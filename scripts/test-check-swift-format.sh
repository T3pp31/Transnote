#!/usr/bin/env bash
# swift-format の実行結果をモックする、macOS ツール不要の回帰テスト。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(command mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Bash 関数を export し、実ツールや一時ファイルの実行権限に依存せず検証する。
xcrun() {
  [[ "$PWD" == "$MOCK_EXPECTED_ROOT" ]] || return 2
  [[ "$*" == "swift-format lint --strict --configuration $MOCK_EXPECTED_ROOT/.github/swift-format.json --recursive LocalTranscriber LocalTranscriberTests" ]] || return 2
  cat "$MOCK_DIAGNOSTICS"
  return "$MOCK_LINT_STATUS"
}

# 本体の BSD mktemp 呼び出しを Linux でも実行できるよう、専用ログを返す。
mktemp() {
  : > "$MOCK_LOG_PATH"
  printf '%s\n' "$MOCK_LOG_PATH"
}
export -f xcrun mktemp

run_check() {
  printf '%s' "$2" > "$WORK/diagnostics"
  (cd "${3:-$ROOT}" && MOCK_DIAGNOSTICS="$WORK/diagnostics" \
    MOCK_EXPECTED_ROOT="$ROOT" \
    MOCK_LINT_STATUS="$1" \
    MOCK_LOG_PATH="$WORK/lint.log" \
    bash "$ROOT/scripts/check-swift-format.sh") > "$WORK/stdout" 2> "$WORK/stderr"
}

fail() {
  echo "FAIL: $*" >&2
  cat "$WORK/stdout" "$WORK/stderr" >&2
  exit 1
}

expect_success() {
  if ! run_check "$@"; then
    fail "expected success for lint status $1"
  fi
}

expect_failure() {
  if run_check "$@"; then
    fail "expected failure for lint status $1"
  fi
  if grep -q 'Swift format violations are limited to the temporary allowlist.' "$WORK/stderr"; then
    fail 'failed lint must not report allowlist success'
  fi
  if [[ -n "$2" && "$(cat "$WORK/stderr")" != *"$2"* ]]; then
    fail 'original diagnostics were not preserved on stderr'
  fi
}

expect_success 0 ''
[[ ! -s "$WORK/stderr" ]] || fail 'clean lint produced an error message'
echo 'PASS: clean lint succeeds'

ALLOWLISTED='LocalTranscriber/Domain/AppSettings.swift:1:1: error: indentation'
expect_success 1 "$ALLOWLISTED"
grep -q 'Swift format violations are limited to the temporary allowlist.' "$WORK/stderr" \
  || fail 'allowlisted violations were not accepted'
echo 'PASS: allowlisted violations still succeed'

UNEXPECTED='LocalTranscriber/NewFile.swift:2:1: error: indentation'
expect_failure 1 "$UNEXPECTED"
grep -q 'Unexpected Swift format violations:' "$WORK/stderr" \
  || fail 'missing unexpected violation message'
echo 'PASS: non-allowlisted violations fail'

expect_failure 1 "${UNEXPECTED}
${ALLOWLISTED}"
echo 'PASS: mixed allowlisted and non-allowlisted violations fail'

expect_unparseable_failure() {
  expect_failure "$@"
  grep -q 'swift-format failed without parseable diagnostics' "$WORK/stderr" \
    || fail 'missing diagnostic parsing failure message'
}

expect_unparseable_failure 1 ''
echo 'PASS: nonzero exit without output fails'

expect_unparseable_failure 64 "Error: Unknown option '--strict'
Usage: swift-format lint [<options>] [<paths> ...]"
echo 'PASS: uppercase CLI error fails and preserves the full log'

expect_unparseable_failure 134 'swift-format: Abort trap: 6'
echo 'PASS: tool crash without error diagnostics fails'

expect_unparseable_failure 127 'xcrun: command not found'
echo 'PASS: tool lookup failure fails'

expect_unparseable_failure 1 'LocalTranscriber/Domain/AppSettings.swift:1:1: note: indentation'
echo 'PASS: nonzero exit with unrecognized diagnostic format fails'

# --strict は warning のみでも非ゼロになり、診断のパスは相対・絶対が混在する。
ALLOWLISTED_WARNING='LocalTranscriber/Domain/AppSettings.swift:1:1: warning: [Indentation] indent by 4 spaces'
expect_success 1 "$ALLOWLISTED_WARNING"
echo 'PASS: allowlisted strict-mode warnings succeed'

expect_success 1 "${ROOT}/${ALLOWLISTED_WARNING}
${ALLOWLISTED_WARNING}
${ALLOWLISTED}"
echo 'PASS: mixed absolute/relative allowlisted warnings and errors succeed'

UNEXPECTED_WARNING='LocalTranscriber/NewFile.swift:2:1: warning: [Indentation] indent by 4 spaces'
expect_failure 1 "$UNEXPECTED_WARNING"
grep -q 'Unexpected Swift format violations:' "$WORK/stderr" \
  || fail 'non-allowlisted warning was not parsed'
echo 'PASS: non-allowlisted strict-mode warnings fail'

expect_failure 1 "${ROOT}/${UNEXPECTED_WARNING}"
grep -qx 'LocalTranscriber/NewFile.swift' "$WORK/stderr" \
  || fail 'absolute warning path was not normalized'
echo 'PASS: non-allowlisted absolute warning paths fail'

expect_failure 1 "${ALLOWLISTED}
${UNEXPECTED_WARNING}"
echo 'PASS: allowlisted errors do not hide non-allowlisted warnings'

for directory in "$ROOT" "$ROOT/scripts" "$WORK"; do
  expect_success 0 '' "$directory"
  expect_success 1 "$ALLOWLISTED" "$directory"
  expect_failure 1 "$UNEXPECTED" "$directory"
  echo "PASS: lint cwd and arguments are independent of invocation directory: $directory"
done

bash "$ROOT/scripts/test-check-swift-format-cwd.sh"
echo 'ALL SWIFT FORMAT SCRIPT TESTS PASSED'
