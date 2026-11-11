#!/usr/bin/env bash
# Portable transaction regression tests; no mounted DMG or macOS tools needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MOCK_BIN="$WORK/mock-bin"
INSTALLER_DIR="$WORK/installer"
APPLICATIONS_DIR="$WORK/Applications"
TARGET_APP="$APPLICATIONS_DIR/Transnote.app"
INSTALL_TMP="$WORK/install tmp"
EVENT_LOG="$WORK/events.log"
REAL_MV="$(type -P mv)"
REAL_RM="$(type -P rm)"
mkdir -p "$MOCK_BIN" "$INSTALLER_DIR"
cp "$ROOT/Config/distribution.plist" "$INSTALLER_DIR/distribution.plist"

# Run the real installer, changing only the absolute macOS plist-tool path and
# the DMG checksum invocation. These tests cover the transaction after validation,
# not DMG discovery or checksum verification. No production bypass is added.
sed -e 's@/usr/libexec/PlistBuddy@PlistBuddy@g' \
  -e 's/^verify_dmg_checksum$/: # DMG validation is outside these transaction tests/' \
  "$ROOT/scripts/install-transnote.command" > "$INSTALLER_DIR/install.command"

cat > "$MOCK_BIN/PlistBuddy" <<'MOCK'
#!/usr/bin/env python3
import plistlib
import sys

try:
    with open(sys.argv[3], "rb") as stream:
        value = plistlib.load(stream)
    for key in sys.argv[2].split(" :", 1)[1].split(":"):
        value = value[int(key)] if isinstance(value, list) else value[key]
    print(value)
except (OSError, ValueError, KeyError, IndexError):
    sys.exit(1)
MOCK

cat > "$MOCK_BIN/ditto" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
phase=staging
[[ "$2" != "$TRANSNOTE_INSTALL_DIR/Transnote.app" ]] || phase=placement
printf '%s\n' "$phase" >> "$EVENT_LOG"
if [[ "$phase" == "${MOCK_FAIL_PHASE:-}" ]]; then
  mkdir -p "$2/Contents"
  printf 'incomplete bundle\n' > "$2/Contents/partial"
  exit 17
fi
cp -R "$1" "$2"
MOCK

cat > "$MOCK_BIN/mv" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_FAIL_BACKUP:-0}" == 1 && "$1" == "$TRANSNOTE_INSTALL_DIR/Transnote.app" ]]; then
  exit 19
fi
if [[ "${MOCK_FAIL_BACKUP:-0}" == partial && "$1" == "$TRANSNOTE_INSTALL_DIR/Transnote.app" ]]; then
  mkdir -p "$2/Contents"
  printf 'partial backup\n' > "$2/Contents/partial"
  exit 19
