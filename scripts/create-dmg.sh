#!/usr/bin/env bash
# Create a compressed DMG containing Transnote.app and an install script.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DISTRIBUTION_PLIST="${ROOT_DIR}/Config/distribution.plist"
INSTALL_SCRIPT_TEMPLATE="${ROOT_DIR}/scripts/install-transnote.command"

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
}

APP_PATH=""
VERSION=""
OUTPUT_DIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --output)
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
STAGING_DIR="$(mktemp -d)"
DMG_RW="$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}.XXXXXX.dmg")"
trap 'rm -rf "$STAGING_DIR" "$DMG_RW"' EXIT

cp -R "$APP_PATH" "${STAGING_DIR}/"
cp "$DISTRIBUTION_PLIST" "${STAGING_DIR}/distribution.plist"
cp "$INSTALL_SCRIPT_TEMPLATE" "${STAGING_DIR}/${INSTALL_SCRIPT_NAME}"
chmod +x "${STAGING_DIR}/${INSTALL_SCRIPT_NAME}"
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
