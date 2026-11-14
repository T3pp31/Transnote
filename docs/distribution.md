# 配布運用

Transnote の Release ビルド、DMG 作成、GitHub Releases 公開は GitHub Actions で自動化しています。現在は **未署名ビルド** を配布しています。

## 配布フロー概要

```text
vX.Y.Z タグ push または workflow_dispatch
  → テスト
  → 実モデル取得・検出・ロードの必須テスト
  → Release archive（署名なし）
  → Transnote.app を取り出し
  → DMG 作成（Transnote.app + インストール.command + Applications リンク）
  → SHA256 チェックサム生成
  → SBOM 生成（Transnote-<version>.cdx.json）
  → GitHub Release へアップロード（DMG + .sha256 + SBOM、本文にハッシュ記載）
```

タグ・手動リリースのどちらでも、アーカイブ前に `ModelDownloadIntegrationTests` と `ModelAvailabilityPathTests/testWhisperKitLoadsFromDetectedModelFolder` を `RUN_MODEL_INTEGRATION_TESTS=1` で個別実行します。XCTest プロセスへは `TEST_RUNNER_RUN_MODEL_INTEGRATION_TESTS=1` を通して有効化フラグを渡します。Nightly の過去の結果ではなく、リリース対象のコードで tiny モデルの実取得・フォルダ検出・WhisperKit ロードを確認します。テスト失敗、セレクタ未検出、全件スキップ、結果解析失敗、120 分のタイムアウト時は配布に進みません。モデル配布元のネットワーク障害もリリースを止めるため、復旧後に再実行してください（実文字起こしや全モデルの品質を保証するテストではありません）。

