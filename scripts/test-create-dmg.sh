#!/usr/bin/env bash
# Portable regression tests for create-dmg.sh; no macOS disk images are mounted.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FIXTURE="$WORK/project"
MOCK_BIN="$WORK/mock-bin"
mkdir -p "$FIXTURE/scripts" "$FIXTURE/Config" "$MOCK_BIN" "$WORK/input app/Transnote.app"
cp "$ROOT/scripts/create-dmg.sh" "$ROOT/scripts/install-transnote.command" \
  "$ROOT/scripts/release-security-notice.sh" "$FIXTURE/scripts/"
cp "$ROOT/Config/distribution.plist" "$ROOT/Config/dmg-gatekeeper-readme.txt" "$FIXTURE/Config/"
printf 'app contents\n' > "$WORK/input app/Transnote.app/marker"

# Only the fixture uses PATH lookup for PlistBuddy, so Linux can read the real config.
python3 - "$FIXTURE/scripts/create-dmg.sh" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
script = path.read_text()
assert script.count('/usr/libexec/PlistBuddy') == 2
path.write_text(script.replace('/usr/libexec/PlistBuddy', 'PlistBuddy'))
PY

cat > "$MOCK_BIN/PlistBuddy" <<'MOCK'
#!/usr/bin/env python3
import plistlib
import sys

assert sys.argv[1] == '-c'
command, key = sys.argv[2].split(' :')
assert command == 'Print'
with open(sys.argv[3], 'rb') as stream:
    print(plistlib.load(stream)[key])
MOCK

cat > "$MOCK_BIN/hdiutil" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
step="$1"
shift
printf '%s\n' "$step" >> "$MOCK_CASE/events"
case "$step" in
  create)
    [[ $# -eq 8 && "$1" == -volname && "$3" == -srcfolder && "$5" == -ov && "$6" == -format && "$7" == UDRW ]]
    stage="$4"
    image="$8"
    printf '%s\n' "$stage" > "$MOCK_CASE/stage"
    # Model hdiutil's automatic extension, not a mock that blindly writes $8.
    [[ "$image" == *.dmg ]] || image="${image}.dmg"
    printf '%s\n' "$image" > "$MOCK_CASE/image"
    [[ "$image" != "$stage/"* ]]
    [[ -f "$stage/Transnote.app/marker" && -f "$stage/distribution.plist" ]]
    [[ -f "$stage/インストール.command" && -f "$stage/初めにお読みください.txt" ]]
    cp "$stage/初めにお読みください.txt" "$MOCK_CASE/readme.txt"
    [[ -L "$stage/Applications" && "$(readlink "$stage/Applications")" == /Applications ]]
    printf 'UDRW mock image\n' > "$image"
    ;;
  convert)
    [[ $# -eq 7 && "$2" == -format && "$3" == UDZO && "$4" == -imagekey && "$5" == zlib-level=9 && "$6" == -o ]]
    if [[ "$1" != "$(cat "$MOCK_CASE/image")" || ! -s "$1" ]]; then
      echo "convert input is not the created image: $1 (created: $(cat "$MOCK_CASE/image"))" >&2
      exit 1
    fi
    [[ "$(cat "$1")" == 'UDRW mock image' ]]
    printf 'UDZO mock image\n' > "$7"
    ;;
  verify)
    [[ $# -eq 1 && -s "$1" && "$(cat "$1")" == 'UDZO mock image' ]]
    ;;
  *) exit 2 ;;
esac
[[ "$step" != "${MOCK_FAIL_STEP:-}" ]] || exit 9
MOCK
chmod +x "$MOCK_BIN"/*

fail() {
  echo "FAIL: $*" >&2
  cat "$CASE_DIR/stdout" "$CASE_DIR/stderr" >&2
  exit 1
}

run_case() {
  local failure_step="$1"
  local signing_state="${2:-unsigned}"
  local signed=0 notarized=0
  [[ "$signing_state" == unsigned ]] || signed=1
  [[ "$signing_state" != notarized ]] || notarized=1
  CASE_DIR="$WORK/$signing_state ${failure_step:-success} case"
  mkdir -p "$CASE_DIR/tmp space"
  local status=0
  PATH="$MOCK_BIN:$PATH" TMPDIR="$CASE_DIR/tmp space" \
    SIGNED="$signed" NOTARIZED="$notarized" \
    MOCK_CASE="$CASE_DIR" MOCK_FAIL_STEP="$failure_step" \
    bash "$FIXTURE/scripts/create-dmg.sh" \
      --app "$WORK/input app/Transnote.app" --version 1.2.3 --output "$CASE_DIR/output space" \
      > "$CASE_DIR/stdout" 2> "$CASE_DIR/stderr" || status=$?

  if [[ -z "$failure_step" ]]; then
    [[ "$status" -eq 0 ]] || fail 'DMG creation should succeed'
    [[ -s "$CASE_DIR/output space/Transnote-1.2.3.dmg" ]] || fail 'missing final DMG'
    grep -q '^Created ' "$CASE_DIR/stdout" || fail 'missing success message'
    [[ "$(cat "$CASE_DIR/events")" == $'create\nconvert\nverify' ]] || fail 'incorrect operation order'
  else
    [[ "$status" -ne 0 ]] || fail "$failure_step failure should be fatal"
    ! grep -q '^Created ' "$CASE_DIR/stdout" || fail 'failed creation reported success'
    local expected=create
    [[ "$failure_step" == create ]] || expected+=$'\nconvert'
    [[ "$failure_step" != verify ]] || expected+=$'\nverify'
    [[ "$(cat "$CASE_DIR/events")" == "$expected" ]] || fail "continued after $failure_step failure"
  fi

  python3 - "$ROOT/Config/dmg-gatekeeper-readme.txt" "$CASE_DIR/readme.txt" "$signing_state" <<'PY'
from pathlib import Path
import sys

prefix, suffix = Path(sys.argv[1]).read_text().split('@SECURITY_NOTICE@')
readme = Path(sys.argv[2]).read_text()
assert '@SECURITY_NOTICE@' not in readme, 'unexpanded notice placeholder'
assert readme.startswith(prefix) and readme.endswith(suffix), 'installation steps changed'
notice = readme[len(prefix):-len(suffix)]
state = sys.argv[3]
if state == 'unsigned':
    assert '署名）をせずに配布しているため' in notice, 'missing unsigned warning'
else:
    expected = {
        'signed': 'Developer ID で署名済みのビルドです。公証は行われていません。',
        'notarized': 'Developer ID で署名・公証済みのビルドです。',
    }
    assert notice == expected[state], 'incorrect signing/notarization notice'
    assert '未署名' not in readme and '署名がないため' not in readme, 'stale unsigned claim'
PY

  [[ ! -e "$(cat "$CASE_DIR/stage")" ]] || fail 'staging directory leaked'
  [[ ! -e "$(cat "$CASE_DIR/image")" ]] || fail 'writable image leaked'
  [[ -z "$(ls -A "$CASE_DIR/tmp space")" ]] || fail 'temporary files or directories leaked'
  [[ -f "$WORK/input app/Transnote.app/marker" ]] || fail 'input app was removed'
  echo "PASS: create-dmg $signing_state ${failure_step:-success} and temporary cleanup (paths with spaces)"
}

run_case ''
run_case '' signed
run_case '' notarized
run_case create
run_case convert
run_case verify

echo 'ALL CREATE DMG TESTS PASSED'
