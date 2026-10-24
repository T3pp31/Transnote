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

install_work="$WORK/install"
apps_dir="$WORK/apps"
mkdir -p "$install_work/Transnote.app/Contents/MacOS" \
  "$apps_dir/Transnote.app/Contents/MacOS" \
  "$WORK/bin"
cp "$ROOT/Config/distribution.plist" "$install_work/distribution.plist"
cp "$ROOT/scripts/install-transnote.command" "$install_work/"
cat > "$install_work/Transnote.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
  <dict>
    <key>CFBundleIdentifier</key>
    <string>com.transnote.LocalTranscriber</string>
  </dict>
</plist>
PLIST
cat > "$apps_dir/Transnote.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
  <dict>
    <key>CFBundleIdentifier</key>
    <string>com.example.DifferentApp</string>
  </dict>
</plist>
PLIST
cat > "$WORK/bin/osascript" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$WORK/bin/osascript"

install_log="$WORK/install.log"
if PATH="$WORK/bin:$PATH" TRANSNOTE_INSTALL_DIR="$apps_dir" \
  bash "$install_work/install-transnote.command" > /dev/null 2> "$install_log"; then
  echo "FAIL: installer should reject a different app with the same name" >&2
  exit 1
fi
if ! grep -q "同名の別アプリ" "$install_log"; then
  echo "FAIL: installer did not report a target Bundle ID mismatch" >&2
  cat "$install_log" >&2
  exit 1
fi
if [[ ! -d "$apps_dir/Transnote.app" ]]; then
  echo "FAIL: target app was removed during Bundle ID mismatch" >&2
  exit 1
fi
echo "PASS: target Bundle ID mismatch rejected"

echo "ALL RELEASE SCRIPT TESTS PASSED"
