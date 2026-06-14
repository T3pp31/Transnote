# アーキテクチャ

Transnote（内部アプリ名: LocalTranscriber）は **SwiftUI + WhisperKit** のネイティブ macOS アプリとして設計する。Python や Rust は v1 では採用しない。

MVP では **SwiftUI + WhisperKit + AVFoundation + SwiftData または SQLite** で十分。Rust を入れるとビルドと配布の複雑さが増えるため、v1 では避ける。

## 推奨アプリ構成

```text
LocalTranscriber/
├─ LocalTranscriberApp.swift
├─ Presentation/
│  ├─ MainWindowView.swift
│  ├─ FileDropView.swift
│  ├─ TranscriptEditorView.swift
│  ├─ SettingsView.swift
│  └─ HistoryView.swift
│
├─ Domain/
│  ├─ TranscriptionJob.swift
│  ├─ Transcript.swift
│  ├─ TranscriptSegment.swift
│  ├─ AppSettings.swift
│  └─ ExportFormat.swift
│
├─ Services/
│  ├─ WhisperKitTranscriber.swift
│  ├─ AudioFileService.swift
│  ├─ ModelManager.swift
│  ├─ ExportService.swift
│  ├─ HistoryStore.swift
│  └─ SecurityScopedFileAccess.swift
│
├─ Infrastructure/
│  ├─ AppDirectories.swift
│  ├─ Logger.swift
│  └─ ErrorMapper.swift
│
└─ Tests/
   ├─ ExportServiceTests.swift
   ├─ TranscriptModelTests.swift
   └─ TranscriptionSmokeTests.swift
```

## 主要モジュール設計

### WhisperKitTranscriber

WhisperKit を直接触る部分はここに閉じ込める。

責務:

```text
- WhisperKit初期化
- モデル指定
- 言語指定
- 音声ファイルの文字起こし
- 進捗通知
- キャンセル
- エラー整形
```

想定インターフェース:

```swift
protocol Transcriber {
    func transcribe(_ job: TranscriptionJob) async throws -> Transcript
    func cancel(jobID: UUID)
}
```

WhisperKit では、モデルを指定しない場合にデバイス向けの推奨モデルを自動選択・ダウンロードでき、明示的に `WhisperKitConfig(model:)` でモデル指定する例も示されている。([GitHub][1])

### ModelManager

モデル管理は UX 上かなり重要。

機能:

```text
- 利用可能モデル一覧
- 未ダウンロード / ダウンロード済み状態
- モデル容量表示
- 推奨モデル表示
- モデル削除
- 初回起動時のモデル準備
```

初期ラインナップ:

| 表示名                       | 想定用途         |
| ------------------------- | ------------ |
| Tiny                      | 動作確認・高速プレビュー |
| Base                      | 軽量利用         |
| Small                     | 日常利用         |
| Large v3 Turbo compressed | 精度重視         |
| Large v3 Turbo            | macOS高性能機向け  |

公式 README では、`large-v3-v20240930_626MB` が多言語精度重視の推奨、`tiny` がデバッグ用の最速ワークフローとして案内されている。([GitHub][1])

### AudioFileService

音声・動画ファイルの扱いを担当する。

MVP ではまず音声ファイル中心にして、動画ファイル対応は少し後ろに置くのが安全。WhisperKit が案内している入力例は WAV / MP3 / M4A / FLAC なので、まずはこの 4 形式を正式対応にする。([Mintlify][2])

MVP 対応:

```text
- wav
- mp3
- m4a
- flac
```

v0.2 以降:

```text
- mp4
- mov
- 音声抽出
- 音声波形プレビュー
```

### ExportService

出力は WhisperKit 依存にせず、自前で安定実装する。

対応形式:

```text
- TXT
- Markdown
- SRT
- VTT
- JSON
```

`Transcript` はこの形で持つのが扱いやすい。

```swift
struct Transcript: Codable, Identifiable {
    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
}

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
}
```

ワードレベルタイムスタンプが必要になる字幕編集機能は v1.1 以降でよい。WhisperKit ドキュメント上はワードレベルタイムスタンプが主要機能として案内されているが、MVP ではまずセグメント単位で十分。([Mintlify][2])

## 画面設計

### MainWindow

```text
┌──────────────────────────────────────────────┐
│ Toolbar: モデル / 言語 / 開始 / 保存          │
├───────────────┬──────────────────────────────┤
│ 履歴・ファイル │ 文字起こし結果エディタ        │
│               │                              │
├───────────────┴──────────────────────────────┤
│ 進捗バー / 状態 / キャンセル                  │
└──────────────────────────────────────────────┘
```

### 必須 UI

| UI     | 内容                           |
| ------ | ---------------------------- |
| ファイル投入 | ドラッグ&ドロップ、ファイル選択             |
| モデル選択  | Tiny / Base / Small / Large系 |
| 言語選択   | Auto / Japanese / English    |
| 結果表示   | 編集可能なテキストビュー                 |
| 進捗表示   | 初期化中、モデルDL中、文字起こし中、完了        |
| 保存     | TXT / SRT / VTT / JSON       |
| 履歴     | 過去の文字起こし結果                   |

macOS App Sandbox ではアプリのファイルアクセスが制限されるため、ユーザーが選択したファイルやフォルダを扱う設計にする。永続的にアクセスしたい出力先を保存する場合は、Security-scoped bookmark を使う前提で設計する。([Apple Developer][3])

[1]: https://github.com/argmaxinc/argmax-oss-swift "GitHub - argmaxinc/argmax-oss-swift: On-device Speech AI for Apple Silicon · GitHub"
[2]: https://www.mintlify.com/explore/argmaxinc/WhisperKit "WhisperKit Documentation - WhisperKit"
[3]: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox "Accessing files from the macOS App Sandbox"
