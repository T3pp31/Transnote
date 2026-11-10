#!/usr/bin/env bash
# Portable regression tests for export-release-app.sh; no macOS keychain needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MOCK_BIN="$WORK/mock-bin"
ARCHIVE="$WORK/Transnote.xcarchive"
OUTPUT="$WORK/output"
MOCK_IDENTITIES="$WORK/identities.txt"
MOCK_SIGN_LOG="$WORK/sign.log"
MOCK_EVENT_LOG="$WORK/events.log"
mkdir -p "$MOCK_BIN" "$ARCHIVE/Products/Applications/Transnote.app" "$OUTPUT"
printf 'original bundle\n' > "$ARCHIVE/Products/Applications/Transnote.app/marker"

cat > "$MOCK_BIN/security" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'find-identity -v -p codesigning' ]] || exit 2
printf 'security\n' >> "$MOCK_EVENT_LOG"
[[ "${MOCK_SECURITY_FAIL:-0}" == 0 ]] || exit 5
cat "$MOCK_IDENTITIES"
MOCK

cat > "$MOCK_BIN/ditto" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'ditto\n' >> "$MOCK_EVENT_LOG"
cp -R "$1" "$2"
MOCK

cat > "$MOCK_BIN/codesign" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  --force)
    printf 'sign\n' >> "$MOCK_EVENT_LOG"
    app="${!#}"
    identity=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" == --sign ]]; then
        identity="$2"
        shift 2
      else
        shift
      fi
    done
    printf '%s\n' "$identity" >> "$MOCK_SIGN_LOG"
    [[ "${MOCK_SIGN_FAIL:-0}" == 0 ]] || exit 7
    touch "$app/.signed"
    ;;
  --verify)
    printf 'verify\n' >> "$MOCK_EVENT_LOG"
    app="${!#}"
    [[ "${MOCK_VERIFY_FAIL:-0}" == 0 && -f "$app/.signed" ]]
    ;;
  -d)
    printf 'display\n' >> "$MOCK_EVENT_LOG"
    app="${!#}"
    [[ -f "$app/.signed" ]]
    ;;
  *) exit 2 ;;
esac
MOCK

