#!/usr/bin/env bash
# swift-format の実行結果をモックする、macOS ツール不要の回帰テスト。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Bash 関数を export し、実ツールや一時ファイルの実行権限に依存せず検証する。
xcrun() {
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
  (cd "$ROOT" && MOCK_DIAGNOSTICS="$WORK/diagnostics" \
    MOCK_LINT_STATUS="$1" \
    MOCK_LOG_PATH="$WORK/lint.log" \
    bash scripts/check-swift-format.sh) > "$WORK/stdout" 2> "$WORK/stderr"
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

expect_unparseable_failure 1 'LocalTranscriber/Domain/AppSettings.swift:1:1: warning: indentation'
echo 'PASS: nonzero exit with unrecognized diagnostic format fails'

echo 'ALL SWIFT FORMAT SCRIPT TESTS PASSED'
