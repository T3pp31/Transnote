#!/usr/bin/env bash
# Release / Pages 用スクリプトの自動テスト。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/LocalTranscriber.xcodeproj" "$WORK/scripts"
cat > "$WORK/LocalTranscriber.xcodeproj/project.pbxproj" <<'PBX'
				MARKETING_VERSION = 0.1.5;
				CURRENT_PROJECT_VERSION = 1;
				MARKETING_VERSION = 0.1.5;
PBX

cp "$ROOT/scripts/set-marketing-version.sh" "$WORK/scripts/"
(cd "$WORK" && bash scripts/set-marketing-version.sh 0.2.0)

if ! grep -q 'MARKETING_VERSION = 0.2.0;' "$WORK/LocalTranscriber.xcodeproj/project.pbxproj"; then
  echo "FAIL: set-marketing-version.sh did not update MARKETING_VERSION" >&2
  exit 1
fi

echo "PASS: set-marketing-version.sh"

if (cd "$WORK" && bash scripts/set-marketing-version.sh bad-version >/dev/null 2>&1); then
  echo "FAIL: invalid version should fail" >&2
  exit 1
fi
echo "PASS: invalid version rejected"

for option in --archive --output --sign --team; do
  message_file="$WORK/missing-option-${option#--}.txt"
  if bash "$ROOT/scripts/export-release-app.sh" "$option" > /dev/null 2> "$message_file"; then
    echo "FAIL: $option without a value should fail" >&2
    exit 1
  fi
  if ! grep -q "Missing value for ${option}" "$message_file"; then
    echo "FAIL: $option without a value did not print a missing-value error" >&2
    cat "$message_file" >&2
    exit 1
  fi
done
echo "PASS: missing option values rejected"

echo "ALL RELEASE SCRIPT TESTS PASSED"
