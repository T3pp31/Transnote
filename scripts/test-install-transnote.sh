#!/usr/bin/env bash
# インストーラーのトランザクションを一時ディレクトリと macOS コマンドのモックで検証する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MOCK_BIN="$WORK/mock-bin"
MOCK_VOLUMES="$WORK/Volumes"
INSTALLER_DIR="$MOCK_VOLUMES/Transnote Installer"
APPLICATIONS_DIR="$WORK/Applications"
INSTALL_TMP="$WORK/tmp"
BUNDLE_ID='com.transnote.LocalTranscriber'
REAL_MV="$(command -v mv)"
mkdir -p "$MOCK_BIN" "$INSTALLER_DIR/Transnote.app/Contents" "$INSTALL_TMP"

# 実スクリプトの固定 macOS パスのみをサンドボックスへ向ける。
# チェックサム検証・設定読取り・退避・配置・EXIT trap は実際の制御フローを実行する。
python3 - "$ROOT" "$INSTALLER_DIR" "$WORK" <<'PY'
import hashlib
import pathlib
import plistlib
import sys

root, installer, work = map(pathlib.Path, sys.argv[1:])
script = (root / 'scripts/install-transnote.command').read_text()
script = script.replace('/usr/libexec/PlistBuddy', '"${MOCK_BIN}/PlistBuddy"')
script = script.replace('/Volumes/', '${MOCK_VOLUMES}/')
(installer / 'install.command').write_text(script)
config = plistlib.loads((root / 'Config/distribution.plist').read_bytes())
config['LegacyAppNames'].append('Older Transnote')
(installer / 'distribution.plist').write_bytes(plistlib.dumps(config))
dmg = work / 'Transnote.dmg'
dmg.write_bytes(b'test disk image\n')
(work / 'Transnote.dmg.sha256').write_text(hashlib.sha256(dmg.read_bytes()).hexdigest())
PY

cat > "$MOCK_BIN/PlistBuddy" <<'MOCK'
#!/usr/bin/env python3
import plistlib
import sys

try:
    with open(sys.argv[3], 'rb') as stream:
        value = plistlib.load(stream)
    for key in sys.argv[2].removeprefix('Print :').split(':'):
        value = value[int(key)] if isinstance(value, list) else value[key]
    print(value)
except (OSError, KeyError, IndexError, ValueError):
    sys.exit(1)
MOCK

cat > "$MOCK_BIN/ditto" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
phase=stage
[[ "$2" != "$TRANSNOTE_INSTALL_DIR/Transnote.app" ]] || phase=place
printf '%s\n' "$phase" >> "$MOCK_EVENT_LOG"
if [[ "$MOCK_FAIL_PHASE" == "$phase" ]]; then
  mkdir -p "$2"
  printf 'incomplete copy\n' > "$2/marker"
  exit 7
fi
cp -R "$1" "$2"
MOCK

cat > "$MOCK_BIN/mv" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_FAIL_PHASE}" == backup && "${1##*/}" == 'LocalTranscriber 2.app' && "$2" == "$TMPDIR"/transnote-backup.*/* ]]; then
  exit 8
fi
exec "$MOCK_REAL_MV" "$@"
MOCK

cat > "$MOCK_BIN/hdiutil" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == info ]]; then
  printf 'image-path : %s\n    %s\n' "$MOCK_DMG" "$MOCK_INSTALLER_DIR"
fi
MOCK

cat > "$MOCK_BIN/shasum" <<'MOCK'
#!/usr/bin/env bash
python3 - "$@" <<'PY'
import hashlib
import pathlib
import sys

assert sys.argv[1:3] == ['-a', '256']
print(hashlib.sha256(pathlib.Path(sys.argv[3]).read_bytes()).hexdigest())
PY
MOCK

cat > "$MOCK_BIN/open" <<'MOCK'
#!/usr/bin/env bash
printf 'open\n' >> "$MOCK_EVENT_LOG"
MOCK

