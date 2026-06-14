# Transnote

macOS 向けのオンデバイス文字起こしアプリ。ローカルの音声ファイルを WhisperKit で処理し、結果を画面表示・エクスポートする。音声データは端末内で完結し、クラウド送信は行わない。内部アプリ名は LocalTranscriber、公開名は Transnote。

技術スタックは SwiftUI + WhisperKit のネイティブ構成とし、Python や Rust は採用しない。

## ダウンロード

| 方法 | リンク |
| --- | --- |
| 最新版 DMG | [GitHub Releases (latest)](https://github.com/T3pp31/Transnote/releases/latest) |
| 配布ページ | [GitHub Pages](https://t3pp31.github.io/Transnote/) |

インストール手順は [docs/install.md](docs/install.md) を参照。

## ステータス

| 項目 | 状態 |
| --- | --- |
| フェーズ | v0.1 実装・配布準備 |
| 実装 | SwiftUI アプリ、テスト、CI 稼働中 |
| 配布 | 未署名 DMG（GitHub Actions） |

## MVP フロー

```text
ローカル音声ファイルを選択
↓
WhisperKitでオンデバイス文字起こし
↓
結果を画面表示
↓
TXT / SRT / VTT / JSONで保存
```

## 技術スタック

| 領域 | 技術 |
| --- | --- |
| UI | SwiftUI |
| 文字起こし | [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) |
| 音声処理 | AVFoundation |
| データ永続化 | SwiftData または SQLite |
| 配布 | 未署名 DMG（GitHub Actions） |

## 要件

| 項目 | バージョン |
| --- | --- |
| macOS | 14.0 以降 |
| Xcode | 16.0 以降 |

WhisperKit は `argmaxinc/argmax-oss-swift` の Swift Package として提供される。前提環境は公式 README に準拠する。

## 開発者向けビルド

```bash
# Xcode プロジェクトを再生成する場合
python3 scripts/generate_xcodeproj.py

# テスト（署名なし）
xcodebuild test \
  -project LocalTranscriber.xcodeproj \
  -scheme LocalTranscriber \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath DerivedData

# Debug ビルド
xcodebuild build \
  -project LocalTranscriber.xcodeproj \
  -scheme LocalTranscriber \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Release ビルドと DMG 作成の運用は [docs/distribution.md](docs/distribution.md) を参照。未署名配布のため GitHub Secrets は不要です。

## バージョン計画（概要）

| バージョン | 内容 |
| --- | --- |
| v0.1 | ファイル選択、文字起こし、TXT 保存 |
| v0.2 | SRT / VTT / JSON、モデル選択 |
| v0.3 | 履歴、設定、長時間音声対応 |
| v0.4 | モデル管理、エラー処理強化 |
| v1.0 | 配布導線の安定化（署名は任意） |
| v1.1 | 動画対応、話者分離、録音 |

詳細は [docs/roadmap.md](docs/roadmap.md) を参照。

## ドキュメント

| ファイル | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | アプリ構成、モジュール設計、画面設計 |
| [docs/roadmap.md](docs/roadmap.md) | 実装フェーズ、スケジュール、拡張計画 |
| [docs/spec-v0.1.md](docs/spec-v0.1.md) | v0.1 の仕様とスコープ |
| [docs/install.md](docs/install.md) | エンドユーザー向けインストール手順 |
| [docs/distribution.md](docs/distribution.md) | Release 運用 |

## 参考リンク

- [WhisperKit（argmax-oss-swift）](https://github.com/argmaxinc/argmax-oss-swift) — Swift Package、モデル管理、文字起こし API
- [WhisperKit ドキュメント](https://www.mintlify.com/explore/argmaxinc/WhisperKit) — ストリーミング、VAD、タイムスタンプ
- [macOS App Sandbox でのファイルアクセス](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) — Security-scoped bookmark 設計の参考
- [Developer ID](https://developer.apple.com/support/developer-id/) — Mac App Store 外配布時の署名・公証
