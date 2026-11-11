#!/usr/bin/env bash
# インストーラの一時領域とトランザクションを macOS のコマンドなしで検証する。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(command mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/dmg/Transnote.app" "$WORK/Applications" "$WORK/temporary files"
printf 'new app\n' > "$WORK/dmg/Transnote.app/marker"
: > "$WORK/dmg/distribution.plist"

# macOS 固有の境界のみ差し替える。チェックサム検証はこのテストの対象外。
# 一時領域の作成、コピー、退避、EXIT trap は元のスクリプトをそのまま実行する。
sed -e 's|/usr/libexec/PlistBuddy|mock_plist_buddy|g' \
  -e 's/^verify_dmg_checksum$/: # checksum verification mocked for transaction tests/' \
  "$ROOT/scripts/install-transnote.command" > "$WORK/dmg/install.command"

cat > "$WORK/mocks.sh" <<'MOCK'
mock_plist_buddy() {
  case "$2" in
    'Print :AppName') printf 'Transnote\n' ;;
    'Print :BundleIdentifier'|'Print :CFBundleIdentifier') printf 'com.transnote.test\n' ;;
    'Print :LegacyAppNames:'*) return 1 ;;
    *) return 2 ;;
  esac
}
osascript() { printf '%s\n' "$*" >> "$TEST_WORK/alerts"; }
sleep() { :; }
open() { printf '%s\n' "$*" >> "$TEST_WORK/opened"; }
xattr() { :; }
mktemp() {
  printf '%s\n' "$*" >> "$TEST_WORK/mktemp-calls"
  if [[ "$*" == *"${MOCK_MKTEMP_FAIL:-no-failure}"* ]]; then
    return 1
  fi
  local created
  created="$(command mktemp "$@")" || return 1
  printf '%s\n' "$created" >> "$TEST_WORK/created"
  # mktemp が実際に作ったディレクトリのアクセス権を、削除前に確認する。
  [[ -d "$created" && ! -L "$created" ]] || return 1
  [[ "$(LC_ALL=C ls -ld "$created")" == drwx------* ]] || return 1
  printf '%s\n' "$created"
}
ditto() {
  printf '%s\n' "$2" >> "$TEST_WORK/copies"
  if [[ "${MOCK_COPY_FAIL:-}" == stage && "$2" != "$TRANSNOTE_INSTALL_DIR/Transnote.app" ]]; then
    return 1
  fi
  if [[ "${MOCK_COPY_FAIL:-}" == install && "$2" == "$TRANSNOTE_INSTALL_DIR/Transnote.app" ]]; then
    mkdir -p "$2"
    printf 'partial app\n' > "$2/partial"
    return 1
  fi
  cp -R "$1" "$2"
}
MOCK

fail() {
  echo "FAIL: $*" >&2
  cat "$WORK/stdout" "$WORK/stderr" >&2
  exit 1
}

reset_case() {
  rm -rf "$WORK/Applications/Transnote.app"
  mkdir -p "$WORK/Applications/Transnote.app"
  printf 'old app\n' > "$WORK/Applications/Transnote.app/marker"
  : > "$WORK/created"
  : > "$WORK/mktemp-calls"
  : > "$WORK/copies"
  : > "$WORK/alerts"
  : > "$WORK/opened"
}

run_install() {
  TEST_WORK="$WORK" TMPDIR="$WORK/temporary files/" \
    TRANSNOTE_INSTALL_DIR="$WORK/Applications" \
    MOCK_COPY_FAIL="${MOCK_COPY_FAIL:-}" MOCK_MKTEMP_FAIL="${MOCK_MKTEMP_FAIL:-}" \
    MOCK_PRESEED="${MOCK_PRESEED:-0}" \
    bash -c '
      source "$TEST_WORK/mocks.sh"
      if [[ "$MOCK_PRESEED" == 1 ]]; then
        mkdir -p "$TEST_WORK/stage-victim" "$TEST_WORK/backup-victim"
        printf "untouched\n" > "$TEST_WORK/stage-victim/sentinel"
        printf "untouched\n" > "$TEST_WORK/backup-victim/sentinel"
        ln -s "$TEST_WORK/stage-victim" "${TMPDIR}/transnote-install-$$"
        ln -s "$TEST_WORK/backup-victim" "${TMPDIR}/transnote-backup-$$"
        printf "%s\n" "${TMPDIR}/transnote-install-$$" "${TMPDIR}/transnote-backup-$$" > "$TEST_WORK/preseeded"
      fi
      umask 000
      source "$0"
    ' "$WORK/dmg/install.command" > "$WORK/stdout" 2> "$WORK/stderr"
}

