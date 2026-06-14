# インストール手順

Transnote は macOS 14 以降向けのオンデバイス文字起こしアプリです。

## ダウンロード

1. [GitHub Releases (latest)](https://github.com/T3pp31/Transnote/releases/latest) を開きます。
2. `Transnote-<version>.dmg` をダウンロードします。
3. 配布ページから案内される場合は [GitHub Pages](https://t3pp31.github.io/Transnote/) からも同じリンクへ遷移できます。

## インストール

1. ダウンロードした DMG を開きます。
2. **Transnote** を **Applications** フォルダへドラッグします。
3. 必要に応じて DMG を取り出します。

## 初回起動

1. Applications から Transnote を起動します。
2. 未署名ビルドのため、macOS の Gatekeeper により「開発元を確認できない」などの警告が出ることがあります:
   - **推奨**: Finder で Transnote を右クリック → **開く** を選択する（2 回目以降は通常どおり起動できます）
   - または、システム設定 → プライバシーとセキュリティ で Transnote の起動を許可する
3. 初回利用時は Whisper モデルのダウンロードが必要です。画面の案内に従ってください。
4. モデル取得時のみインターネット接続が必要です。文字起こし処理自体は端末内で完結します。

## ファイルアクセス

Transnote は App Sandbox 上で動作します。音声ファイルの読み込みや書き出しには、ファイル選択ダイアログまたはドラッグ&ドロップでユーザーが選んだファイルへのアクセス権が必要です。

## アンインストール

1. Applications から Transnote をゴミ箱へ移動します。
2. 必要に応じて `~/Library/Application Support/LocalTranscriber/` 以下のデータを削除します。

## トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| アプリが開かない | Finder で右クリック → **開く** を試す。それでも開かない場合は DMG から再インストールする |
| モデルが取得できない | ネットワーク接続とファイアウォール設定を確認する |
| 文字起こしが遅い | より小さいモデルを選ぶ、または長時間音声を分割する |

問題が続く場合は [GitHub Issues](https://github.com/T3pp31/Transnote/issues) に報告してください。