fi
if [[ "${MOCK_FAIL_RESTORE:-0}" == 1 && "$1" == "$TMPDIR"/transnote-backup*/* ]]; then
  exit 20
fi
exec "$REAL_MV" "$@"
MOCK

cat > "$MOCK_BIN/rm" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MOCK_FAIL_CLEANUP:-0}" == 1 && "$#" == 3 && "$2" == "$TMPDIR"/transnote-backup* && "$3" == "$TMPDIR"/transnote-install* ]]; then
  exit 21
fi
exec "$REAL_RM" "$@"
MOCK

for tool in osascript sleep xattr open; do
  cat > "$MOCK_BIN/$tool" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${0##*/}" "$*" >> "$EVENT_LOG"
MOCK
done
chmod +x "$MOCK_BIN"/*

make_app() {
  local app="$1" marker="$2" bundle_id="$3"
  mkdir -p "$app/Contents"
  printf '%s\n' "$marker" > "$app/Contents/marker"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${bundle_id}</string>
</dict></plist>
PLIST
}

make_app "$INSTALLER_DIR/Transnote.app" new com.transnote.LocalTranscriber

reset_case() {
  rm -rf "$APPLICATIONS_DIR" "$INSTALL_TMP" "$WORK/expected-old.app"
  mkdir -p "$APPLICATIONS_DIR" "$INSTALL_TMP"
  : > "$EVENT_LOG"
}

make_old_app() {
  make_app "$TARGET_APP" old "$1"
  cp -R "$TARGET_APP" "$WORK/expected-old.app"
}

run_install() {
  PATH="$MOCK_BIN:$PATH" TRANSNOTE_INSTALL_DIR="$APPLICATIONS_DIR" \
    TMPDIR="$INSTALL_TMP" EVENT_LOG="$EVENT_LOG" REAL_MV="$REAL_MV" REAL_RM="$REAL_RM" \
    MOCK_FAIL_PHASE="${MOCK_FAIL_PHASE:-}" MOCK_FAIL_BACKUP="${MOCK_FAIL_BACKUP:-0}" \
    MOCK_FAIL_RESTORE="${MOCK_FAIL_RESTORE:-0}" MOCK_FAIL_CLEANUP="${MOCK_FAIL_CLEANUP:-0}" \
    bash "$INSTALLER_DIR/install.command" > "$WORK/stdout" 2> "$WORK/stderr"
}

fail() {
  echo "FAIL: $*" >&2
  cat "$WORK/stdout" "$WORK/stderr" >&2
  exit 1
}

expect_failure() {
  local expected_code="$1" message="${2:-}" code=0
  run_install || code=$?
  [[ "$code" == "$expected_code" ]] || fail "expected exit $expected_code, got $code"
  if [[ -n "$message" ]]; then
    grep -qF "$message" "$EVENT_LOG" || fail "missing failure alert: $message"
  fi
  ! grep -q '^open$' "$EVENT_LOG" || fail 'failed install launched the app'
  assert_clean_tmp
}

assert_clean_tmp() {
  [[ -z "$(ls -A "$INSTALL_TMP")" ]] || fail 'staging or backup directory remains'
}

assert_old_app() {
  diff -r "$WORK/expected-old.app" "$TARGET_APP" || fail 'old app was changed or lost'
}

assert_no_placement() {
  ! grep -q '^placement$' "$EVENT_LOG" || fail 'placement started before validation/backup completed'
}

# Reproduce a ditto failure after it has already created part of the target.
reset_case
MOCK_FAIL_PHASE=placement
expect_failure 1 '新バージョンの配置に失敗しました。'
grep -q '^placement$' "$EVENT_LOG" || fail 'placement failure was not exercised'
[[ ! -e "$TARGET_APP" ]] || fail 'fresh install failure left a partial target bundle'
echo 'PASS: fresh install placement failure removes the partial bundle'

reset_case
make_old_app com.transnote.LocalTranscriber
expect_failure 1 '新バージョンの配置に失敗しました。'
assert_old_app
echo 'PASS: upgrade placement failure restores the old bundle'
unset MOCK_FAIL_PHASE

# Failures before placement must not delete an app that has not been backed up.
for installed in absent present; do
  reset_case
  if [[ "$installed" == present ]]; then
    make_old_app com.transnote.LocalTranscriber
  fi
  MOCK_FAIL_PHASE=staging
  expect_failure 1 '新バージョンのコピーに失敗しました。'
  grep -q '^staging$' "$EVENT_LOG" || fail 'staging failure was not exercised'
  assert_no_placement
  if [[ "$installed" == present ]]; then
    assert_old_app
  else
    [[ ! -e "$TARGET_APP" ]] || fail 'staging failure created a target bundle'
  fi
  echo "PASS: staging failure preserves the original state ($installed)"
done
unset MOCK_FAIL_PHASE

for bundle_id in com.example.Unrelated ''; do
  reset_case
  make_old_app "$bundle_id"
  expect_failure 1 'Bundle ID が一致しません'
  assert_no_placement
  assert_old_app
  echo "PASS: rejected Bundle ID preserves the existing bundle (${bundle_id:-empty})"
done

reset_case
make_old_app com.transnote.LocalTranscriber
MOCK_FAIL_BACKUP=1
expect_failure 19
assert_no_placement
assert_old_app
unset MOCK_FAIL_BACKUP
echo 'PASS: backup move failure preserves the old bundle'

for installed in absent present; do
  reset_case
  if [[ "$installed" == present ]]; then
    make_old_app com.transnote.LocalTranscriber
  fi
  run_install || fail 'expected install success'
  diff -r "$INSTALLER_DIR/Transnote.app" "$TARGET_APP" || fail 'new app was not installed intact'
  assert_clean_tmp
  grep -q '^open$' "$EVENT_LOG" || fail 'successful install did not launch the app'
  echo "PASS: successful install keeps the new bundle ($installed)"
done

# Cross-volume mv may leave a partial backup while the intact source remains.
reset_case
make_old_app com.transnote.LocalTranscriber
MOCK_FAIL_BACKUP=partial
expect_failure 19
assert_no_placement
assert_old_app
unset MOCK_FAIL_BACKUP
echo 'PASS: partial backup failure preserves the original bundle'

for existing_path in file broken-link; do
  reset_case
  if [[ "$existing_path" == file ]]; then
    printf 'unrelated file\n' > "$TARGET_APP"
  else
    ln -s "$WORK/missing.app" "$TARGET_APP"
  fi
  expect_failure 1 '配置先にアプリ以外のファイルまたはリンクがあります'
  assert_no_placement
  if [[ "$existing_path" == file ]]; then
    [[ "$(cat "$TARGET_APP")" == 'unrelated file' ]] || fail 'existing file was changed'
  else
    [[ -L "$TARGET_APP" && "$(readlink "$TARGET_APP")" == "$WORK/missing.app" ]] || fail 'existing link was changed'
  fi
  echo "PASS: existing $existing_path is preserved"
done

reset_case
make_old_app com.transnote.LocalTranscriber
MOCK_FAIL_PHASE=placement
MOCK_FAIL_RESTORE=1
code=0
run_install || code=$?
[[ "$code" != 0 && ! -e "$TARGET_APP" ]] || fail 'restore failure must remain observable without a partial target'
backup_marker="$(find "$INSTALL_TMP" -path '*/Transnote.app/Contents/marker' -print -quit)"
[[ -n "$backup_marker" && "$(cat "$backup_marker")" == old ]] || fail 'restore failure lost the original backup'
grep -q 'バックアップを保存しています' "$WORK/stderr" || fail 'missing recovery path'
unset MOCK_FAIL_PHASE MOCK_FAIL_RESTORE
[[ ! -e "$APPLICATIONS_DIR/.transnote-install.lock" ]] || fail 'restore failure left the installer lock'
echo 'PASS: failed restoration retains a recoverable backup' 

reset_case
make_old_app com.transnote.LocalTranscriber
MOCK_FAIL_CLEANUP=1
code=0
run_install || code=$?
[[ "$code" == 21 ]] || fail 'cleanup failure must remain observable'
diff -r "$INSTALLER_DIR/Transnote.app" "$TARGET_APP" || fail 'cleanup failure deleted the committed app'
unset MOCK_FAIL_CLEANUP
[[ ! -e "$APPLICATIONS_DIR/.transnote-install.lock" ]] || fail 'cleanup failure left the installer lock'
echo 'PASS: cleanup failure preserves the installed new bundle' 

echo 'ALL INSTALL TRANSACTION TESTS PASSED' 
