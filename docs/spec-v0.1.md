# v0.1 仕様

最初のリリースはこの範囲に切る。

```text
対象OS: macOS 14+
開発環境: Xcode 16+
UI: SwiftUI
文字起こし: WhisperKit
入力: wav, mp3, m4a, flac
出力: txt, md, json, srt, vtt
言語: auto, ja, en
モデル: tiny, base, small, large-v3系
保存: ローカルのみ
通信: モデルDL時のみ
```

## スコープ外

以下は v0.1 には含めない。

- 動画ファイル
- 話者分離
- リアルタイム録音
- 要約
- 用語辞書

## 前提技術

WhisperKit は `argmaxinc/argmax-oss-swift` の Swift Package として提供され、`WhisperKit` / `TTSKit` / `SpeakerKit` を個別プロダクトとして追加できる。公式 README では前提環境が **macOS 14.0 以降、Xcode 16.0 以降** とされている。([GitHub][1])

ローカル音声ファイルの文字起こしは `WhisperKit().transcribe(audioPath:)` のように呼び出せる構成で、WAV / MP3 / M4A / FLAC などの形式が案内されている。([GitHub][1]) WhisperKit のドキュメントではリアルタイムストリーミング、ワードレベルタイムスタンプ、VAD、モデル管理も主要機能として説明されている。([Mintlify][2])

## MVP フロー

```text
ローカル音声・動画ファイルを選択
↓
WhisperKitでオンデバイス文字起こし
↓
結果を画面表示
↓
TXT / SRT / VTT / JSONで保存
```

[1]: https://github.com/argmaxinc/argmax-oss-swift "GitHub - argmaxinc/argmax-oss-swift: On-device Speech AI for Apple Silicon · GitHub"
[2]: https://www.mintlify.com/explore/argmaxinc/WhisperKit "WhisperKit Documentation - WhisperKit"
