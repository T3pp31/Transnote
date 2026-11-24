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
derived_data_path="${DERIVED_DATA_PATH:-DerivedData}"
result_root="${RESULT_ROOT:-${derived_data_path}/TestResults}"
result_bundle="${result_root}/${1}Tests.xcresult"
mkdir -p "$result_root"
rm -rf "$result_bundle"

args=(
  test
  -project "${PROJECT:-LocalTranscriber.xcodeproj}"
  -scheme "${SCHEME:-LocalTranscriber}"
  -destination 'platform=macOS'
  CODE_SIGNING_ALLOWED=NO
  -derivedDataPath "$derived_data_path"
  -resultBundlePath "$result_bundle"
  # 実モデルの取得・ロードは Nightly 専用の only-testing 経路で検証する。
  -skip-testing:LocalTranscriberTests/ModelDownloadIntegrationTests
  -skip-testing:LocalTranscriberTests/ModelAvailabilityPathTests/testWhisperKitLoadsFromDetectedModelFolder
)

# 既存の範囲を維持する: CI は UI を除外し、Release は UI も実行する。
if [[ "$1" == ci ]]; then
  args+=(-skip-testing:LocalTranscriberUITests)
fi

xcodebuild "${args[@]}"

# R04: 0件実行や全件スキップを成功と誤認しないよう xcresult サマリを検証・記録する。
summary="$(xcrun xcresulttool get test-results summary --path "$result_bundle" --compact)"
read -r total executed passed failed skipped < <(
  printf '%s' "$summary" | python3 -c '
import json, sys
data = json.load(sys.stdin)
total = int(data.get("totalTestCount", 0))
devices = data.get("devicesAndConfigurations", [])
passed = sum(int(d.get("passedTests", 0)) for d in devices)
failed = sum(int(d.get("failedTests", 0)) for d in devices)
expected = sum(int(d.get("expectedFailures", 0)) for d in devices)
skipped = sum(int(d.get("skippedTests", 0)) for d in devices)
executed = passed + failed + expected
print(total, executed, passed, failed, skipped)
'
)
echo "Test summary ($1): executed=$executed passed=$passed failed=$failed skipped=$skipped total=$total"
if [[ "$total" -eq 0 || "$executed" -eq 0 ]]; then
  echo "FAIL: $1 test suite executed 0 tests (total=$total, skipped=$skipped)" >&2
  exit 1
fi
