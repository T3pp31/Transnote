#!/usr/bin/env bash
# cwd に依存しない lint と allowlist 判定の回帰テスト。Xcode は不要。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repository with spaces"
mkdir -p "$REPO/scripts" "$REPO/.github" "$REPO/LocalTranscriber" \
  "$REPO/LocalTranscriberTests" "$WORK/unrelated"
cp "$ROOT/scripts/check-swift-format.sh" "$REPO/scripts/"
cp "$ROOT/.github/swift-format.json" "$REPO/.github/"
printf 'LocalTranscriber/Allowed.swift\n' > "$REPO/.github/swift-format-allowlist.txt"
touch "$REPO/LocalTranscriber/Allowed.swift" "$REPO/LocalTranscriberTests/New.swift"

xcrun() {
  printf '%s\n' "$PWD" "$@" > "$MOCK_INVOCATION"
  # 存在しない相対ターゲットでは診断なし・成功となるケースを再現する。
  [[ -f LocalTranscriber/Allowed.swift && -f LocalTranscriberTests/New.swift ]] || return 0
  case "$MOCK_LINT_CASE" in
    clean) return 0 ;;
    allowed)
      echo 'LocalTranscriber/Allowed.swift:1:1: error: format violation'
      return 1
      ;;
    unexpected)
      echo 'LocalTranscriber/Allowed.swift:1:1: error: format violation'
      echo 'LocalTranscriberTests/New.swift:1:1: error: format violation'
      return 1
      ;;
    *) return 2 ;;
  esac
}

printf '%s\n' "$REPO" swift-format lint --strict --configuration \
  "$REPO/.github/swift-format.json" --recursive LocalTranscriber LocalTranscriberTests \
  > "$WORK/expected-invocation"

fail() {
  echo "FAIL: $*" >&2
  cat "$WORK/output" >&2
  exit 1
}

for location in root scripts unrelated; do
  case "$location" in
    root) cwd="$REPO"; script='scripts/check-swift-format.sh' ;;
    scripts) cwd="$REPO/scripts"; script='./check-swift-format.sh' ;;
    unrelated) cwd="$WORK/unrelated"; script="$REPO/scripts/check-swift-format.sh" ;;
  esac
  for lint_case in unexpected clean allowed; do
    rm -f "$WORK/invocation"
    status=0
    (
      cd "$cwd"
      # 本体が使う BSD mktemp -t のテンプレートを Linux でも扱えるようにする。
      mktemp() {
        [[ "$*" == '-t transnote-swift-format' ]] || return 2
        command mktemp "${TMPDIR:-/tmp}/transnote-swift-format.XXXXXX"
      }
      export -f mktemp xcrun
      MOCK_INVOCATION="$WORK/invocation" MOCK_LINT_CASE="$lint_case" bash "$script"
    ) > "$WORK/output" 2>&1 || status=$?

    case "$lint_case" in
      unexpected)
        [[ "$status" -eq 1 ]] || fail "$location: new violation must fail (status=$status)"
        grep -q '^Unexpected Swift format violations:$' "$WORK/output" || fail 'missing violation error'
        grep -q '^LocalTranscriberTests/New.swift$' "$WORK/output" || fail 'missing unexpected file'
        ;;
      clean)
        [[ "$status" -eq 0 && ! -s "$WORK/output" ]] || fail "$location: clean lint must succeed silently"
        ;;
      allowed)
        [[ "$status" -eq 0 ]] || fail "$location: allowlisted violation must succeed"
        grep -q '^Swift format violations are limited to the temporary allowlist\.$' "$WORK/output" \
          || fail "$location: allowlist was not applied"
        ;;
    esac
    cmp -s "$WORK/expected-invocation" "$WORK/invocation" \
      || fail "$location: lint cwd or arguments differ from the repository-root invocation"
    echo "PASS: $location / $lint_case"
  done
done

echo 'ALL SWIFT FORMAT SCRIPT TESTS PASSED'
