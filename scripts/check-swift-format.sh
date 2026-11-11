#!/usr/bin/env bash
# 既存の違反ファイルは allowlist で段階的に排除し、新規ファイルの違反は blocking にする。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/.github/swift-format.json"
ALLOWLIST_PATH="${ROOT_DIR}/.github/swift-format-allowlist.txt"
LOG_PATH="$(mktemp -t transnote-swift-format)"
trap 'rm -f "$LOG_PATH"' EXIT

cd "$ROOT_DIR"

set +e
xcrun swift-format lint --strict --configuration "$CONFIG_PATH" \
  --recursive LocalTranscriber LocalTranscriberTests > "$LOG_PATH" 2>&1
lint_status=$?
set -e

if [[ "$lint_status" -eq 0 ]]; then
  exit 0
fi

# --strict では warning も失敗要因になる。絶対パスは allowlist と同じ相対パスに揃える。
violating_files="$(awk -F: -v root="${ROOT_DIR}/" '
  /^[^:]+:[0-9]+:[0-9]+: (warning|error):/ {
    path = $1
    if (index(path, root) == 1) path = substr(path, length(root) + 1)
    print path
  }
' "$LOG_PATH" | sort -u)"
if [[ -z "$violating_files" ]]; then
  echo "swift-format failed without parseable diagnostics (exit status: $lint_status)" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

unexpected_files="$(comm -13 <(sort "$ALLOWLIST_PATH") <(printf '%s\n' "$violating_files" | sed '/^$/d'))"

if [[ -n "$unexpected_files" ]]; then
  echo "Unexpected Swift format violations:" >&2
  printf '%s\n' "$unexpected_files" >&2
  cat "$LOG_PATH" >&2
  exit 1
fi

echo "Swift format violations are limited to the temporary allowlist." >&2
