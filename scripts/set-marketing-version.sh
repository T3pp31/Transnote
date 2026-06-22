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

sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${version};/g" "$project"
echo "Set MARKETING_VERSION to ${version} in ${project}"
