#!/usr/bin/env bash
# Create a compressed DMG containing Transnote.app and an install script.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DISTRIBUTION_PLIST="${ROOT_DIR}/Config/distribution.plist"
INSTALL_SCRIPT_TEMPLATE="${ROOT_DIR}/scripts/install-transnote.command"
GATEKEEPER_README="${ROOT_DIR}/Config/dmg-gatekeeper-readme.txt"

usage() {
  cat <<EOF
Usage: $(basename "$0") --app <path/to/Transnote.app> --version <version> [--output <dir>]

Creates Transnote-{version}.dmg in the output directory (default: current directory).
EOF
}

read_distribution_config() {
  if [[ ! -f "$DISTRIBUTION_PLIST" ]]; then
    echo "Distribution config not found: $DISTRIBUTION_PLIST" >&2
    exit 1
  fi
  if [[ ! -f "$INSTALL_SCRIPT_TEMPLATE" ]]; then
    echo "Install script template not found: $INSTALL_SCRIPT_TEMPLATE" >&2
    exit 1
  fi

  APP_NAME="$(/usr/libexec/PlistBuddy -c "Print :AppName" "$DISTRIBUTION_PLIST")"
  INSTALL_SCRIPT_NAME="$(/usr/libexec/PlistBuddy -c "Print :InstallScriptName" "$DISTRIBUTION_PLIST")"

  LEGACY_APP_NAMES=""
  legacy_index=0
  while legacy_name="$(/usr/libexec/PlistBuddy -c "Print :LegacyAppNames:${legacy_index}" "$DISTRIBUTION_PLIST" 2>/dev/null)"; do
    if [[ -z "$LEGACY_APP_NAMES" ]]; then
      LEGACY_APP_NAMES="${legacy_name}.app"
    else
      LEGACY_APP_NAMES="${LEGACY_APP_NAMES}、${legacy_name}.app"
    fi
    legacy_index=$((legacy_index + 1))
  done
}

replace_readme_placeholders() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//@APP_NAME@/$APP_NAME}"
    line="${line//@DMG_NAME@/$DMG_NAME}"
    line="${line//@INSTALL_SCRIPT_NAME@/$INSTALL_SCRIPT_NAME}"
    if [[ -z "$LEGACY_APP_NAMES" ]]; then
      # 旧アプリ名が無い場合は補足の括弧書きごと省く
      line="${line//（および @LEGACY_APP_NAMES@）/}"
    fi
    line="${line//@LEGACY_APP_NAMES@/$LEGACY_APP_NAMES}"
    if [[ "$line" == '@SECURITY_NOTICE@' ]]; then
      printf '%s\n' "$security_notice"
    else
      printf '%s\n' "$line"
    fi
  done
}

APP_PATH=""
VERSION=""
OUTPUT_DIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --app" >&2
        usage >&2
        exit 1
      fi
      APP_PATH="$2"
      shift 2
      ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --version" >&2
        usage >&2
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --output)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --output" >&2
        usage >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

read_distribution_config

if [[ -z "$APP_PATH" || -z "$VERSION" ]]; then
  echo "Both --app and --version are required." >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
STAGING_DIR="${WORK_DIR}/staging"
DMG_RW="${WORK_DIR}/${APP_NAME}.dmg"
mkdir "$STAGING_DIR"

cp -R "$APP_PATH" "${STAGING_DIR}/"
cp "$DISTRIBUTION_PLIST" "${STAGING_DIR}/distribution.plist"
cp "$INSTALL_SCRIPT_TEMPLATE" "${STAGING_DIR}/${INSTALL_SCRIPT_NAME}"
chmod +x "${STAGING_DIR}/${INSTALL_SCRIPT_NAME}"
if [[ -f "$GATEKEEPER_README" ]]; then
  source "${ROOT_DIR}/scripts/release-security-notice.sh"
  replace_readme_placeholders < "$GATEKEEPER_README" > "${STAGING_DIR}/初めにお読みください.txt"
fi
ln -s /Applications "${STAGING_DIR}/Applications"

mkdir -p "$OUTPUT_DIR"
FINAL_DMG="${OUTPUT_DIR}/${DMG_NAME}"
rm -f "$FINAL_DMG"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$DMG_RW" >/dev/null

hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
hdiutil verify "$FINAL_DMG"

echo "Created ${FINAL_DMG}"
