#!/usr/bin/env bash
# Create a compressed DMG containing Transnote.app.
set -euo pipefail

APP_NAME="Transnote"

usage() {
  cat <<EOF
Usage: $(basename "$0") --app <path/to/${APP_NAME}.app> --version <version> [--output <dir>]

Creates ${APP_NAME}-{version}.dmg in the output directory (default: current directory).
EOF
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
