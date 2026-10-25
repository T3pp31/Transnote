#!/usr/bin/env bash
# Sync MARKETING_VERSION in project.pbxproj with the release tag version.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 0.1.4" >&2
  exit 1
fi

version="$1"
project="LocalTranscriber.xcodeproj/project.pbxproj"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid version format: $version (expected X.Y.Z)" >&2
  exit 1
fi

if [ ! -f "$project" ]; then
  echo "Project file not found: $project" >&2
  exit 1
fi

VERSION="$version" perl -pi -e 'BEGIN { $count = 0; $version = $ENV{VERSION} } s/^([ \t]*MARKETING_VERSION = )[^;]*;/${1}$version;/g and $count++; END { if ($count == 0) { exit 1 } }' "$project"

if ! grep -qF "MARKETING_VERSION = ${version};" "$project"; then
  echo "Failed to update MARKETING_VERSION in $project" >&2
  exit 1
fi

echo "Set MARKETING_VERSION to ${version} in $project"
