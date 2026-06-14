#!/usr/bin/env bash
# Extract Transnote.app from an Xcode archive and prepare it for signing / notarization.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Transnote"
ENTITLEMENTS_PATH="${ROOT_DIR}/LocalTranscriber/LocalTranscriber.entitlements"

usage() {
  cat <<EOF
Usage: $(basename "$0") --archive <path.xcarchive> --output <dir> [options]

Options:
  --archive PATH     Path to the .xcarchive produced by xcodebuild archive
  --output PATH      Directory where ${APP_NAME}.app will be copied
  --sign IDENTITY    Developer ID signing identity (optional)
  --team TEAM_ID     Apple Team ID passed to codesign (optional)
  --verify-only      Verify signature on an existing app in --output
  -h, --help         Show this help
EOF
}

ARCHIVE_PATH=""
OUTPUT_DIR=""
SIGN_IDENTITY=""
TEAM_ID=""
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --sign)
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --team)
      TEAM_ID="$2"
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY=1
      shift
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

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "Missing required option: --output" >&2
  usage >&2
  exit 1
fi

APP_PATH="${OUTPUT_DIR}/${APP_NAME}.app"

verify_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "App not found: $APP_PATH" >&2
    exit 1
  fi

  if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "App is unsigned; skipping signature verification."
    return 0
  fi

  echo "Verifying signature for ${APP_PATH}"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH" || true
}

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  verify_app
  exit 0
fi

if [[ -z "$ARCHIVE_PATH" ]]; then
  echo "Missing required option: --archive" >&2
  usage >&2
  exit 1
fi

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "Archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

SOURCE_APP="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Application bundle not found in archive: $SOURCE_APP" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_PATH"
ditto "$SOURCE_APP" "$APP_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signing ${APP_PATH} with identity: ${SIGN_IDENTITY}"
  sign_args=(
    --force
    --deep
    --options runtime
    --timestamp
    --sign "$SIGN_IDENTITY"
    --entitlements "$ENTITLEMENTS_PATH"
  )
  if [[ -n "$TEAM_ID" ]]; then
    sign_args+=(--identifier "com.transnote.LocalTranscriber")
  fi
  codesign "${sign_args[@]}" "$APP_PATH"
fi

verify_app
echo "Exported ${APP_PATH}"
