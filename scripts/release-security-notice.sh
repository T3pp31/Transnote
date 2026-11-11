#!/usr/bin/env bash
# Source from release.yml and create-dmg.sh so both describe the same build state.
# SIGNED and NOTARIZED are set by the release workflow after successful signing.
if [[ "${NOTARIZED:-0}" == "1" ]]; then
  security_notice="Developer ID で署名・公証済みのビルドです。"
  signature_note="このビルドは Developer ID で署名・公証済みです。"
elif [[ "${SIGNED:-0}" == "1" ]]; then
  security_notice="Developer ID で署名済みのビルドです。公証は行われていません。"
  signature_note="このビルドは Developer ID で署名済みです。公証には Apple ID 等の secrets 設定が必要です。"
else
  security_notice="**⚠️ 初回起動時に「マルウェア」という警告が出ても、これはマルウェアではありません。** Transnote は Apple の有料開発者認証（署名）をせずに配布しているため、macOS の Gatekeeper が「マルウェアでないことを確認できない」と表示します。未署名アプリ共通の安全確認の通知で、ウイルス検出ではありません。「完了」で閉じて進んでください（「ゴミ箱に入れる」は押さないでください）。"
  signature_note="現時点では未署名ビルドを配布しています。Developer ID 署名と Notarization には [Apple Developer Program](https://developer.apple.com/programs/) への加入と CI 用証明書の設定が必要です（将来対応予定）。"
fi
