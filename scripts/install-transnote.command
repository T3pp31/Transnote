#!/usr/bin/env bash
# Install Transnote to /Applications, removing any previous version first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="${SCRIPT_DIR}/distribution.plist"
APPLICATIONS_DIR="/Applications"

fail() {
  osascript -e "display alert \"Transnote インストールエラー\" message \"${1}\" as critical" >/dev/null 2>&1 || true
  exit 1
}

if [[ ! -f "$PLIST" ]]; then
  fail "配布設定ファイル (distribution.plist) が見つかりません。"
fi

APP_NAME="$(/usr/libexec/PlistBuddy -c "Print :AppName" "$PLIST")"
SOURCE_APP="${SCRIPT_DIR}/${APP_NAME}.app"
TARGET_APP="${APPLICATIONS_DIR}/${APP_NAME}.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  fail "${APP_NAME}.app が DMG 内に見つかりません。"
fi

osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
sleep 1

if [[ -d "$TARGET_APP" ]]; then
  rm -rf "$TARGET_APP"
fi

legacy_index=0
while legacy_name="$(/usr/libexec/PlistBuddy -c "Print :LegacyAppNames:${legacy_index}" "$PLIST" 2>/dev/null)"; do
  legacy_app="${APPLICATIONS_DIR}/${legacy_name}.app"
  if [[ -d "$legacy_app" ]]; then
    rm -rf "$legacy_app"
  fi
  legacy_index=$((legacy_index + 1))
done

ditto "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP" 2>/dev/null || true

osascript -e "display alert \"Transnote をインストールしました\" message \"${APP_NAME} を Applications フォルダに配置しました。\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
open "$TARGET_APP" || true
