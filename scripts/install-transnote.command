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

verify_dmg_checksum_if_requested() {
  [[ -z "${CHECKSUM:-}" ]] && return 0

  if [[ "$SCRIPT_DIR" != /Volumes/* ]]; then
    fail "CHECKSUM 検証は DMG から実行した場合のみ利用できます。"
  fi

  local volume_path="/Volumes/${SCRIPT_DIR#/Volumes/}"
  volume_path="${volume_path%%/*}"

  local dmg_path=""
  local current_path=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^image-path[[:space:]]*: ]]; then
      current_path="${line#*: }"
    elif [[ "$line" == *"$volume_path"* ]] && [[ -n "$current_path" ]]; then
      dmg_path="$current_path"
      break
    fi
  done < <(hdiutil info 2>/dev/null)

  if [[ -z "$dmg_path" || ! -f "$dmg_path" ]]; then
    fail "マウント中の DMG パスを取得できませんでした。"
  fi

  local actual
  actual="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
  if [[ "$actual" != "$CHECKSUM" ]]; then
    fail "DMG の SHA256 チェックサムが一致しません。配布物が改ざんされている可能性があります。"
  fi
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

verify_dmg_checksum_if_requested

remove_installed_apps() {
  local base_name="$1"
  local candidate

  shopt -s nullglob
  for candidate in "${APPLICATIONS_DIR}/${base_name}.app" "${APPLICATIONS_DIR}/${base_name} "*.app; do
    if [[ -d "$candidate" ]]; then
      rm -rf "$candidate"
    fi
  done
  shopt -u nullglob
}

eject_installer_volume() {
  if [[ "$SCRIPT_DIR" != /Volumes/* ]]; then
    return 0
  fi

  local volume_path="/Volumes/${SCRIPT_DIR#/Volumes/}"
  volume_path="${volume_path%%/*}"
  hdiutil detach "$volume_path" -quiet >/dev/null 2>&1 || true
}

osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
sleep 1

remove_installed_apps "$APP_NAME"

legacy_index=0
while legacy_name="$(/usr/libexec/PlistBuddy -c "Print :LegacyAppNames:${legacy_index}" "$PLIST" 2>/dev/null)"; do
  remove_installed_apps "$legacy_name"
  legacy_index=$((legacy_index + 1))
done

ditto "$SOURCE_APP" "$TARGET_APP"
xattr -cr "$TARGET_APP" 2>/dev/null || true

eject_installer_volume

osascript -e "display alert \"Transnote をインストールしました\" message \"${APP_NAME} を Applications フォルダに配置しました。\" buttons {\"OK\"} default button \"OK\"" >/dev/null 2>&1 || true
open "$TARGET_APP" || true
