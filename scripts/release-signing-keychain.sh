#!/usr/bin/env bash
# リリース署名（App / DMG）で共通利用する一時キーチェーンの構築・破棄ヘルパー。
# source して setup_signing_keychain / cleanup_signing_keychain を呼び出す。

cleanup_signing_keychain() {
  local keychain_path="$1"
  local cert_path="$2"
  security delete-keychain "$keychain_path" || true
  rm -f "$cert_path"
}

setup_signing_keychain() {
  local keychain_path="$1"
  local cert_path="$2"

  if [[ -z "$keychain_path" || -z "$cert_path" ]]; then
    echo "setup_signing_keychain requires keychain_path and cert_path" >&2
    return 1
  fi
  if [[ -z "${CERTIFICATE_BASE64:-}" || -z "${CERTIFICATE_PASSWORD:-}" ]]; then
    echo "CERTIFICATE_BASE64 and CERTIFICATE_PASSWORD must be set" >&2
    return 1
  fi

  security create-keychain -p "$CERTIFICATE_PASSWORD" "$keychain_path"
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain -p "$CERTIFICATE_PASSWORD" "$keychain_path"
  printf '%s' "$CERTIFICATE_BASE64" | base64 --decode > "$cert_path"
  security import "$cert_path" -k "$keychain_path" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$CERTIFICATE_PASSWORD" "$keychain_path"
  security list-keychain -d user -s "$keychain_path"
}
