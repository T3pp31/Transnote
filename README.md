# Transnote

macOS 向けのオンデバイス文字起こしアプリ。ローカルの音声ファイルを WhisperKit で処理し、結果を画面表示・エクスポートする。音声データは端末内で完結し、クラウド送信は行わない。内部アプリ名は LocalTranscriber を想定している。

技術スタックは SwiftUI + WhisperKit のネイティブ構成とし、Python や Rust は採用しない。

## ステータス

| 項目 | 状態 |
| --- | --- |
| フェーズ | 設計・計画 |
| 実装 | 未着手 |
| リポジトリ | README と設計ドキュメントのみ |

## 計画している MVP フロー

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
| 配布 | Developer ID 署名 + Notarization + DMG |

## 要件

| 項目 | バージョン |
| --- | --- |
| macOS | 14.0 以降 |
| Xcode | 16.0 以降 |

WhisperKit は `argmaxinc/argmax-oss-swift` の Swift Package として提供される。前提環境は公式 README に準拠する。

## バージョン計画（概要）

| バージョン | 内容 |
| --- | --- |
| v0.1 | ファイル選択、文字起こし、TXT 保存 |
| v0.2 | SRT / VTT / JSON、モデル選択 |
| v0.3 | 履歴、設定、長時間音声対応 |
| v0.4 | モデル管理、エラー処理強化 |
| v1.0 | 署名・公証済み DMG 配布 |
| v1.1 | 動画対応、話者分離、録音 |

詳細は [docs/roadmap.md](docs/roadmap.md) を参照。

## ドキュメント

| ファイル | 内容 |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | アプリ構成、モジュール設計、画面設計 |
| [docs/roadmap.md](docs/roadmap.md) | 実装フェーズ、スケジュール、拡張計画 |
| [docs/spec-v0.1.md](docs/spec-v0.1.md) | v0.1 の仕様とスコープ |

## 参考リンク

- [WhisperKit（argmax-oss-swift）](https://github.com/argmaxinc/argmax-oss-swift) — Swift Package、モデル管理、文字起こし API
- [WhisperKit ドキュメント](https://www.mintlify.com/explore/argmaxinc/WhisperKit) — ストリーミング、VAD、タイムスタンプ
- [macOS App Sandbox でのファイルアクセス](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) — Security-scoped bookmark 設計の参考
- [Developer ID](https://developer.apple.com/support/developer-id/) — Mac App Store 外配布時の署名・公証
