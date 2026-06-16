# 配布運用

Transnote の Release ビルド、DMG 作成、GitHub Releases 公開は GitHub Actions で自動化しています。現在は **未署名ビルド** を配布しています。

## 配布フロー概要

```text
vX.Y.Z タグ push または workflow_dispatch
  → テスト
  → Release archive（署名なし）
  → Transnote.app を取り出し
  → DMG 作成（Transnote.app + インストール.command + Applications リンク）
  → GitHub Release へアップロード
```

GitHub Pages は `main` ブランチの `site/` 更新時に自動デプロイされ、[releases/latest](https://github.com/T3pp31/Transnote/releases/latest) へ誘導します。

## GitHub Secrets

未署名配布では **GitHub Secrets は不要** です。Release workflow はそのまま実行できます。

将来、Developer ID 署名と Notarization を導入する場合は、Apple Developer Program への加入と証明書の準備が必要です。

## リリース手順

### タグからリリース

```bash
git tag v0.1.0
git push origin v0.1.0
```

`v*.*.*` 形式のタグ push で `.github/workflows/release.yml` が起動します。

### 手動リリース

1. GitHub の **Actions → Release → Run workflow** を開く
2. `version` に `v0.1.0` 形式のタグ名を入力する
3. workflow 完了後、GitHub Releases に `Transnote-<version>.dmg` が添付される

## ローカル補助スクリプト

| スクリプト | 用途 |
| --- | --- |
| `scripts/export-release-app.sh` | `.xcarchive` から `Transnote.app` を取り出す |
| `scripts/create-dmg.sh` | `Transnote.app` から `Transnote-<version>.dmg` を作成 |
| `scripts/install-transnote.command` | DMG 同梱用インストールスクリプト（旧版削除→新版配置） |
| `Config/distribution.plist` | 配布時のアプリ名・旧名・インストールスクリプト名 |

### archive の例

```bash
xcodebuild archive \
  -project LocalTranscriber.xcodeproj \
  -scheme LocalTranscriber \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/Transnote.xcarchive \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath DerivedData
```

### export / DMG の例

```bash
./scripts/export-release-app.sh \
  --archive build/Transnote.xcarchive \
  --output build/release

./scripts/create-dmg.sh \
  --app build/release/Transnote.app \
  --version 0.1.0 \
  --output build/dist
```

## Pages の有効化

初回のみ、リポジトリ設定で GitHub Pages の Source を **GitHub Actions** に設定してください。以降は `pages.yml` が `site/` をデプロイします。

## 成果物

| ファイル | 説明 |
| --- | --- |
| `Transnote-<version>.dmg` | 未署名アプリを格納した配布用 DMG |
| `Transnote.app` | Bundle ID `com.transnote.LocalTranscriber` |
| `インストール.command` | DMG 内のワンクリックインストーラー（旧版を削除してから配置） |
| `初めにお読みください.txt` | Gatekeeper 回避手順（未署名配布向け） |
| `distribution.plist` | DMG 内に同梱される配布設定（インストールスクリプトが参照） |

## ユーザー向け注意

未署名アプリは初回起動時に macOS の Gatekeeper 警告が出ることがあります。**インストール.command** も同様に、ダウンロード直後のダブルクリックでは「開いていません」とブロックされる場合があります。DMG 内の `初めにお読みください.txt` または [docs/install.md](install.md) の手順（右クリック → 開く、またはターミナル実行）を案内してください。

インストールスクリプトは配置後に `xattr -cr` で Applications 内アプリの隔離属性を除去するため、インストール直後の起動がスムーズになります。

## 検証コマンド

```bash
hdiutil verify Transnote-0.1.0.dmg
ls -la build/release/Transnote.app/Contents/MacOS/Transnote

# DMG 内容の確認
hdiutil attach Transnote-0.1.0.dmg -mountpoint /tmp/transnote-dmg
ls -la /tmp/transnote-dmg
# Transnote.app, インストール.command, 初めにお読みください.txt, distribution.plist, Applications があること
hdiutil detach /tmp/transnote-dmg
```
