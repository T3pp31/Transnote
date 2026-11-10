#!/usr/bin/env bash
# Extract Transnote.app from an Xcode archive for distribution.
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
  --team TEAM_ID     Validate that --sign belongs to this Apple Team ID (requires --sign)
  --verify-only      Verify signature on an existing app in --output
  -h, --help         Show this help
EOF
}

ARCHIVE_PATH=""
OUTPUT_DIR=""
SIGN_IDENTITY=""
TEAM_ID=""
VERIFY_ONLY=0
SIGN_SPECIFIED=0
TEAM_SPECIFIED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --archive" >&2
        usage >&2
        exit 1
      fi
      ARCHIVE_PATH="$2"
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
    --sign)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --sign" >&2
        usage >&2
        exit 1
      fi
      SIGN_SPECIFIED=1
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --team)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --team" >&2
        usage >&2
        exit 1
      fi
      TEAM_SPECIFIED=1
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

if [[ "$SIGN_SPECIFIED" -eq 1 && -z "$SIGN_IDENTITY" ]]; then
  echo "--sign requires a non-empty signing identity" >&2
  exit 1
fi

if [[ "$TEAM_SPECIFIED" -eq 1 ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "--team requires --sign with a signing identity" >&2
    exit 1
  fi
  if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Invalid --team value: expected a 10-character Apple Team ID" >&2
    exit 1
  fi
fi

APP_PATH="${OUTPUT_DIR}/${APP_NAME}.app"

verify_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "App not found: $APP_PATH" >&2
    exit 1
  fi

  if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    if [[ -n "$SIGN_IDENTITY" ]]; then
      echo "Signature verification failed for ${APP_PATH} (requested identity: ${SIGN_IDENTITY})" >&2
      return 1
    fi
    if codesign -d "$APP_PATH" >/dev/null 2>&1; then
      echo "Invalid signature detected for ${APP_PATH}" >&2
      return 1
    fi
    echo "App is unsigned; skipping signature verification."
    return 0
  fi

  echo "Verifying signature for ${APP_PATH}"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
}

# A Team ID is only a constraint on a certificate, never a codesign --sign value.
# Look up both full certificate names and SHA-1 fingerprints to validate --team.
validate_signing_team() {
  local identities line fingerprint certificate_name matched=0
  local normalized_fingerprint=""
  local identity_line_re='^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"([^"]+)"'

  if ! identities="$(security find-identity -v -p codesigning)"; then
    echo "Could not list valid codesigning identities to validate --team" >&2
    return 1
  fi

  if [[ "$SIGN_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
    normalized_fingerprint="$(printf '%s' "$SIGN_IDENTITY" | tr '[:lower:]' '[:upper:]')"
  fi

  while IFS= read -r line; do
    if [[ "$line" =~ $identity_line_re ]]; then
      fingerprint="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]')"
      certificate_name="${BASH_REMATCH[2]}"
      if [[ "$SIGN_IDENTITY" == "$certificate_name" || "$normalized_fingerprint" == "$fingerprint" ]]; then
        matched=1
        if [[ "$certificate_name" == *"(${TEAM_ID})" ]]; then
          return 0
        fi
      fi
    fi
  done <<< "$identities"

  if [[ "$matched" -eq 1 ]]; then
    echo "Signing identity '${SIGN_IDENTITY}' does not belong to Team ID ${TEAM_ID}" >&2
  else
    echo "Signing identity '${SIGN_IDENTITY}' was not found among valid codesigning identities" >&2
  fi
  return 1
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

if [[ -n "$TEAM_ID" ]]; then
  validate_signing_team
fi

resolved_output_path="$(cd "$(dirname "$APP_PATH")" && pwd -P)/$(basename "$APP_PATH")"
resolved_source_path="$(cd "$SOURCE_APP" && pwd -P)"
if [[ "$resolved_output_path" == "$resolved_source_path" ||
      "$resolved_source_path" == "$resolved_output_path"/* ||
      "$resolved_output_path" == "$resolved_source_path"/* ]]; then
  echo "--output overlaps the source app inside the archive: $OUTPUT_DIR" >&2
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
  if ! codesign "${sign_args[@]}" "$APP_PATH"; then
    echo "Failed to sign ${APP_PATH} with identity: ${SIGN_IDENTITY}" >&2
    exit 1
  fi
fi

verify_app
echo "Exported ${APP_PATH}"
