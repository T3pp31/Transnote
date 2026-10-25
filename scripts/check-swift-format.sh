#!/usr/bin/env bash
# 既存の違反ファイルは allowlist で段階的に排除し、新規ファイルの違反は blocking にする。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/.github/swift-format.json"
ALLOWLIST_PATH="${ROOT_DIR}/.github/swift-format-allowlist.txt"
LOG_PATH="$(mktemp -t transnote-swift-format)"
trap 'rm -f "$LOG_PATH"' EXIT

set +e
xcrun swift-format lint --strict --configuration "$CONFIG_PATH" \
  --recursive LocalTranscriber LocalTranscriberTests > "$LOG_PATH" 2>&1
lint_status=$?
set -e

if [[ "$lint_status" -eq 0 ]]; then
  exit 0
fi

violating_files="$(awk -F: '/error:/ {print $1}' "$LOG_PATH" | sort -u)"
unexpected_files="$(comm -13 <(sort "$ALLOWLIST_PATH") <(printf '%s\n' "$violating_files" | sed '/^$/d'))"

if [[ -n "$unexpected_files" ]]; then
  echo "Unexpected Swift format violations:" >&2
  printf '%s\n' "$unexpected_files" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

echo "Swift format violations are limited to the temporary allowlist." >&2
