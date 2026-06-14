# ロードマップ

## 実装フェーズ

### Phase 1: 最小 CLI / サービス検証

GUI より先に、Swift コードから WhisperKit を呼び出して文字起こしできるか確認する。

やること:

```text
- Xcodeプロジェクト作成
- Swift PackageでWhisperKit追加
- サンプル音声を1つ文字起こし
- fullText取得
- segment情報取得可否確認
- Tiny / Base / Large系で速度比較
```

完了条件:

```text
- ローカル音声ファイルをSwiftから文字起こしできる
- モデル指定ができる
- 日本語音声で実用レベルの結果が出る
- 失敗時のエラー内容を取得できる
```

### Phase 2: GUI MVP

次に SwiftUI 画面を作る。

やること:

```text
- メインウィンドウ作成
- ファイル選択
- ドラッグ&ドロップ
- モデル選択
- 言語選択
- 文字起こし開始
- 結果表示
- キャンセル
```

この時点では、履歴や複雑なモデル管理はまだ入れない。

完了条件:

```text
- ファイルを選んでボタンを押すと文字起こしできる
- 処理中にUIが固まらない
- キャンセルできる
- 文字起こし結果をコピーできる
```

### Phase 3: エクスポート

やること:

```text
- TXT出力
- Markdown出力
- JSON出力
- SRT出力
- VTT出力
```

完了条件:

```text
- セグメント単位のタイムスタンプ付き字幕を保存できる
- 保存先をユーザーが選べる
- 保存失敗時にわかりやすいエラーを出せる
```

### Phase 4: モデル管理

ここでアプリらしくする。

やること:

```text
- モデル未準備状態の表示
- 初回ダウンロード導線
- ダウンロード進捗
- モデル削除
- 推奨モデル表示
- 空き容量チェック
```

WhisperKit には Hugging Face からの自動モデルダウンロードやカスタムモデル対応が案内されている。([Mintlify][2]) ただし、商用・配布を見据えるなら、モデルのライセンス表記、保存先、削除導線はアプリ側で明示した方がよい。

### Phase 5: 履歴・プロジェクト保存

やること:

```text
- 文字起こし履歴
- 元ファイル名
- 生成日時
- 使用モデル
- 言語
- 出力済み形式
- 編集済み本文
```

保存場所:

```text
~/Library/Application Support/LocalTranscriber/
├─ Models/
├─ Transcripts/
├─ Exports/
└─ history.sqlite
```

SwiftData を使うと実装は楽だが、将来的にデータ移行やバックアップを重視するなら SQLite 直叩き、または GRDB のような SQLite ラッパーも候補。MVP では SwiftData で十分。

### Phase 6: 長時間音声対応

会議録アプリとして使うなら、このフェーズが重要。

やること:

```text
- 30分 / 60分 / 120分音声で検証
- メモリ使用量の測定
- 途中結果の保存
- クラッシュ復旧
- VADの有効化検討
- 無音区間での幻聴対策
```

WhisperKit は VAD を機能として案内している。([Mintlify][2]) ただし MVP では VAD を最初から複雑に設定せず、まずは標準設定で動く状態を作り、その後に無音区間の精度問題を見て調整するのがよい。

### Phase 7: 配布

やること:

```text
- Releaseビルド
- Developer ID署名
- Notarization
- DMG作成
- GitHub Actions release workflow
- GitHub Releases への DMG 公開
- GitHub Pages から releases/latest へ誘導
```

完了条件:

```text
- v*.*.* タグ push で署名・公証済み Transnote-{version}.dmg が GitHub Releases に公開される
- GitHub Pages にダウンロード導線とインストール案内がある
- 必要な GitHub Secrets 未設定時は配布 workflow が失敗する
```

Mac App Store 外で配布する場合、Developer ID で署名し、Apple の Notarization に提出する流れを想定する。Apple は、Mac App Store 外で配布する Developer ID 署名ソフトウェアについて、公証により Gatekeeper がソフトウェアの改ざんや既知マルウェアでないことを確認できると説明している。([Apple Developer][4])

## 開発スケジュール案

|  期間 | 内容           | 成果物                               |
| --: | ------------ | --------------------------------- |
| 1週目 | WhisperKit検証 | Swiftから音声1本を文字起こし                 |
| 2週目 | GUI MVP      | ファイル選択→文字起こし→表示                   |
| 3週目 | 出力機能         | TXT / Markdown / JSON / SRT / VTT |
| 4週目 | モデル管理        | モデルDL、選択、削除                       |
| 5週目 | 履歴・設定        | 履歴、保存先、言語設定                       |
| 6週目 | 長時間音声テスト     | 60分以上の音声で安定化                      |
| 7週目 | 配布準備         | 署名、公証、DMG                         |
| 8週目 | β版           | 実ユーザーテスト                          |

## v1 以降の拡張

| 機能       | 優先度 | 実装方針                 |
| -------- | --: | -------------------- |
| 動画ファイル対応 |   高 | AVFoundationで音声抽出    |
| リアルタイム録音 |   高 | WhisperKit streaming |
| 話者分離     | 中〜高 | SpeakerKitを検討        |
| 用語辞書     |   中 | 後処理で固有名詞補正           |
| 字幕エディタ   |   中 | セグメント編集UI            |
| 議事録化     |   中 | ローカルLLM or 手動テンプレ    |
| メニューバー常駐 | 低〜中 | dictation用途向け        |

`argmax-oss-swift` には WhisperKit だけでなく SpeakerKit も含まれており、話者分離系の導線も公式 README にある。([GitHub][1]) ただし、話者分離は UI とデータ構造が一段複雑になるので、MVP 後に回すべき。

## 実装優先順位

最短で形にするなら、この順:

```text
1. WhisperKitをSwift Packageで追加
2. 固定音声ファイルを文字起こし
3. SwiftUIでファイル選択
4. 文字起こし結果をTextEditorに表示
5. TXT保存
6. SRT / VTT保存
7. モデル選択
8. 履歴
9. 長時間音声対応
10. DMG配布
```

## バージョン計画

このプロジェクトは、まず **SwiftUI + WhisperKit のみ** で進めるのが最もよい。

```text
v0.1: ファイル選択 → 文字起こし → TXT保存
v0.2: SRT / VTT / JSON、モデル選択
v0.3: 履歴、設定、長時間音声対応
v0.4: モデル管理、エラー処理強化
v1.0: 署名・公証済みDMG配布
v1.1: 動画対応、話者分離、録音
```

Python や Rust は、現段階では入れない方がよい。**Swift だけで MVP を作り、WhisperKit の限界が見えた時点で Rust / whisper.cpp バックエンドを追加検討**するのが堅実。

[1]: https://github.com/argmaxinc/argmax-oss-swift "GitHub - argmaxinc/argmax-oss-swift: On-device Speech AI for Apple Silicon · GitHub"
[2]: https://www.mintlify.com/explore/argmaxinc/WhisperKit "WhisperKit Documentation - WhisperKit"
[4]: https://developer.apple.com/support/developer-id/ "Developer ID - Support"