cat > "$MOCK_BIN/spctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'spctl\n' >> "$MOCK_EVENT_LOG"
exit 0
MOCK
chmod +x "$MOCK_BIN"/*

TEAM='ABCDE12345'
OTHER_TEAM='ZYXWV98765'
IDENTITY="Developer ID Application: Test Developer (${TEAM})"
OTHER_IDENTITY="Developer ID Application: Other Developer (${OTHER_TEAM})"
FINGERPRINT='0123456789ABCDEF0123456789ABCDEF01234567'
OTHER_FINGERPRINT='89ABCDEF0123456789ABCDEF0123456789ABCDEF'
printf '  1) %s "%s"\n  2) %s "%s"\n     2 valid identities found\n' \
  "$FINGERPRINT" "$IDENTITY" "$OTHER_FINGERPRINT" "$OTHER_IDENTITY" > "$MOCK_IDENTITIES"

run_export() {
  : > "$MOCK_SIGN_LOG"
  : > "$MOCK_EVENT_LOG"
  PATH="$MOCK_BIN:$PATH" \
    MOCK_IDENTITIES="$MOCK_IDENTITIES" \
    MOCK_SIGN_LOG="$MOCK_SIGN_LOG" \
    MOCK_EVENT_LOG="$MOCK_EVENT_LOG" \
    MOCK_SIGN_FAIL="${MOCK_SIGN_FAIL:-0}" \
    MOCK_VERIFY_FAIL="${MOCK_VERIFY_FAIL:-0}" \
    MOCK_SECURITY_FAIL="${MOCK_SECURITY_FAIL:-0}" \
    bash "$ROOT/scripts/export-release-app.sh" \
      --archive "$ARCHIVE" --output "$OUTPUT" "$@" \
      > "$WORK/stdout" 2> "$WORK/stderr"
}

fail() {
  echo "FAIL: $*" >&2
  cat "$WORK/stdout" "$WORK/stderr" >&2
  exit 1
}

expect_success() {
  if ! run_export "$@"; then
    fail "expected export success: $*"
  fi
}

expect_failure() {
  if run_export "$@"; then
    fail "expected export failure: $*"
  fi
  if grep -q '^Exported ' "$WORK/stdout"; then
    fail "failed export must not report success"
  fi
}

# First exports must create missing output directories before resolving their paths.
for new_output in "$WORK/new output/nested" 'relative output/nested'; do
  (
    cd "$WORK"
    [[ ! -e "$new_output" ]] || fail 'output fixture already exists'
    expect_success --output "$new_output"
    [[ ! -s "$WORK/stderr" ]] || fail 'new output directory produced an error'
    cmp "$ARCHIVE/Products/Applications/Transnote.app/marker" \
      "$new_output/Transnote.app/marker" || fail 'new output has incorrect bundle contents'
  )
done
echo 'PASS: missing absolute and relative output directories are created without errors'

# Resolving an existing output, including a symlink alias, must still protect the source.
ln -s "$ARCHIVE/Products/Applications" "$WORK/source applications"
for overlapping_output in "$ARCHIVE/Products/Applications" "$WORK/source applications"; do
  expect_failure --output "$overlapping_output"
  grep -q -- '--output overlaps the source app' "$WORK/stderr" || fail 'missing overlap error'
  [[ ! -s "$MOCK_EVENT_LOG" ]] || fail 'overlapping output ran a macOS tool'
  [[ "$(cat "$ARCHIVE/Products/Applications/Transnote.app/marker")" == 'original bundle' ]] \
    || fail 'overlapping output modified the source app'
done
echo 'PASS: source overlap is rejected for direct and symlink paths'

# An output app that would contain the archive must not be removed either.
NESTED_ARCHIVE="$WORK/overlap/Transnote.app/Transnote.xcarchive"
mkdir -p "$(dirname "$NESTED_ARCHIVE")"
cp -R "$ARCHIVE" "$NESTED_ARCHIVE"
expect_failure --archive "$NESTED_ARCHIVE" --output "$WORK/overlap"
grep -q -- '--output overlaps the source app' "$WORK/stderr" || fail 'missing ancestor overlap error'
[[ ! -s "$MOCK_EVENT_LOG" ]] || fail 'ancestor overlap ran a macOS tool'
[[ "$(cat "$NESTED_ARCHIVE/Products/Applications/Transnote.app/marker")" == 'original bundle' ]] \
  || fail 'ancestor overlap modified the source app'
echo 'PASS: output containing the source archive is rejected'

# Directory creation failures must stop the export before copying or verification.
printf 'not a directory\n' > "$WORK/blocked-output"
expect_failure --output "$WORK/blocked-output/nested"
[[ ! -s "$MOCK_EVENT_LOG" ]] || fail 'failed directory creation ran a macOS tool'
[[ "$(cat "$WORK/blocked-output")" == 'not a directory' ]] || fail 'blocking file was modified'
[[ "$(cat "$ARCHIVE/Products/Applications/Transnote.app/marker")" == 'original bundle' ]] \
  || fail 'failed directory creation modified the source app'
echo 'PASS: output directory creation failure stops the export'

# Providing both flags must never replace the requested certificate with Team ID.
expect_success --sign "$IDENTITY" --team "$TEAM"
[[ "$(cat "$MOCK_SIGN_LOG")" == "$IDENTITY" ]] || fail 'certificate name was overwritten'
[[ -f "$OUTPUT/Transnote.app/.signed" ]] || fail 'app was not signed'
echo 'PASS: --sign and --team preserve certificate identity'

# A SHA-1 identity should be supported, including lowercase fingerprints.
LOWERCASE_FINGERPRINT="$(printf '%s' "$FINGERPRINT" | tr '[:upper:]' '[:lower:]')"
expect_success --sign "$LOWERCASE_FINGERPRINT" --team "$TEAM"
[[ "$(cat "$MOCK_SIGN_LOG")" == "$LOWERCASE_FINGERPRINT" ]] || fail 'fingerprint was overwritten'
echo 'PASS: fingerprint signing identity with --team'

# Reject an identity from another Team before overwriting the exported app.
printf 'keep existing app\n' > "$OUTPUT/Transnote.app/keep"
expect_failure --sign "$IDENTITY" --team "$OTHER_TEAM"
grep -q 'does not belong to Team ID' "$WORK/stderr" || fail 'missing Team mismatch error'
[[ ! -s "$MOCK_SIGN_LOG" ]] || fail 'mismatched Team attempted signing'
! grep -q '^ditto$' "$MOCK_EVENT_LOG" || fail 'mismatched Team copied the app'
[[ -f "$OUTPUT/Transnote.app/keep" ]] || fail 'mismatched Team deleted existing export'
echo 'PASS: mismatched Team rejected before copying'

expect_failure --team "$TEAM"
grep -q -- '--team requires --sign' "$WORK/stderr" || fail 'missing --sign requirement'
[[ ! -s "$MOCK_EVENT_LOG" ]] || fail '--team alone ran a macOS tool'
echo 'PASS: --team without --sign rejected'

expect_failure --sign "$IDENTITY" --team 'bad-team'
grep -q 'Invalid --team' "$WORK/stderr" || fail 'missing invalid Team error'
[[ ! -s "$MOCK_EVENT_LOG" ]] || fail 'invalid Team ran a macOS tool'
echo 'PASS: invalid Team ID rejected'

expect_failure --sign 'Developer ID Application: Missing (ABCDE12345)' --team "$TEAM"
grep -q 'was not found' "$WORK/stderr" || fail 'missing identity error'
! grep -q '^ditto$' "$MOCK_EVENT_LOG" || fail 'missing identity copied the app'
echo 'PASS: unknown signing identity rejected'

MOCK_SECURITY_FAIL=1
expect_failure --sign "$IDENTITY" --team "$TEAM"
grep -q 'Could not list valid codesigning identities' "$WORK/stderr" || fail 'missing keychain error'
! grep -q '^ditto$' "$MOCK_EVENT_LOG" || fail 'keychain failure copied the app'
unset MOCK_SECURITY_FAIL
echo 'PASS: keychain lookup failure rejected'

MOCK_SIGN_FAIL=1
expect_failure --sign "$IDENTITY" --team "$TEAM"
grep -q 'Failed to sign' "$WORK/stderr" || fail 'missing signing failure error'
! grep -q '^verify$' "$MOCK_EVENT_LOG" || fail 'continued to verification after signing failed'
unset MOCK_SIGN_FAIL
echo 'PASS: codesign failure is fatal'

MOCK_VERIFY_FAIL=1
expect_failure --sign "$IDENTITY" --team "$TEAM"
grep -q 'Signature verification failed' "$WORK/stderr" || fail 'verification failure was ignored'
! grep -q '^spctl$' "$MOCK_EVENT_LOG" || fail 'spctl should not run after verification failure'
unset MOCK_VERIFY_FAIL
echo 'PASS: signature verification failure is fatal'

# Preserve the existing unsigned export behavior if no signing was requested.
expect_success
[[ ! -s "$MOCK_SIGN_LOG" ]] || fail 'unsigned export unexpectedly signed'
grep -q 'App is unsigned; skipping signature verification.' "$WORK/stdout" || fail 'unsigned export changed behavior'
echo 'PASS: unsigned export still allowed without --sign'

# --sign should not require keychain identity enumeration when --team is absent.
MOCK_SECURITY_FAIL=1
expect_success --sign "$IDENTITY"
[[ "$(cat "$MOCK_SIGN_LOG")" == "$IDENTITY" ]] || fail '--sign alone changed identity'
! grep -q '^security$' "$MOCK_EVENT_LOG" || fail '--sign alone searched keychain'
unset MOCK_SECURITY_FAIL
echo 'PASS: --sign alone retains existing behavior'

# Reject exports into the source bundle before deleting any existing destination.
SOURCE_APP="$ARCHIVE/Products/Applications/Transnote.app"
mkdir -p "$SOURCE_APP/Transnote.app" "$SOURCE_APP/out/Transnote.app"
printf 'keep direct destination\n' > "$SOURCE_APP/Transnote.app/keep"
printf 'keep nested destination\n' > "$SOURCE_APP/out/Transnote.app/keep"
ln -s "$SOURCE_APP/out" "$WORK/source-output-link"
for overlap_output in "$SOURCE_APP" "$SOURCE_APP/out" "$WORK/source-output-link"; do
  expect_failure --output "$overlap_output"
  grep -q -- '--output overlaps the source app' "$WORK/stderr" || fail 'missing overlap error'
  [[ ! -s "$MOCK_EVENT_LOG" ]] || fail 'overlapping export ran a macOS tool'
  [[ "$(cat "$SOURCE_APP/marker")" == 'original bundle' ]] || fail 'source bundle was modified'
  [[ "$(cat "$SOURCE_APP/Transnote.app/keep")" == 'keep direct destination' ]] || fail 'direct destination was deleted'
  [[ "$(cat "$SOURCE_APP/out/Transnote.app/keep")" == 'keep nested destination' ]] || fail 'nested destination was deleted'
done
echo 'PASS: outputs inside the source bundle rejected, including symlink aliases'

# The existing equality guard must still protect the source app itself.
expect_failure --output "$(dirname "$SOURCE_APP")"
grep -q -- '--output overlaps the source app' "$WORK/stderr" || fail 'missing same-path overlap error'
[[ ! -s "$MOCK_EVENT_LOG" ]] || fail 'same-path export ran a macOS tool'
[[ "$(cat "$SOURCE_APP/marker")" == 'original bundle' ]] || fail 'same-path export modified source'
echo 'PASS: output equal to the source app rejected'

# Preserve the guard against deleting a destination that contains the source app.
CONTAINING_OUTPUT="$WORK/container"
NESTED_ARCHIVE="$CONTAINING_OUTPUT/Transnote.app/Transnote.xcarchive"
NESTED_SOURCE="$NESTED_ARCHIVE/Products/Applications/Transnote.app"
mkdir -p "$NESTED_SOURCE"
printf 'nested source bundle\n' > "$NESTED_SOURCE/marker"
expect_failure --archive "$NESTED_ARCHIVE" --output "$CONTAINING_OUTPUT"
grep -q -- '--output overlaps the source app' "$WORK/stderr" || fail 'missing ancestor overlap error'
[[ ! -s "$MOCK_EVENT_LOG" ]] || fail 'ancestor export ran a macOS tool'
[[ "$(cat "$NESTED_SOURCE/marker")" == 'nested source bundle' ]] || fail 'ancestor export modified source'
echo 'PASS: output containing the source app rejected'

# A sibling whose name shares the source path prefix is not inside the bundle.
PREFIX_OUTPUT="${SOURCE_APP}-export"
mkdir -p "$PREFIX_OUTPUT"
expect_success --output "$PREFIX_OUTPUT"
[[ "$(cat "$PREFIX_OUTPUT/Transnote.app/marker")" == 'original bundle' ]] || fail 'non-overlapping export was not copied'
echo 'PASS: sibling with matching path prefix can be exported'

echo 'ALL EXPORT RELEASE APP TESTS PASSED'
