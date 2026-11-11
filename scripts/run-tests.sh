#!/usr/bin/env bash
# CI / Release 共通の XCTest 実行設定。リポジトリのルートから呼び出す。
set -euo pipefail

usage() {
  echo "Usage: bash scripts/run-tests.sh <ci|release>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi
case "$1" in
  ci|release) ;;
  *) usage; exit 2 ;;
esac

# Release の archive と同じ既存の環境変数を使う。
args=(
  test
  -project "${PROJECT:-LocalTranscriber.xcodeproj}"
  -scheme "${SCHEME:-LocalTranscriber}"
  -destination 'platform=macOS'
  CODE_SIGNING_ALLOWED=NO
  -derivedDataPath "${DERIVED_DATA_PATH:-DerivedData}"
  # 実モデルの取得・ロードは Nightly 専用の only-testing 経路で検証する。
  -skip-testing:LocalTranscriberTests/ModelDownloadIntegrationTests
  -skip-testing:LocalTranscriberTests/ModelAvailabilityPathTests/testWhisperKitLoadsFromDetectedModelFolder
)

# 既存の範囲を維持する: CI は UI を除外し、Release は UI も実行する。
if [[ "$1" == ci ]]; then
  args+=(-skip-testing:LocalTranscriberUITests)
fi

xcodebuild "${args[@]}"
