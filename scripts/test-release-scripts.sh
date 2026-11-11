#!/usr/bin/env bash
# Release / Pages / CI 用スクリプトの自動テスト。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 "$ROOT/scripts/test-ci-package-resolved.py"

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

python3 "$ROOT/scripts/test_verify_xcode_project.py"

NO_MATCH_WORK=$(mktemp -d)
trap 'rm -rf "$WORK" "$NO_MATCH_WORK"' EXIT
mkdir -p "$NO_MATCH_WORK/LocalTranscriber.xcodeproj"
mkdir -p "$NO_MATCH_WORK/scripts"
cp "$ROOT/scripts/set-marketing-version.sh" "$NO_MATCH_WORK/scripts/"
for fixture in \
  'CURRENT_PROJECT_VERSION = 1;' \
  'MARKETING_VERSION=0.1.5;' \
  'MARKETING_VERSION  = 0.1.5;'; do
  printf '%s\n' "$fixture" > "$NO_MATCH_WORK/LocalTranscriber.xcodeproj/project.pbxproj"
  cp "$NO_MATCH_WORK/LocalTranscriber.xcodeproj/project.pbxproj" "$NO_MATCH_WORK/project-before"

  status=0
  (cd "$NO_MATCH_WORK" && bash scripts/set-marketing-version.sh 0.3.0 \
    >stdout 2>stderr) || status=$?
  if [[ "$status" -ne 1 ]]; then
    echo "FAIL: unmatched MARKETING_VERSION should exit 1: $fixture" >&2
    exit 1
  fi
  if ! grep -qF 'No matching MARKETING_VERSION = ...; entry found' "$NO_MATCH_WORK/stderr"; then
    echo "FAIL: unmatched MARKETING_VERSION should report the cause: $fixture" >&2
    exit 1
  fi
  if ! grep -qF 'Failed to update MARKETING_VERSION in LocalTranscriber.xcodeproj/project.pbxproj' "$NO_MATCH_WORK/stderr"; then
    echo "FAIL: unmatched MARKETING_VERSION should report the project path: $fixture" >&2
    exit 1
  fi
  if [[ -s "$NO_MATCH_WORK/stdout" ]]; then
    echo "FAIL: unmatched MARKETING_VERSION should not report success: $fixture" >&2
    exit 1
  fi
  if ! cmp -s "$NO_MATCH_WORK/project-before" "$NO_MATCH_WORK/LocalTranscriber.xcodeproj/project.pbxproj"; then
    echo "FAIL: unmatched MARKETING_VERSION should preserve the project: $fixture" >&2
    exit 1
  fi
done
echo "PASS: missing or unmatched MARKETING_VERSION rejected with diagnostics"

# Release から案内するインストール文書のコード例と後続の手順を確認する。
python3 - "$ROOT/docs/install.md" <<'PY'
import sys
from pathlib import Path

# この文書で使う、行頭の三連バッククォートのフェンスを追跡する。
language = None
code = []
blocks = []
prose = []
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if language is None:
        if line.startswith("```"):
            language = line[3:].strip()
        else:
            prose.append(line)
    elif line.rstrip() == "```":
        blocks.append((language, "\n".join(code)))
        language = None
        code = []
    else:
        code.append(line)

assert language is None, "install.md: unclosed code fence"
assert ("bash", 'bash "/Volumes/Transnote 1/インストール.command"') in blocks, \
    "install.md: alternate volume command must be in its own bash block"
for heading in (
    "#### 方法 B: 右クリック → 開く（macOS 14まで）",
    "#### 方法 C: システム設定から許可",
    "## インストール（上級者向け: ドラッグ&ドロップ）",
    "## 初回起動",
    "## 更新",
    "## アンインストール",
    "## トラブルシューティング",
    "| 症状 | 対処 |",
):
    assert heading in prose, f"install.md: expected outside code blocks: {heading}"
print("PASS: install.md code fences and subsequent sections")
PY

python3 "$ROOT/scripts/test-release-signing.py"
bash "$ROOT/scripts/test-export-release-app.sh"
bash "$ROOT/scripts/test-check-swift-format.sh"

echo "ALL RELEASE SCRIPT TESTS PASSED"