GitHub Pages は `main` ブランチの `site/` 更新時に自動デプロイされ、[releases/latest](https://github.com/T3pp31/Transnote/releases/latest) へ誘導します。

## GitHub Secrets

未署名配布では **GitHub Secrets は不要** です。Release workflow はそのまま実行できます。

将来、Developer ID 署名と Notarization を導入する場合は、[Apple Developer Program](https://developer.apple.com/programs/) への加入と CI 用証明書（`APPLE_CERTIFICATE_BASE64` 等）の GitHub Secrets 設定が必要です。現時点では SHA256 チェックサム配布で整合性確認を提供しています。

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
| `scripts/release-security-notice.sh` | `SIGNED` / `NOTARIZED` に応じた署名案内（Release 本文・DMG README 共通） |
| `scripts/generate-sbom.sh` | Syft で CycloneDX JSON 形式の SBOM を生成 |
| `scripts/install-transnote.command` | DMG 同梱用インストールスクリプト（旧版削除→新版配置） |
| `Config/distribution.plist` | 配布時のアプリ名・旧名・インストールスクリプト名 |
| `Config/sbom.plist` | SBOM 生成設定（Syft バージョン・出力形式・パス） |

配布物のアプリ名の正本は `Config/distribution.plist` の `AppName` です。Release workflow のアプリ名・archive パス、export、DMG、Release / CI の SBOM ファイル名と Release の既定スキャン対象はこの値を参照します。`Config/sbom.plist` にはアプリ名を定義せず、`{AppName}` を使って出力名を指定します（`generate-sbom.sh --config` で SBOM 設定を差し替えた場合も同様）。Xcode の製品名やユーザー向けドキュメントの改名は別途必要です。

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

DMG 内の `初めにお読みください.txt` は `Config/dmg-gatekeeper-readme.txt` から生成し、署名案内のプレースホルダーを共通スクリプトで埋め込みます。Release workflow は署名・公証の成功時に設定した `SIGNED` / `NOTARIZED` をそのまま利用します。ローカルでは未設定なら未署名として案内します。署名済みアプリをパッケージする場合は、実際の状態に応じて `SIGNED=1`、公証済みなら加えて `NOTARIZED=1` を環境変数で渡してください。

### SBOM の例

CI では `Package.resolved`（宣言依存のロックファイル）を Ubuntu 上で、Release では配布用 `Transnote.app` を macOS 上でスキャンします。Whisper モデルなどランタイムで取得するコンポーネントは SBOM 対象外です。`generate-sbom.sh` は macOS では PlistBuddy、Linux では python3 + plistlib で `Config/sbom.plist` と `Config/distribution.plist` を読みます。`--print AppName` は配布設定の値を返し、その他の `--print` キーは従来どおり SBOM 設定の値を返します。

```bash
# CI 相当（依存ロックのみ）
./scripts/generate-sbom.sh --mode ci

# Release 相当（.app が必要）
./scripts/generate-sbom.sh --mode release --version 0.1.0
```

生成物は `build/sbom/` に出力されます。CI では artifact `sbom-cyclonedx` として保存されます（保持 30 日）。

`generate-sbom.sh` は生成後に CycloneDX の `library` 型 `components` が 1 件以上あることを検証し、0 件の場合は非ゼロ終了で CI / Release を失敗させます（Syft の退行やスキャン失敗で空 SBOM が artifact に残るのを防ぐ）。

## Pages の有効化

初回のみ、リポジトリ設定で GitHub Pages の Source を **GitHub Actions** に設定してください。以降は `pages.yml` が `site/` をデプロイします。

## 成果物

| ファイル | 説明 |
| --- | --- |
| `Transnote-<version>.dmg` | 未署名アプリを格納した配布用 DMG |
| `Transnote.dmg` | 最新版向けエイリアス DMG（内容は versioned と同一） |
| `Transnote-<version>.dmg.sha256` | versioned DMG の SHA256 チェックサム |
| `Transnote.dmg.sha256` | latest DMG の SHA256 チェックサム |
| `Transnote-<version>.cdx.json` | CycloneDX JSON 形式の SBOM（配布バイナリベース、Release 添付） |
| `Transnote-sbom.cdx.json` | CycloneDX JSON 形式の SBOM（依存ロックベース、CI artifact） |
| `Transnote.app` | Bundle ID `com.transnote.LocalTranscriber` |
| `インストール.command` | DMG 内のワンクリックインストーラー（旧版を削除してから配置） |
| `初めにお読みください.txt` | ビルドの署名・公証状態と、警告が表示された場合のインストール手順 |
| `distribution.plist` | DMG 内に同梱される配布設定（インストールスクリプトが参照） |

## ユーザー向け注意

未署名アプリは初回起動時に macOS の Gatekeeper 警告が出ることがあります。**インストール.command** も同様に、ダブルクリックでは「開いていません」とブロックされる場合があります。右クリック → 開く でも通らないことがあるため、DMG 内の `初めにお読みください.txt` または [docs/install.md](install.md) の **ターミナル実行手順**（`bash` での実行）を案内してください。

インストールスクリプトは配置後に Applications 内アプリから検疫属性のみを除去するため、インストール直後の起動がスムーズになります。

同じインストール先への多重起動は、インストール先の `.transnote-install.lock` ディレクトリで拒否します。ロックは処理の終了時（失敗時は旧版の復元後）に解放されます。強制終了（SIGKILL）や電源断でロックが残った場合は、すべてのインストール処理が終了していることを確認してから、このロックディレクトリを手動で削除して再実行してください。

## 検証コマンド

```bash
# ダウンロード後の整合性確認（ユーザー向け）
shasum -a 256 -c Transnote-0.1.0.dmg.sha256

# SBOM の妥当性確認（開発者向け）
# generate-sbom.sh 実行時にも library components の件数チェックが行われる
jq -e '[.components[]? | select(.type == "library")] | length > 0' build/sbom/Transnote-sbom.cdx.json

hdiutil verify Transnote-0.1.0.dmg
ls -la build/release/Transnote.app/Contents/MacOS/Transnote

# DMG 内容の確認
MOUNT_DIR="$(mktemp -d)"
hdiutil attach Transnote-0.1.0.dmg -mountpoint "$MOUNT_DIR"
ls -la "$MOUNT_DIR"
# Transnote.app, インストール.command, 初めにお読みください.txt, distribution.plist, Applications があること
hdiutil detach "$MOUNT_DIR"
```
