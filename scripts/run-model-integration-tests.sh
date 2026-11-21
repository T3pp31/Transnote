#!/usr/bin/env bash
# 実モデル統合テストをセレクタごとに実行し、0件実行を失敗させる。
# Nightly と Release で共有する。リポジトリのルートから呼び出す。
set -euo pipefail

# セレクタごとに個別実行する。未一致の -only-testing は黙って無視されるため、
# 別セレクタの成功で隠れないようにする。
model_test_selectors=(
  LocalTranscriberTests/ModelDownloadIntegrationTests
  LocalTranscriberTests/ModelAvailabilityPathTests/testWhisperKitLoadsFromDetectedModelFolder
)

project="${PROJECT:-LocalTranscriber.xcodeproj}"
scheme="${SCHEME:-LocalTranscriber}"
derived_data_path="${DERIVED_DATA_PATH:-DerivedData}"
result_root="${RESULT_ROOT:-${derived_data_path}/TestResults}"
# 失敗メッセージに含める呼び出し元の名前（nightly / release）。
gate_name="${GATE_NAME:-real-model}"

for selector in "${model_test_selectors[@]}"; do
  result_bundle="${result_root}/${gate_name}ModelTests-${selector##*/}.xcresult"
  rm -rf "$result_bundle"
  xcodebuild test \
    -project "$project" \
    -scheme "$scheme" \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$derived_data_path" \
    -resultBundlePath "$result_bundle" \
    "-only-testing:$selector"

  summary="$(xcrun xcresulttool get test-results summary --path "$result_bundle" --compact)"
  total="$(echo "$summary" | python3 -c 'import json,sys; print(json.load(sys.stdin)["totalTestCount"])')"
  executed="$(echo "$summary" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(sum(item["passedTests"] + item["failedTests"] + item["expectedFailures"] for item in data["devicesAndConfigurations"]))')"
  echo "Executed tests for $selector: $executed (total: $total)"
  if [[ "$total" -eq 0 || "$executed" -eq 0 ]]; then
    echo "FAIL: ${gate_name} real-model tests did not execute for $selector" >&2
    exit 1
  fi
done