assert_cleaned() {
  local created
  while IFS= read -r created; do
    [[ ! -e "$created" && ! -L "$created" ]] || fail "temporary directory leaked: $created"
  done < "$WORK/created"
}

assert_failure_preserves_app() {
  if run_install; then
    fail 'install should have failed'
  fi
  [[ "$(cat "$WORK/Applications/Transnote.app/marker")" == 'old app' ]] || fail 'old app was not preserved'
  [[ ! -e "$WORK/Applications/Transnote.app/partial" ]] || fail 'partial copy was not removed'
  [[ ! -s "$WORK/opened" ]] || fail 'failed install opened the app'
  grep -q 'インストールエラー' "$WORK/alerts" || fail 'failed install did not report an error'
  assert_cleaned
}

reset_case
MOCK_PRESEED=1
if ! run_install; then
  fail 'install with pre-existing PID symlinks should succeed safely'
fi
unset MOCK_PRESEED
[[ "$(cat "$WORK/Applications/Transnote.app/marker")" == 'new app' ]] || fail 'new app was not installed'
[[ "$(cat "$WORK/stage-victim/sentinel")" == untouched ]] || fail 'stage symlink target was modified'
[[ "$(cat "$WORK/backup-victim/sentinel")" == untouched ]] || fail 'backup symlink target was modified'
[[ ! -e "$WORK/stage-victim/Transnote.app" && ! -e "$WORK/backup-victim/Transnote.app" ]] || fail 'pre-existing symlink was followed'
while IFS= read -r link; do
  [[ -L "$link" ]] || fail 'pre-existing symlink was removed'
done < "$WORK/preseeded"
[[ "$(wc -l < "$WORK/created")" -eq 2 ]] || fail 'stage and backup must use mktemp'
[[ "$(wc -l < "$WORK/copies")" -eq 2 ]] || fail 'expected staging and installation copies'
[[ -s "$WORK/opened" ]] || fail 'successful install did not open the app'
assert_cleaned
echo 'PASS: private mktemp directories ignore PID symlinks and are cleaned after success'

for phase in stage install; do
  reset_case
  MOCK_COPY_FAIL="$phase"
  assert_failure_preserves_app
  unset MOCK_COPY_FAIL
  [[ "$(wc -l < "$WORK/created")" -eq 2 ]] || fail 'copy failure did not exercise both temporary directories'
  echo "PASS: $phase copy failure preserves the old app and cleans temporary directories"
done

for phase in install backup; do
  reset_case
  MOCK_MKTEMP_FAIL="transnote-${phase}."
  assert_failure_preserves_app
  unset MOCK_MKTEMP_FAIL
  [[ ! -s "$WORK/copies" ]] || fail 'temporary directory creation failure copied the app'
  if [[ "$phase" == install ]]; then
    [[ ! -s "$WORK/created" ]] || fail 'stage creation failure allocated another directory'
    [[ "$(wc -l < "$WORK/mktemp-calls")" -eq 1 ]] || fail 'continued after stage creation failed'
  else
    [[ "$(wc -l < "$WORK/created")" -eq 1 ]] || fail 'backup creation failure should clean the allocated stage'
    [[ "$(wc -l < "$WORK/mktemp-calls")" -eq 2 ]] || fail 'backup creation was not attempted'
  fi
  echo "PASS: $phase directory creation failure leaves the old app untouched without leaks"
done

echo 'ALL INSTALLER TESTS PASSED'