for tool in osascript sleep xattr; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_BIN/$tool"
done
chmod +x "$MOCK_BIN"/*

make_app() {
  local name="$1" marker="$2" bundle_id="$3"
  mkdir -p "$APPLICATIONS_DIR/$name.app/Contents"
  printf '%s\n' "$marker" > "$APPLICATIONS_DIR/$name.app/marker"
  cat > "$APPLICATIONS_DIR/$name.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>${bundle_id}</string></dict></plist>
PLIST
}

reset_apps() {
  rm -rf "$APPLICATIONS_DIR"
  mkdir -p "$APPLICATIONS_DIR"
  make_app LocalTranscriber 'original legacy' "$BUNDLE_ID"
  make_app 'LocalTranscriber 2' 'original duplicate' "$BUNDLE_ID"
  make_app 'Older Transnote' 'original older name' "$BUNDLE_ID"
  make_app 'LocalTranscriber 3' 'unrelated app' 'org.example.unrelated'
  make_app 'LocalTranscriber 4' 'unknown bundle' ''
  : > "$WORK/events.log"
}

run_install() {
  env PATH="$MOCK_BIN:$PATH" \
    MOCK_BIN="$MOCK_BIN" MOCK_VOLUMES="$MOCK_VOLUMES" \
    MOCK_DMG="$WORK/Transnote.dmg" MOCK_INSTALLER_DIR="$INSTALLER_DIR" \
    MOCK_EVENT_LOG="$WORK/events.log" MOCK_REAL_MV="$REAL_MV" \
    MOCK_FAIL_PHASE="${1:-none}" TMPDIR="$INSTALL_TMP" \
    TRANSNOTE_INSTALL_DIR="$APPLICATIONS_DIR" \
    bash "$INSTALLER_DIR/install.command" > "$WORK/stdout" 2> "$WORK/stderr"
}

fail() {
  echo "FAIL: $*" >&2
  cat "$WORK/stdout" "$WORK/stderr" >&2
  exit 1
}

assert_app() {
  local name="$1" marker="$2"
  [[ -f "$APPLICATIONS_DIR/$name.app/marker" ]] || fail "missing $name.app"
  [[ "$(cat "$APPLICATIONS_DIR/$name.app/marker")" == "$marker" ]] || fail "changed $name.app"
}

assert_legacy_apps() {
  assert_app LocalTranscriber 'original legacy'
  assert_app 'LocalTranscriber 2' 'original duplicate'
  assert_app 'Older Transnote' 'original older name'
  assert_app 'LocalTranscriber 3' 'unrelated app'
  assert_app 'LocalTranscriber 4' 'unknown bundle'
}

assert_clean_tmp() {
  [[ -z "$(find "$INSTALL_TMP" -mindepth 1 -print -quit)" ]] || fail 'temporary files remain'
}

expect_failure() {
  if run_install "$1"; then
    fail "expected install failure: $1"
  fi
  ! grep -q '^open$' "$WORK/events.log" || fail 'failed install launched the app'
  assert_clean_tmp
}

printf 'new version\n' > "$INSTALLER_DIR/Transnote.app/marker"

# 主名のアプリが存在しないユーザーでも、配置失敗で旧名アプリを失わない。
reset_apps
expect_failure place
grep -q '^place$' "$WORK/events.log" || fail 'placement failure was not reached'
assert_legacy_apps
echo 'PASS: placement failure restores all legacy app names and duplicates'

# 主名と旧名の両方がある場合も、各バンドルを元の名前・内容で復元する。
reset_apps
make_app Transnote 'original main' "$BUNDLE_ID"
expect_failure place
assert_app Transnote 'original main'
assert_legacy_apps
echo 'PASS: placement failure restores both main and legacy apps'

# 退避途中の失敗も、既に退避した旧版を復元し、配置へ進まない。
reset_apps
make_app Transnote 'original main' "$BUNDLE_ID"
expect_failure backup
assert_app Transnote 'original main'
assert_legacy_apps
! grep -q '^place$' "$WORK/events.log" || fail 'continued after backup failure'
echo 'PASS: backup failure restores already moved apps'

# ステージへのコピー失敗時は、インストール済みアプリに触れない。
reset_apps
make_app Transnote 'original main' "$BUNDLE_ID"
expect_failure stage
assert_app Transnote 'original main'
assert_legacy_apps
! grep -q '^place$' "$WORK/events.log" || fail 'continued after staging failure'
echo 'PASS: staging failure preserves installed apps'

# 無関係な主名アプリを拒否する既存の安全策を維持する。
reset_apps
make_app Transnote 'unrelated main' 'org.example.unrelated'
expect_failure none
assert_app Transnote 'unrelated main'
assert_legacy_apps
! grep -q '^place$' "$WORK/events.log" || fail 'overwrote mismatched main app'
echo 'PASS: mismatched target Bundle ID preserves every installed app'

# 成功時のみ旧名アプリを破棄する。Bundle ID 不一致・不明のアプリは残す。
reset_apps
make_app Transnote 'original main' "$BUNDLE_ID"
if ! run_install; then
  fail 'expected install success'
fi
assert_app Transnote 'new version'
for name in LocalTranscriber 'LocalTranscriber 2' 'Older Transnote'; do
  [[ ! -e "$APPLICATIONS_DIR/$name.app" ]] || fail "legacy app remains: $name"
done
assert_app 'LocalTranscriber 3' 'unrelated app'
assert_app 'LocalTranscriber 4' 'unknown bundle'
grep -q '^open$' "$WORK/events.log" || fail 'successful install did not launch the app'
assert_clean_tmp
[[ "$(cat "$INSTALLER_DIR/Transnote.app/marker")" == 'new version' ]] || fail 'source app changed'
echo 'PASS: successful install removes only matching legacy apps and cleans backups'

echo 'ALL INSTALL TRANSNOTE TESTS PASSED'
