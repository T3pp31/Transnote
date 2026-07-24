#!/usr/bin/env bash
# Generate a CycloneDX SBOM using Syft.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SBOM_CONFIG="${TRANSNOTE_SBOM_CONFIG:-${ROOT_DIR}/Config/sbom.plist}"
SYFT_BIN="${SYFT_PATH:-syft}"

MODE=""
INPUT_PATH=""
VERSION=""
OUTPUT_DIR=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --mode <release|ci> [options]

Options:
  --mode release|ci       Required. release scans the app bundle; ci scans Package.resolved
  --input PATH            Scan target (defaults depend on mode)
  --version VERSION       Required for release mode (e.g. 0.1.0)
  --output-dir PATH       Output directory (default: Config/sbom.plist OutputDirectory)
  --config PATH           SBOM config plist (default: Config/sbom.plist)
  -h, --help
EOF
}

read_sbom_config() {
  if [[ ! -f "$SBOM_CONFIG" ]]; then
    echo "SBOM config not found: $SBOM_CONFIG" >&2
    exit 1
  fi

  OUTPUT_FORMAT="$(/usr/libexec/PlistBuddy -c "Print :OutputFormat" "$SBOM_CONFIG")"
  APP_NAME="$(/usr/libexec/PlistBuddy -c "Print :AppName" "$SBOM_CONFIG")"
  RELEASE_FILENAME_PATTERN="$(/usr/libexec/PlistBuddy -c "Print :ReleaseOutputFilenamePattern" "$SBOM_CONFIG")"
  CI_FILENAME_PATTERN="$(/usr/libexec/PlistBuddy -c "Print :CIOutputFilename" "$SBOM_CONFIG")"
  DEFAULT_OUTPUT_DIR="$(/usr/libexec/PlistBuddy -c "Print :OutputDirectory" "$SBOM_CONFIG")"
  PACKAGE_RESOLVED_PATH="$(/usr/libexec/PlistBuddy -c "Print :PackageResolvedPath" "$SBOM_CONFIG")"
}

apply_filename_pattern() {
  local pattern="$1"
  local version="${2:-}"
  local result="$pattern"
  result="${result//\{AppName\}/$APP_NAME}"
  result="${result//\{Version\}/$version}"
  printf '%s' "$result"
}

resolve_default_input() {
  case "$MODE" in
    release)
      printf '%s/build/release/%s.app' "$ROOT_DIR" "$APP_NAME"
      ;;
    ci)
      printf '%s/%s' "$ROOT_DIR" "$PACKAGE_RESOLVED_PATH"
      ;;
    *)
      echo "Unknown mode: $MODE" >&2
      exit 1
      ;;
  esac
}

resolve_output_filename() {
  case "$MODE" in
    release)
      if [[ -z "$VERSION" ]]; then
        echo "--version is required for release mode." >&2
        exit 1
      fi
      apply_filename_pattern "$RELEASE_FILENAME_PATTERN" "$VERSION"
      ;;
    ci)
      apply_filename_pattern "$CI_FILENAME_PATTERN"
      ;;
    *)
      echo "Unknown mode: $MODE" >&2
      exit 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --input)
      INPUT_PATH="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --config)
      SBOM_CONFIG="$2"
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

if [[ -z "$MODE" ]]; then
  echo "--mode is required." >&2
  usage >&2
  exit 1
fi

if [[ "$MODE" != "release" && "$MODE" != "ci" ]]; then
  echo "Invalid mode: $MODE (expected release or ci)" >&2
  exit 1
fi

read_sbom_config

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="${ROOT_DIR}/${DEFAULT_OUTPUT_DIR}"
elif [[ "$OUTPUT_DIR" != /* ]]; then
  OUTPUT_DIR="${ROOT_DIR}/${OUTPUT_DIR}"
fi

if [[ -z "$INPUT_PATH" ]]; then
  INPUT_PATH="$(resolve_default_input)"
elif [[ "$INPUT_PATH" != /* ]]; then
  INPUT_PATH="${ROOT_DIR}/${INPUT_PATH}"
fi

if [[ ! -e "$INPUT_PATH" ]]; then
  echo "Scan target not found: $INPUT_PATH" >&2
  exit 1
fi

if ! command -v "$SYFT_BIN" >/dev/null 2>&1; then
  echo "Syft not found: $SYFT_BIN" >&2
  exit 1
fi

OUTPUT_FILENAME="$(resolve_output_filename)"
OUTPUT_PATH="${OUTPUT_DIR}/${OUTPUT_FILENAME}"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_PATH"

"$SYFT_BIN" scan "$INPUT_PATH" \
  --output "${OUTPUT_FORMAT}=${OUTPUT_PATH}"

echo "$OUTPUT_PATH"
