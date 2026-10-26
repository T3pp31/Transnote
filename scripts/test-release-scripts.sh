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

cp "$ROOT/scripts/verify-xcode-project.py" "$WORK/scripts/"

if ! (cd "$ROOT" && python3 scripts/verify-xcode-project.py); then
  echo "FAIL: Xcode project build phase references should resolve" >&2
  exit 1
fi
echo "PASS: Xcode project build phase references resolve"

awk '
  BEGIN {
    target = "		B96466D6AF9543009AF761B9 /* Frameworks */ = {"
    replacement = "		B96466D6AF9543009AF761B90 /* Frameworks */ = {"
  }
  !replaced && $0 == target {
    print replacement
    replaced = 1
    next
  }
  { print }
' "$ROOT/LocalTranscriber.xcodeproj/project.pbxproj" \
  > "$WORK/LocalTranscriber.xcodeproj/project.pbxproj"

if ! grep -q 'B96466D6AF9543009AF761B90 /\* Frameworks \*/ = {' \
  "$WORK/LocalTranscriber.xcodeproj/project.pbxproj"; then
  echo "FAIL: could not create unresolved Frameworks phase fixture" >&2
  exit 1
fi

if (cd "$WORK" && python3 scripts/verify-xcode-project.py >/dev/null 2>&1); then
  echo "FAIL: unresolved Frameworks phase should fail validation" >&2
  exit 1
fi
echo "PASS: unresolved Frameworks phase rejected"

NO_MATCH_WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$NO_MATCH_WORK"' EXIT
mkdir -p "$NO_MATCH_WORK/LocalTranscriber.xcodeproj"
mkdir -p "$NO_MATCH_WORK/scripts"
printf 'CURRENT_PROJECT_VERSION = 1;
' \
  > "$NO_MATCH_WORK/LocalTranscriber.xcodeproj/project.pbxproj"
cp "$ROOT/scripts/set-marketing-version.sh" "$NO_MATCH_WORK/scripts/"
if (cd "$NO_MATCH_WORK" && bash scripts/set-marketing-version.sh 0.3.0 >/dev/null 2>&1); then
  echo "FAIL: missing MARKETING_VERSION should fail" >&2
  exit 1
fi
echo "PASS: missing MARKETING_VERSION rejected"

echo "ALL RELEASE SCRIPT TESTS PASSED"
