# 配布運用

Transnote の Release ビルド、署名、公証、DMG 作成、GitHub Releases 公開は GitHub Actions で自動化しています。

## 配布フロー概要

```text
vX.Y.Z タグ push または workflow_dispatch
  → テスト
  → Release archive
  → Developer ID 証明書 import
  → アプリ署名
  → notarytool submit --wait
  → staple
  → DMG 作成
  → GitHub Release へアップロード
```

GitHub Pages は `main` ブランチの `site/` 更新時に自動デプロイされ、[releases/latest](https://github.com/T3pp31/Transnote/releases/latest) へ誘導します。

## 必要な GitHub Secrets

Release workflow は以下の Secrets がすべて設定されていない場合、**失敗**します。

| Secret | 用途 |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Notarization 用 Apple ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` | Developer ID Application 証明書 (p12) の Base64 |
| `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` | p12 のパスワード |
| `KEYCHAIN_PASSWORD` | CI 一時 keychain のパスワード |

`DEVELOPMENT_TEAM` は Xcode プロジェクト上では空のままとし、CI では `APPLE_TEAM_ID` を `xcodebuild` や `codesign` に渡します。

## リリース手順

### タグからリリース

```bash
git tag v0.1.0
git push origin v0.1.0
```

`v*.*.*` 形式のタグ push で `.github/workflows/release.yml` が起動します。

### 手動リリース

1. GitHub の **Actions → Release → Run workflow** を開く
2. 必要なら `version` に `v0.1.0` 形式のタグ名を入力する
3. workflow 完了後、GitHub Releases に `Transnote-<version>.dmg` が添付される

## ローカル補助スクリプト

| スクリプト | 用途 |
| --- | --- |
| `scripts/export-release-app.sh` | `.xcarchive` から `Transnote.app` を取り出し、署名検証 |
| `scripts/create-dmg.sh` | `Transnote.app` から `Transnote-<version>.dmg` を作成 |

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

署名と公証は Developer ID 証明書と Apple 認証情報がローカル keychain にある環境でのみ実行できます。

## Pages の有効化

初回のみ、リポジトリ設定で GitHub Pages の Source を **GitHub Actions** に設定してください。以降は `pages.yml` が `site/` をデプロイします。

## 成果物

| ファイル | 説明 |
| --- | --- |
| `Transnote-<version>.dmg` | 公証済みアプリを格納した配布用 DMG |
| `Transnote.app` | Bundle ID `com.transnote.LocalTranscriber` |

## 検証コマンド

```bash
codesign --verify --deep --strict --verbose=2 Transnote.app
spctl --assess --type execute --verbose Transnote.app
xcrun stapler validate Transnote.app
hdiutil verify Transnote-0.1.0.dmg
```
