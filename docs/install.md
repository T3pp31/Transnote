# インストール手順

Transnote は macOS 14 以降向けのオンデバイス文字起こしアプリです。

## ダウンロード

1. [GitHub Releases (latest)](https://github.com/T3pp31/Transnote/releases/latest) を開きます。
2. `Transnote-<version>.dmg` または `Transnote.dmg` をダウンロードします。
3. 配布ページから案内される場合は [GitHub Pages](https://t3pp31.github.io/Transnote/) からも同じリンクへ遷移できます。

## インストール（推奨）

1. ダウンロードした DMG を開きます。
2. DMG 内の **初めにお読みください.txt** に Gatekeeper 回避手順が記載されています（未署名配布のため、初回は追加操作が必要な場合があります）。
3. DMG 内の **インストール.command** をダブルクリックします。
   - **「開いていません」** と表示され、**ゴミ箱に入れる / 完了** だけのダイアログが出る場合は、ダブルクリックでは実行できません。次のいずれかを行ってください。
     - **推奨**: `インストール.command` を右クリック → **開く** → 確認ダイアログで **開く**
     - **ターミナル**: 次を実行（ボリューム名は DMG により `Transnote` など）
       ```bash
       xattr -cr "/Volumes/Transnote/"
       bash "/Volumes/Transnote/インストール.command"
       ```
4. インストールが完了すると Transnote が起動します。
5. 必要に応じて DMG を取り出します。

インストールスクリプトは、Applications 内の旧バージョン（`Transnote.app` および旧名 `LocalTranscriber.app`）を削除してから新バージョンを配置します。起動中の Transnote がある場合は自動的に終了してから置き換えます。

## インストール（上級者向け: ドラッグ&ドロップ）

手動で配置する場合は、次の手順を守ってください。

1. 実行中の Transnote を終了します。
2. Applications フォルダ内の既存の `Transnote.app`（および `LocalTranscriber.app` があればそれも）を削除します。
3. DMG 内の **Transnote** を **Applications** フォルダへドラッグします。

この方法では、アプリが起動中だったり旧版が残っていると `Transnote 2.app` などの重複ができることがあります。**通常は上記のインストールスクリプトを使うことを推奨します。**

## 初回起動

1. Applications から Transnote を起動します。
2. 未署名ビルドのため、macOS の Gatekeeper により「開発元を確認できない」などの警告が出ることがあります:
   - **推奨**: Finder で Transnote を右クリック → **開く** を選択する（2 回目以降は通常どおり起動できます）
   - または、システム設定 → プライバシーとセキュリティ で Transnote の起動を許可する
3. 初回利用時は Whisper モデルのダウンロードが必要です。画面の案内に従ってください。
4. モデル取得時のみインターネット接続が必要です。文字起こし処理自体は端末内で完結します。

## 更新

新しいバージョンがリリースされたら、最新の DMG をダウンロードし、**インストール.command** を実行してください。旧バージョンは自動的に置き換えられます。ユーザーデータ（`~/Library/Application Support/LocalTranscriber/`）は保持されます。

## ファイルアクセス

Transnote は App Sandbox 上で動作します。音声ファイルの読み込みや書き出しには、ファイル選択ダイアログまたはドラッグ&ドロップでユーザーが選んだファイルへのアクセス権が必要です。

## アンインストール

1. Applications から Transnote をゴミ箱へ移動します。
2. 必要に応じて `~/Library/Application Support/LocalTranscriber/` 以下のデータを削除します。

## トラブルシューティング

| 症状 | 対処 |
| --- | --- |
| アプリが開かない | Finder で右クリック → **開く** を試す。それでも開かない場合は DMG から再インストールする |
| インストールスクリプトが実行できない（「開いていません」） | 右クリック → **開く** を選ぶ。それでも失敗する場合は `xattr -cr "/Volumes/Transnote/"` のあと `bash "/Volumes/Transnote/インストール.command"` を実行する |
| 旧バージョンが残る | **インストール.command** を使って再インストールする。手動ドラッグの場合は Applications 内の重複を削除してから再度配置する |
| モデルが取得できない | ネットワーク接続とファイアウォール設定を確認する |
| 文字起こしが遅い | より小さいモデルを選ぶ、または長時間音声を分割する |

問題が続く場合は [GitHub Issues](https://github.com/T3pp31/Transnote/issues) に報告してください。
