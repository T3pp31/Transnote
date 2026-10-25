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

if [[ "$(grep -c 'MARKETING_VERSION = 0.2.0;' "$WORK/LocalTranscriber.xcodeproj/project.pbxproj")" -ne 2 ]]; then
  echo "FAIL: set-marketing-version.sh did not update MARKETING_VERSION" >&2
  exit 1
fi

if grep -q 'MARKETING_VERSION = 0.1.5;' "$WORK/LocalTranscriber.xcodeproj/project.pbxproj"; then
  echo "FAIL: old MARKETING_VERSION remains after update" >&2
  exit 1
fi

echo "PASS: set-marketing-version.sh"

if (cd "$WORK" && bash scripts/set-marketing-version.sh bad-version >/dev/null 2>&1); then
  echo "FAIL: invalid version should fail" >&2
  exit 1
fi
echo "PASS: invalid version rejected"

if ! grep -q 'MARKETING_VERSION = 0.2.0;' "$WORK/LocalTranscriber.xcodeproj/project.pbxproj"; then
  echo "FAIL: valid version was not persisted after invalid input" >&2
  exit 1
fi
echo "PASS: invalid version preserves valid value"

NO_MATCH_WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$NO_MATCH_WORK"' EXIT
mkdir -p "$NO_MATCH_WORK/LocalTranscriber.xcodeproj"
mkdir -p "$NO_MATCH_WORK/scripts"
printf 'CURRENT_PROJECT_VERSION = 1;\n' \
  > "$NO_MATCH_WORK/LocalTranscriber.xcodeproj/project.pbxproj"
cp "$ROOT/scripts/set-marketing-version.sh" "$NO_MATCH_WORK/scripts/"
if (cd "$NO_MATCH_WORK" && bash scripts/set-marketing-version.sh 0.3.0 >/dev/null 2>&1); then
  echo "FAIL: missing MARKETING_VERSION should fail" >&2
  exit 1
fi
echo "PASS: missing MARKETING_VERSION rejected"

echo "ALL RELEASE SCRIPT TESTS PASSED"
