# Transnote テスト監査台帳

監査日: 2026年10月23日（日本時間）。基準コミット: `fadfe8fa6f0822f6d8c17891b0344bd4a0398d87`。

リポジトリ内の全 **209 テストケース**を本番コード・呼び出し元・CI 設定と照合した。現状の assertion、実行経路、運用条件では回帰防止の増分が小さい、または保証範囲を誤認させる **45 件**を対応候補とした。重要なのはテスト数の削減より、**失敗時掃除の未接続、存在しない fixture の削除試験、通らない実音声経路**を修復すること。残る 164 件には独立した保護があり、維持を基本とする。

45 件を一括削除する判断ではない。削除候補は 9 件であり、その場合も未使用コードの扱いと代替の本番経路テストを確認する。統合 9 件は有効な入力と assertion を統合先へ残す。改善 18 件・置換 7 件は失敗を検知できる形に直し、診断 2 件は通常の回帰スイートから分離する。この成果物は監査台帳であり、テスト・本番コード・CI の変更は含まない。

## 対象と判定基準

| 対象 | ファイル数 | ケース数 | 数え方 |
| --- | ---: | ---: | --- |
| LocalTranscriberTests | 25 | 198 | 24 テストクラスの test メソッド。補助ファイル 1 件も読了 |
| LocalTranscriberUITests | 1 | 3 | UI の test メソッド |
| site/app.test.js | 1 | 6 | 独自 test 関数の呼出し |
| scripts/test-release-scripts.sh | 1 | 2 | 正常版更新・不正版拒否のシナリオ |
| 合計 | 28 | 209 | ループ内の入力数や assertion 数を重複計上しない |

このほか `verify-readme-version.py`、`generate-site-config.py --check`、Xcode プロジェクト登録、生成スクリプト、CI／Nightly／Release／Pages の実行設定を確認した。これらの整合性チェックを 209 件に混ぜていない。第三者依存の SourcePackages 内のテストは対象外。

判定は、①壊れた動作を assertion が検出できるか、②本番から呼ばれる経路か、③別テストが同じ保護を持つか、④fixture・mock・設定・待機が現実の条件と対応するか、⑤CI で選択され実行前提が揃うか、の 5 点に基づく。短いテストや mock 利用をそれだけで低価値とはしない。空実装・誤った戻り値でも通る理由は個別に記載する。

| 判定 | 件数 |
| --- | ---: |
| 維持 | 164 |
| 統合 | 9 |
| 削除候補 | 9 |
| 改善 | 18 |
| 置換 | 7 |
| 診断へ移動 | 2 |

**証拠の区別:** 「実測」は今回コマンドや一時コピーで再現した結果。「静的確認」は現行の呼出しと assertion から確認できる事実。「未検証経路」は追加の試験が必要な領域であり、そのすべてを既知の本番バグと断定するものではない。

## 優先対応台帳

優先度 P1 は利用者のデータ・処理結果を守る経路の見逃し、P2 は assertion・実行条件・結合の改善、P3 は主に重複や診断用途の整理を表す。全項目の対応状態は **未対応**。テスト ID は後半の全件台帳に対応する。

| ID | 優先度 | 対象テスト | 根拠と失われている保護 | 対応と残すべき検証 |
| --- | --- | --- | --- | --- |
| L01 | P1 | MD02・MD03・MD04 | **静的確認:** [download](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/ModelDownloadService.swift:72) は事前フォルダを控えるが、失敗時に [cleanUpFailedDownload](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/ModelDownloadService.swift:172) を呼ばない。3 件は helper の直接呼出し。コンパイラも事前 snapshot 未使用を警告した。 | 公開 downloadIfNeeded から失敗を注入し、新規 partial／hidden staging の消去と既存モデルの保持を観測する。helper の規則は有用なので、本番との接続を直す前に単純削除しない。 |
| L02 | P1 | AI08・AI09 | **fixture 前提を実測:** AI08 は setUp で root の URL を作るだけで mkdir しない。createFile は false、削除前からファイルなし。AI09 とともに削除 helper が空でも成功する。 | root と実ファイルを作成し存在を前提 assertion にする。削除→同じパスを再削除する流れに統合し、実消去と冪等性を残す。 |
| L03 | P1 | AI10 | **静的確認:** 現行 [importFile](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/AudioImportService.swift:40) は `.名前.tmp-UUID` へコピー。テストが不在確認する `unreadable.wav` は失敗時には元から作られない。 | FileManager spy で実際の一時コピー先を記録するか、hidden を含む全エントリを比較する。copy・streaming・最終 move 失敗後の残骸を観測する。 |
| L10 | P1 | SM01 | **静的確認:** [fixture 探索](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionSmokeTests.swift:5) の sample.wav は Git 管理にも CI 生成手順にもなく、標準 checkout では skip。Nightly はこのテストを選択しない。 | 短い音声と最低限の期待内容を管理し、モデルを用意する専用経路で必ず実行する。通常 PR の単体試験と実音声試験の責務を分ける。非空だけで任意の誤認識を許容しない。 |
| L15 | P1 | EX15 | **静的確認:** `contains("schemaVersion")` と `contains("1")` は対応していない。version が別値でも timestamp や segment 番号中の 1 で成功する。 | JSON を decode／parse し `schemaVersion` の値を完全一致で確認。旧 JSON の互換性 EX16 は残す。 |
| L20 | P1 | VI09・VP02 | **静的確認:** VI09 の [AsyncGate](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:199) は opened を読まない。start 後に await せず open し、後から wait すると再開しない。VP02 は固定 sleep 後の空文字だけで対象 callback の到着を証明しない。 | transcriber 到達／対象 callback 適用を明示的なイベントで待ち、終了・取消と Task の片付けまで確認する。VI09 が既に守る同期 busy guard は維持する。 |
| L24 | P1 | SH01 | **実測:** `MARKETING_VERSION` 2 行のうち先頭だけを更新する誤実装で両シナリオ成功。grep -q は 1 行の一致で足りる。 | 全該当行が新版で旧版が残らないこと、`CURRENT_PROJECT_VERSION` 等が不変なことを確認。対象を失っても通る fixture にしない。 |
| L04 | P2 | AF07・AF08・AF15・AF16 | **静的確認:** [DropURLParser](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/DropURLParser.swift:3) に本番呼出しなし。現在の [FileDropView](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/FileDropView.swift:212) は loadFileRepresentation の URL を受ける。 | parser の維持要否を本体と一緒に判断。残すべき保護は provider の型 fallback、callback 内のコピー、URL 有効期間、ViewModel への受渡し。旧 parser のテストだけを増やさない。 |
| L05 | P2 | AF09・AF10 | **静的確認:** [probeDecodability](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/AudioFileService.swift:56) は本番未使用。正例も data 長 0 の WAV header。 | 壊れた音声を利用者の入口でどう扱うかを試験する。metadata 検査とデコード可能性を同じ保証として数えない。未使用 helper の廃止時に一緒に削除可能。 |
| L09 | P2 | SA03・SA04 | **静的確認:** SA03 は無関係なファイル存在、SA04 は true のみを確認。[endAllAccess](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/SecurityScopedFileAccess.swift:34) は本番未使用。 | 有効な access の開始と終了回数、保存キャンセル／失敗時の解放を検証する。未使用一括解放を廃止する場合は SA04 も削除候補。 |
| L11 | P2 | PB01 | **静的確認:** 性能閾値なしの計測 probe。固定 `/opt/homebrew/bin/ffmpeg` と個人絶対パスに依存。`whisperKitModelName = large-v3-turbo` は [本番設定](/Users/fukutomiteppei/Documents/GitHub/Transnote/Config/Defaults.plist) の `large-v3-v20240930_turbo` と異なる。fixture が見つかるとモデル未配置／ffmpeg 不在で失敗し得る。 | 計測用の明示コマンドへ移す。モデル名は設定から取得し、入力・モデル・環境・RTF を記録する。現在のテストを性能退行の検出件数に含めない。 |
| L13 | P2 | UC08 | **静的確認:** [isValidRepository](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/UpdateCheckService.swift:127) は不一致 full_name で先に return。埋込み HTML URL の検証に到達しない。 | UC07 の repo 不一致と UC10 の field 欠落＋埋込み URL がそれぞれ担当。負例を失わず統合する。 |
| L14 | P2 | ER06・ER07 | **静的確認:** 汎用文言との非等値だけ。ネットワーク文言がキャンセル文言になっても成功する。 | アプリ bundle から取得したネットワーク用の期待文言と一致させる。ロケール依存を避けるために分類を弱めない。 |
| L16 | P2 | PD02 | **静的確認:** モデル名と `/` のみを確認。64／100 の分子・分母・単位の誤表示を検出しない。 | 既知の byte 値の表示、completed／total の取り違え、total 不明時の fallback を確認する。 |
| L17 | P2 | AF13 | **静的確認:** UTType の件数だけ。wav／mp3／m4a が同じ型に置換されても成功する。 | 期待する型の集合と不明拡張子の扱いを比較する。picker で許される形式という保護を残す。 |
| L18 | P2 | AP03・AP05・AP06 | **静的確認:** AP03 は開始待ち結果を無視。AP05 の callback は [ロード失敗](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/AudioPlayerService.swift:122) からも呼ばれる。AP06 は「後者」ではなく何かが再生されたことしか見ない。 | 開始と対象区間を確認してから停止／正常終了を観測。AP06 はより強い AP07 に統合し、新旧 callback の区別を残す。 |
| L19 | P2 | DI01 | **静的確認:** アプリの永続モデル root を使い cleanup なし。キャッシュがあれば downloadIfNeeded が早期 return し、実 DL を検査しない。 | 空一時 root の DI02、既存 path の MD01、実ロードの MP02 に役割を整理。既定ディレクトリ結線を残すなら別の軽い試験にする。 |
| L21 | P2 | UI01・UI02 | **静的確認:** [初期表示](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/TranscriptEditorView.swift:204) はモデル未取得時に別文言。UI01 は取得状態を用意しない。UI02 は menu の exists のみで、disabled や export 実行を見ない。 | locale・モデル状態・復旧状態・更新確認を固定し、空状態／取得済みの両条件を検証する。export は初期無効→結果後有効→保存内容までを接続する。 |
| L22 | P2 | JS04 | **実測:** TZ=America/Los_Angeles では 2026-01-15T00:00:00Z が 1 月 14 日となり失敗。現在の formatDate はローカル暦日を返す。 | ローカル暦日か UTC 固定日かを仕様として明示し、TZ と期待値を対応させる。現在の振る舞いを無断で UTC に変更しない。 |
| L23 | P2 | JS05・JS06 | **実測:** DMG／SHA selector をそれぞれ無条件 `assets[0]` にしても 6 件全部成功。正解が常に先頭。 | decoy を先頭にし、複数 DMG・別 DMG の checksum・該当なし・入力なしを置く。本番の選択規則を使った異常例で比較する。 |
| L25 | P2 | TM06 | **静的確認:** singleton の現在値を読むだけで、未知 ID からの復旧も保存の往復も誘発しない。開発端末の状態に依存する。 | 一時 UserDefaults／明示 config で valid・invalid・missing の入力を用意し、初期選択と persist を試験する。 |
| L26 | P2 | VI02 | **静的確認:** `Imports...WithPreferredFileName` という名前だが引数なしで、期待は任意エラーの non-nil。ファイル権限など無関係な失敗も同じ結果になる。 | 負例の名前に直し、unsupported 相当の分類／選択状態／前結果保持を観測。成功側 VI03 も残す。 |
| L27 | P2 | UC15 | **静的確認:** HTTP 500 の body が空。status 判定を削除しても JSON decode が失敗し、同じ nil になる。 | 200 なら有効な新版 JSON を 500 で返して拒否させる。transport error／壊れた JSON は独立した入力として扱う。 |
| L06 | P3 | AF12 | **静的確認:** [SupportedAudioTypes.isSupported](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Infrastructure/SupportedAudioTypes.swift:41) は本番未使用。resolveExtension／allowedContentTypes の利用と混同できない。 | helper の廃止・本番利用のどちらかを決める。実 validate の許可／拒否テストを残す。 |
| L07 | P3 | PR01 | **静的確認:** ログを出し `XCTAssertTrue(true)`。どの variant を誤解決しても回帰を報告しない。 | 手動診断へ移す。通常の選択規則は MA 群が実データ構造と期待パスで守る。 |
| L08 | P3 | TM02 | **静的確認:** `TranscriptSegment.id` は非 Optional UUID。assertNotNil は型が既に保証するだけで、衝突・固定値化は検出しない。 | ID の独立性や Codable での ID 保持が必要ならその契約へ置換。現在の assertion 自体は削除候補。 |
| L12 | P3 | AF01・EX09・EX14・MP01・PD05 | **静的確認:** それぞれ AF06、EX10、EX04、MA05、PD03 と同じ入力クラス・分岐を重ねている。MP01／MA05 は階層と assertion も同等。 | 同一ケースは統合、モデル名等が違う入力は表として残す。EX07 の本文と EX10 の期間は相補的なので両 assertion を残す。単に名前が似たテストをまとめて削除しない。 |

## 重複として削除すべきでない組合せ

| 組合せ | 異なる保護 |
| --- | --- |
| URL validator の UV 群と UpdateCheckService の UC 群 | 純粋な URL 判定と、JSON decode 後も実サービスがその判定を使う接続。UC08 の短絡だけが別問題。 |
| FN／AF の名前解決と AI／VI の import | 入力名の規則、実 FS コピー、ViewModel の状態反映という境界が異なる。偽音声を使っていても metadata 試験としては有用。 |
| TS／PT／VP | サニタイズ規則、ウィンドウ蓄積、非同期 UI 反映。PT の新旧比較が同じ sanitizer を使う弱点を TS の固定期待値が補う。 |
| TM01 と EX03 と EX16 | Codable の基本保存、ExportService の encoder 設定、固定 legacy JSON の後方互換性。往復成功だけでは legacy 互換性は守れない。 |
| MA の file／bundle・hidden・同点候補 | FS 種別と選択条件が別。合成 CoreML ファイルは検出器の単体試験には妥当で、実ロード保証は MP02。 |
| UC09 と UC13 | repository field の欠落と JSON null は wire format が異なる。入力表にはまとめられるが両方を残す。 |
| AP07 と UI03 | 実 AVPlayer の連打時 callback と、設定シートを閉じる実 UI 操作を守る。実時間依存・状態隔離を改善して維持する。 |

## 本番経路に残る重要な穴

テストが存在するファイル数を機能の保護範囲とみなさない。以下は優先対応と関連する未検証経路であり、コードで確認できる現象を併記した。

| ID | 本番経路と現状 | 既存テストが観測しないもの |
| --- | --- | --- |
| G01 | [MainWindowView の footer](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/MainWindowView.swift:205) と [メニュー結線](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/MainWindowView.swift:131) は cancelTranscription を渡す。[cancelModelDownload](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/MainWindowViewModel.swift:646) は別メソッド。 | DL 用ラベルになっても実 DL Task は停止されない接続を VP09 は検出しない。DL／文字起こしの取消、遅れて来る旧 callback、再実行、二重開始の一連の操作が未検証。 |
| G02 | [FileDropView.loadDropItem](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/FileDropView.swift:196) → import → main queue → selectFile。通常選択の [旧コピー削除](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/MainWindowViewModel.swift:494) は固定 AppDirectories root を参照。 | provider 型優先、表現 fallback、複数ファイル拒否、一時 URL の寿命、確認待ち中のコピー片付け、旧音声の保持／削除。VI の injected root は固定 root の削除分岐に入らない。 |
| G03 | [全文・segment 編集](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/MainWindowViewModel.swift:660) → [exportTranscript](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/MainWindowViewModel.swift:759) → save panel → write。 | 全文／segment／dirty 状態の同期、保存キャンセル、書込み失敗、bookmark 解放、最新版の書出し。現行 updateSegmentText は segment を変えても全文を再構築しない。この違いを EX 群は観測できない。 |
| G04 | [UpdateCheckService の取得](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/UpdateCheckService.swift:92) と [UpdateCheckViewModel](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Presentation/UpdateCheckViewModel.swift:17)。 | 6 時間制限、ETag／304、response 8 MB 境界、request URL／header、SHA asset 対応、manual check と起動時設定。毎テストで状態を消すため連続呼出しを守れない。現在 ETag は HTTP header でなく JSON の etag を保存している。 |
| G05 | [WhisperKitTranscriber](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/WhisperKitTranscriber.swift:48) の実 inference と chunk／checkpoint。 | 長音声の分割、後続 chunk の時刻補正、途中失敗の後始末、言語／VAD オプション、tokenizer fallback、モデル切替・再利用・取消。WT01 はモデル未取得だけ、SM01 は標準では skip、MP02 は SDK の直接ロードのみ。 |
| G06 | [モデル index](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/ModelAvailabilityService.swift:68) と DL／削除後の refresh。 | キャッシュを温めてからモデルを追加・削除する順序、TTL 境界、diskUsage、disk 不足、retry／cancel。現行の 30 秒 cache は追加直後の発見を遅らせ得る。MA 群は主に初回走査の状態で検証。 |
| G07 | [HistoryStore](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Services/HistoryStore.swift:25) と recovery／checkpoint。 | 複数履歴の降順・limit・検索・破損 JSON・metadata 保存、途中 checkpoint から復旧まで。saveTemporary は injected historyRoot を使わず固定 root へ書く。 |
| G08 | [サイトの 2 つの fetch と描画](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.js:175)。 | fetch 解決順が逆の場合の最新バッジ、失敗／不正応答／空一覧、DOM の href／文言／checksum、再描画。renderReleaseList を空にしても JS 全 6 件が実測で成功した。 |
| G09 | Release／Pages の生成・配布。 | shell の 2 件は版更新のみ。DMG 作成、archive export、install の更新／復元、checksum 不一致、SBOM の正しさ、設定生成の成功／失敗を直接守らない。配布 workflow の成功と製品動作のテストを区別する。 |
| G10 | [AppConfig.validationErrors](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriber/Domain/AppSettings.swift:167)、UserDefaults、OS access／再生。 | 必須設定欠損・不正 default ID、設定の保存復元、再生位置／pause・resume・無効区間・ロード失敗、実 security-scoped access の開始終了。既存 getter／初期状態テストだけでは覆えない。 |

G04 の HTTP 契約は [GitHub 公式の conditional requests](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests) で確認した。`etag` はレスポンスヘッダーから保存し、次の同一リソース要求に `If-None-Match` として送る仕様である。この仕様と、現行コードが `release.etag`（JSON field）を読む事実を根拠に、header を持つ fixture が必要と判断した。

## 実行設定と検証結果

| 経路 | 静的な選択件数 | 実行条件・制限 |
| --- | ---: | --- |
| [PR／main CI](/Users/fukutomiteppei/Documents/GitHub/Transnote/.github/workflows/ci.yml:169) | XCTest 195 | 198 単体から DI01・DI02・MP02 を除外。UI 3 件も除外。SM01／PB01 は選択されるが fixture により skip／外部依存実行が変わる。 |
| [Nightly](/Users/fukutomiteppei/Documents/GitHub/Transnote/.github/workflows/nightly.yml:38) | XCTest 3 | DI01・DI02・MP02 のみ。実文字起こし SM01 と UI は含まない。 |
| [Release](/Users/fukutomiteppei/Documents/GitHub/Transnote/.github/workflows/release.yml:64) | XCTest 198 | 実モデル 3 件のみ除外。UI 3 件はここでは選択される。scheme の TestAction は Debug で、Release archive 自体の UI テストではない。 |
| [site-js-tests](/Users/fukutomiteppei/Documents/GitHub/Transnote/.github/workflows/ci.yml:82) | JS 6＋shell 2 | JS ステップの cd site は次の run ステップに持ち越されないため、shell テストのパスは正常。 |
| [Pages](/Users/fukutomiteppei/Documents/GitHub/Transnote/.github/workflows/pages.yml:33) | 設定整合性 1 | 通常 PR CI にはこの --check がない。現 checkout は config markers 不在で失敗。 |

件数は**選択される件数**であり、今回通過した件数でも過去 CI の実績でもない。Xcode の現 PBXSourcesBuildPhase には Swift 全 26 ファイル（テスト helper 含む）が登録され、scheme に単体・UI の両 target がある。

| 今回の確認 | 結果 | 言えること・限界 |
| --- | --- | --- |
| `node site/app.test.js` | 6／6 成功 | Node 26.12.0、通常 TZ。CI の Node 20 とは異なる。 |
| `bash scripts/test-release-scripts.sh` | 2／2 成功 | 更新する project fixture はスクリプト内の一時ディレクトリ。実 project は不変。 |
| `python3 scripts/verify-readme-version.py` | 成功 | README と現 project は 0.1.5。README 内の全表記一致までの保証ではない。 |
| `python3 scripts/generate-site-config.py --check` | 失敗 | `site/app.js: config markers not found`。JS unit が緑でも Pages の整合性 gate は通らない。 |
| `TZ=America/Los_Angeles node site/app.test.js` | 日付 1 件失敗、他 5 件成功 | JS04 の TZ 依存を再現。プロダクトの日付仕様の良否を判定したものではない。 |
| DMG selector を assets[0] へ変更した一時コピー | 6／6 成功 | JS05 が誤選択を検出しない実例。 |
| SHA selector を assets[0] へ変更した一時コピー | 6／6 成功 | JS06 が誤選択を検出しない実例。 |
| renderReleaseList を空にした一時コピー | 6／6 成功 | JS helper tests には描画の保証がない。 |
| 版更新を全文中 1 か所だけにした一時コピー | 2／2 成功 | 旧版行が残ることも出力で確認。SH01 の弱さを実証。 |
| AI08 と同じ親未作成で Foundation.createFile を実行 | false、削除前 exists=false | fixture が最初から作成されていないことを再現。AI08 自体を実行した結果ではない。 |
| 全 target の `xcodebuild build-for-testing` | 成功、終了 0 | Xcode 26.6／Swift 6.3.3、project は Swift 5 言語モード。アプリと単体・UI のコンパイル確認。CI は Xcode 16.4。 |
| XCTest メソッド／UI の実行 | 今回は未実行 | 下記 C01 の実保存領域・共有設定・UI の復旧破棄を隔離していないため、既存データへ副作用を与える実行は行っていない。成功・失敗・skip の実測値は主張しない。 |

Mutation は狙いを定めた 4 パターンだけであり、スイート全体の mutation score ではない。上記誤実装はすべて一時コピーだけに適用した。元のテストや本番コードへは適用していない。

ビルドは当初 sandbox の Xcode cache 書込制限、次に既存 DerivedData の UI runner plist 書込エラーに当たった。既存ファイルの権限を変更せず、別の一時 DerivedData で成功を確認した。コンパイラ警告をテスト失敗として数えていない。

再実行可能なビルドコマンド（今回使用した依存 checkout は Package.resolved と同じ WhisperKit revision `e2adabbe7d98dc4d0ab9a5b75424ecc42a9cdbef`）:

```sh
xcodebuild build-for-testing \
  -project LocalTranscriber.xcodeproj \
  -scheme LocalTranscriber \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/transnote-test-audit.ARbswO/DerivedData \
  -clonedSourcePackagesDirPath /Users/fukutomiteppei/Documents/GitHub/Transnote/DerivedData/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -resultBundlePath /tmp/transnote-test-audit.ARbswO/build-fresh.xcresult
```

再実行時は出力先・result bundle を新しい一時パスにする。今回の [ビルドログ](/tmp/transnote-test-audit.ARbswO/build-fresh.log)、[ビルド結果](/tmp/transnote-test-audit.ARbswO/build-fresh.xcresult)、[mutation 結果](/tmp/transnote-test-audit.ARbswO/mutations.json) はローカル一時成果物であり、永続的な証跡は上表のコマンド・変更条件・結果とこの台帳である。

## 横断する信頼性の問題

| ID | 問題と根拠 | 対応方針 |
| --- | --- | --- |
| C01 | VI／VP の AppSettings.shared と settings.persist、UC の UserDefaults.standard の時刻・ETag 削除、SA02 の既存 bookmark 削除、VP01〜03 の default HistoryStore と recovery 書込み、DI01 の永続モデル、UI03 の復旧データ破棄。 | 共有値の保存復元または isolated defaults／保存 root を使う。HistoryStore に historyRoot を渡すだけでは saveTemporary の固定 root を隔離できない。App 起動時の Imports cleanup と UI の更新確認も制御する。 |
| C02 | VP07・VP14・VP15、PD03・PD05・PD06、UI の文字列探索は日本語に依存する一方、他の箇所では L()／NSLocalizedString を使用。UI01 はモデル取得状態にも依存。 | 日本語表示のテストなら起動 locale と状態を固定し、ロジック試験では適切な bundle の翻訳や構造的な状態を比較。文言一致を無意味な non-nil に弱めない。 |
| C03 | VI09 の gate 未解放、VP01 の短い表示窓、VP02 の未同期 sleep、AP の実時間待ちと捨てた待機結果。setup の createFile 戻り値を確認しない箇所も多い。 | 操作開始／callback 適用／終了を明示的な expectation で同期し、tearDown で Task を止める。fixture の作成と削除前の存在を検証する。 |
| C04 | MockURLProtocol の static handler は reset だけで session.invalidateAndCancel なし。WT01 の音声ファイル名は固定。scheme は random 順序。 | 同一プロセスでの並行化や中断後の残存に備え、session とファイルをケース単位にする。現構成で常に race が起きると断定するものではない。 |


## 全テスト台帳

各行は 1 つのテストメソッド／シナリオに対応する。ループ内の入力はケース数を水増ししない。「維持」も網羅的保証ではなく、現在検証している契約に価値があるという判断。各節の本番経路は、個別の未使用・迂回の注記がある行を除いて共通する。全項目は未対応であり、この監査ではテストを変更・削除していない。

### AppVersionTests

対象: [AppVersionTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift)（11 件）。

更新確認 → AppVersion.normalize / compare / isNewer。実際の比較関数を呼ぶ。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| AV01 | [testCompareReturnsSameForEqualVersions](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:8) | 同版と v 接頭辞付き同版が等しい | **維持**。等値判定を固定。新版／旧版の判定とは別の境界。 |
| AV02 | [testCompareOrdersSemanticVersions](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:16) | 新旧の両方向と 0.10 > 0.9 の数値順 | **維持**。文字列辞書順への退行を検出。 |
| AV03 | [testNormalizeStripsVersionPrefix](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:25) | v / V 接頭辞の除去 | **維持**。比較だけでなく表示用 normalize の契約。 |
| AV04 | [testIsNewerDetectsAvailableUpdate](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:33) | 新版だけ true、同版・旧版 false、安定版優先 | **維持**。compare の結果を Bool に変換する接続を守る。 |
| AV05 | [testCompareOrdersStableVersionsAfterPrereleases](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:43) | 安定版が alpha / beta / rc より後 | **維持**。prerelease 不在の分岐。両方向も確認。 |
| AV06 | [testCompareOrdersPrereleases](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:53) | prerelease の文字・数値・混在順 | **維持**。各比較規則の違いがあるため単純重複ではない。 |
| AV07 | [testCompareAfterNormalizingPrefixedPrerelease](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:63) | v 接頭辞付き prerelease の比較 | **維持**。正規化と prerelease 解析の組合せ。 |
| AV08 | [testCompareIgnoresBuildMetadata](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:71) | build metadata が比較を変えない | **維持**。core 比較だけでは守れない仕様。 |
| AV09 | [testCompareWithBothPrereleaseAndBuildMetadata](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:79) | prerelease と build metadata の同時指定 | **維持**。分割順の誤りを検出する組合せ。 |
| AV10 | [testCompareDoesNotOverflowLargeCoreNumbers](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:87) | Int 上限を超える core 数値の順序と等値 | **維持**。桁あふれで 0 に落ちる回帰を防ぐ。 |
| AV11 | [testCompareTreatsSignedPrereleaseIdentifierAsNonNumeric](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AppVersionTests.swift:105) | -1 風識別子を非数値として扱う | **維持**。ASCII 数字判定の境界。正負の順序を確認。 |

### AudioFileNameResolverTests

対象: [AudioFileNameResolverTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileNameResolverTests.swift)（6 件）。

ファイル選択／ドロップ → AudioFileNameResolver → AudioImportService。ファイル名処理だけを検証。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| FN01 | [testSanitizeFileNameAcceptsNormalName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileNameResolverTests.swift:21) | 通常のファイル名を変更しない | **維持**。sanitize の正例。実ファイルのデコード保証ではない。 |
| FN02 | [testSanitizeFileNameNormalizesSubpath](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileNameResolverTests.swift:25) | 通常のサブパスから末尾名を取り出す | **維持**。拒否すべき traversal と区別した許容例。 |
| FN03 | [testSanitizeFileNameRejectsPathTraversal](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileNameResolverTests.swift:29) | ../、単独 . / .. を拒否する | **維持**。出力先を逸脱させない境界。Windows 風区切り等は未検証。 |
| FN04 | [testIsUsableFileNameRejectsUnsupportedExtension](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileNameResolverTests.swift:35) | 許可外拡張子を使える名前と判定しない | **維持**。resolve 内で利用される predicate の負例。 |
| FN05 | [testResolveRejectsTraversalPreferredFileNameAndFallsBack](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileNameResolverTests.swift:40) | 危険な preferredFileName を拒否して source に戻る | **維持**。sanitize と優先順位の接続。4 バイト MP3 断片はデコード用 fixture ではない。 |
| FN06 | [testResolveAcceptsNormalPreferredFileName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileNameResolverTests.swift:56) | 有効な preferredFileName を元名より優先する | **維持**。source.wav と recording.wav を区別し優先順位を確認。 |

### AudioFileServiceTests

対象: [AudioFileServiceTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift)（16 件）。

AudioFileService.validate は選択／インポート後のメタデータ検査。名前解決は FileDropView、型一覧は picker で使用。未使用 API は各行に明記。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| AF01 | [testValidateAcceptsM4AExtension](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:19) | m4a の拡張子を受理する | **統合**。L12。AF06 が同じ条件に fileName の確認も加えている。 |
| AF02 | [testValidateRejectsExtensionlessTempFileLikeDrop](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:28) | 拡張子も型情報もないファイルを unknown として拒否 | **維持**。AppError の種類と引数まで確認。偽音声はこのメタデータ境界には妥当。 |
| AF03 | [testDropFileNameResolverUsesSuggestedNameForExtensionlessTemp](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:40) | 拡張子なしの一時名より suggestedName を優先 | **維持**。本番 DropFileNameResolver を通す。単純 resolver 試験と接続箇所が異なる。 |
| AF04 | [testDropFileNameResolverIgnoresPlaceholderSuggestedName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:52) | placeholder の suggestedName を捨て UTI に戻る | **維持**。suggestedName が nil の AF05 と別の分岐。 |
| AF05 | [testDropFileNameResolverInfersM4AFromTypeIdentifier](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:64) | suggestedName がない場合に UTI から m4a を推定 | **維持**。本番のドロップ名決定で使用。 |
| AF06 | [testValidateAcceptsResolvedDropFileName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:76) | recording.m4a の拡張子と名前を返す | **維持**。名前と異なり resolver 自体は呼ばない。AF01 の統合先。 |
| AF07 | [testDropURLParserReadsDataRepresentation](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:86) | Data 表現を URL に戻す | **削除候補**。L04。DropURLParser に本番の呼び出し元がない。 |
| AF08 | [testDropURLParserReadsURLObject](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:95) | URL オブジェクトをそのまま受理する | **削除候補**。L04。現在の FileDropView は loadFileRepresentation を使う。 |
| AF09 | [testProbeDecodabilityReturnsTrueForRealWAV](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:103) | WAV ヘッダーを AVFoundation のプローブが受理 | **削除候補**。L05。probeDecodability は本番未使用。データ部 0 バイトで実デコードも未確認。 |
| AF10 | [testProbeDecodabilityReturnsFalseForGarbage](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:125) | garbage をプローブが拒否する | **削除候補**。L05。本番 validate／import はこのプローブを呼ばない。 |
| AF11 | [testSupportedAudioTypesResolveExtension](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:134) | 拡張子取得・小文字化・拡張子なし nil | **維持**。validate から使われる resolveExtension の分岐。 |
| AF12 | [testSupportedAudioTypesIsSupported](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:140) | wav を許容、mov を拒否する | **削除候補**。L06。SupportedAudioTypes.isSupported は本番未使用。validate とは別実装。 |
| AF13 | [testSupportedAudioTypesAllowedContentTypes](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:146) | picker 向け型一覧の件数が 3 | **改善**。L17。同じ UTType を 3 個返す誤実装でも通る。型の集合を比較する。 |
| AF14 | [testDropImportServiceHasSupportedExtension](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:151) | ドロップ名の許可／不許可拡張子を区別 | **維持**。FileDropView と ViewModel の本番分岐で使われる。 |
| AF15 | [testDropURLParserReadsStringFileURL](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:156) | file URL 文字列をパースする | **削除候補**。L04。旧入力表現のヘルパーのみを検証。 |
| AF16 | [testDropURLParserReturnsNilForUnknownType](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioFileServiceTests.swift:161) | NSNumber を URL と解釈しない | **削除候補**。L04。本番が通らない型拒否。 |

### AudioImportServiceTests

対象: [AudioImportServiceTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift)（13 件）。

AudioImportService.importFile は picker／drop 共通。実 FS を一時 root に隔離。失敗注入には PartialCopyThenFailFileManager を使用。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| AI01 | [testImportFileCopiesIntoSandboxDirectory](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:18) | sandbox コピーの返却先と実在 | **維持**。実 importFile を通る。内容一致も確認すると空コピーを検出できる。 |
| AI02 | [testImportFileSkipsCopyWhenAlreadyInImportsDirectory](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:33) | Imports 内の既存ファイルを再コピーしない | **維持**。同じ URL が返ることを確認。兄弟 prefix／symlink 境界は未検証。 |
| AI03 | [testImportFileUsesPreferredFileNameWhenSourceNameIsPlaceholder](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:43) | placeholder を preferredFileName に置換してコピー | **維持**。ファイル名と拡張子と実在を確認。 |
| AI04 | [testImportFileInfersM4AExtensionFromContentTypeForPlaceholderName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:59) | 拡張子なし M4A ヘッダーから保存名を決定 | **維持**。推定器とコピーの接続。音声デコードのテストではない。 |
| AI05 | [testImportFileThrowsWhenFileExceedsSizeLimit](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:79) | サイズ上限 10 に対し 11 バイトを fileTooLarge で拒否 | **維持**。正確な境界。最終ファイルの不在は確認するが隠し一時ファイルは未確認。 |
| AI06 | [testImportFileSucceedsWhenFileWithinSizeLimit](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:99) | 上限ちょうど 10 バイトを許容 | **維持**。超過拒否と対になる境界値。 |
| AI07 | [testValidateAcceptsExtensionFromPreferredFileName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:116) | preferredFileName 由来の拡張子で validate が成功 | **維持**。実際の対象は AudioFileService。元ファイル名を保持する仕様も確認。 |
| AI08 | [testRemoveFileIfExistsIfFailedDeletesZeroByteFile](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:134) | 失敗時に 0 バイトファイルを削除する意図 | **置換**。L02。親 root 未作成で createFile が false。呼び出し前からファイルが存在しない。 |
| AI09 | [testRemoveFileIfExistsIfFailedIsNoOpForMissingFile](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:143) | 存在しないパスの削除が無害 | **統合**。L02。削除ヘルパーを空実装にしても通る。AI08 修正後の再削除にまとめる。 |
| AI10 | [testImportFileRemovesPartialFileWhenCopyItemFailsAndStreamingIsSkipped](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:152) | copy 失敗後の部分ファイルを消す意図 | **置換**。L03。確認するのは最終名だけ。現在残り得る .tmp UUID ファイルを観測しない。 |
| AI11 | [testImportFileFallsBackToStreamingWhenCopyItemFails](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:185) | copyItem 失敗から streaming コピーへ復帰 | **維持**。実ファイルのバイト一致がある。通常コピーの試験とは別経路。 |
| AI12 | [testCleanupExpiredImportsRemovesOldFilesAndKeepsRecentOnes](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:211) | 古い import を消し最近のファイルを保持 | **維持**。本番起動時 cleanup を通す。隠し .tmp ファイルと期限ちょうどは対象外。 |
| AI13 | [testCleanupExpiredImportsIsNoOpWhenImportsRootMissing](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:228) | root が存在しなくても cleanup が失敗しない | **維持**。公開 cleanup の欠損ディレクトリ入力。AI09 とは対象メソッドが異なる。 |

### AudioPlayerServiceTests

対象: [AudioPlayerServiceTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift)（7 件）。

本番 AVPlayer を合成した無音 WAV で使用。ViewModel.playSegment／stopPlayback が呼び出すサービス。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| AP01 | [testLoadSetsLoadedURL](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:23) | load 後の URL と非再生・observer なし | **維持**。実ロード API の初期状態を確認。 |
| AP02 | [testPlaySegmentSetsTimeObserver](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:30) | playSegment 後に observer が付く | **維持**。AVPlayer の非同期開始を待つ。実際の再生位置は未確認。 |
| AP03 | [testStopClearsPlaybackState](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:40) | stop が player・再生状態・observer を消す | **改善**。L18。開始待ちの結果を捨てるため、再生開始前の stop でも成功し得る。 |
| AP04 | [testStopPlaybackClearsViewModelPlayingSegmentID](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:55) | ViewModel.stopPlayback が選択セグメント ID を消す | **維持**。手動設定状態の表示リセット。実再生停止は AP03 の担当。 |
| AP05 | [testOnSegmentFinishedCallbackFires](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:65) | 終了 callback と停止状態 | **改善**。L18。AVPlayerItem.failed も同じ完了経路。正常再生開始／経過を確認していない。 |
| AP06 | [testConsecutivePlaySegmentStartsLatestSegment](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:84) | 連打後に何らかの再生が始まる | **統合**。L18。後者の区間かは判定できない。AP07 に開始検証を統合。 |
| AP07 | [testConsecutivePlaySegmentFiresFinishCallbackOnlyForLatestSegment](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:101) | 古い callback を捨て新しいセグメントだけ完了 | **維持**。連打回帰の中心。200 ms の実時間待ちがあり、制御可能なイベント待ちへの改善余地。 |

### ErrorMapperTests

対象: [ErrorMapperTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift)（10 件）。

各サービスの失敗 → ViewModel.handleError → ErrorMapper／AppError.errorDescription。L() はアプリ bundle の翻訳を取得。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| ER01 | [testUnknownErrorReturnsGenericMessage](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:14) | 未知エラーを汎用文言にし内部情報を隠す | **維持**。完全一致と秘密文言の不在で検証。 |
| ER02 | [testModelNotDownloadedErrorMentionsToolbarButtonLabel](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:27) | 未取得モデルの案内に実際のボタン名を使う | **維持**。利用者が復旧操作を見つけられる契約。 |
| ER03 | [testTranscriptionFailedWithReasonErrorDescriptionUsesUserMessage](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:34) | 原因付き文字起こしエラーを原因の表示分類へ渡す | **維持**。ラッパーの委譲を確認。分類自体の正しさは ER06 等で別途補強。 |
| ER04 | [testExportFailedWithReasonErrorDescriptionUsesUserMessage](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:47) | 原因付き export エラーに接頭辞を付ける | **維持**。エラー分類を再利用する委譲契約であり、同一実装比較だけの空試験ではない。 |
| ER05 | [testTranscriptionFailedWithReasonIsEquatable](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:66) | 同じ原因の等値と異なる原因／case の非等値 | **維持**。Error を含む手書き Equatable の分岐。 |
| ER06 | [testURLErrorNotConnectedToInternetClassifiedAsNetwork](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:77) | offline の URLError をネットワーク文言にする意図 | **改善**。L14。汎用文言と違うことしか見ない。任意の別文言でも成功。 |
| ER07 | [testURLErrorNetworkConnectionLostClassifiedAsNetwork](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:84) | connectionLost をネットワーク文言にする意図 | **改善**。L14。キャンセル等への誤分類も検出できない。 |
| ER08 | [testURLErrorCancelledClassifiedAsCancelled](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:91) | URLError.cancelled を CancellationError と同じ分類にする | **維持**。ネットワーク分類との非等値も確認。 |
| ER09 | [testErrorContainingNetworkKeywordIsNotClassifiedAsNetwork](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:98) | network という単語だけの未知エラーを誤分類しない | **維持**。部分文字列一致への退行を防ぐ負例。 |
| ER10 | [testOfflineKeywordIsNoLongerClassifiedAsNetwork](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ErrorMapperTests.swift:110) | offline という単語だけの未知エラーを誤分類しない | **維持**。旧キーワード判定の別の負例。入力表への集約は可能だが意味は残す。 |

### ExportServiceTests

対象: [ExportServiceTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift)（18 件）。

ViewModel.exportTranscript → ExportService.write → content。ここでは content／JSON decode まで。保存パネル、書込み、編集反映は通らない。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| EX01 | [testTXTExportReturnsFullTextOnly](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:19) | TXT が全文のみを返す | **維持**。完全一致でヘッダー混入も検出。 |
| EX02 | [testMarkdownExportIncludesHeaderAndSegments](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:24) | Markdown の見出し・全文・区間を含める | **維持**。含有検査。順序や余計な出力は未検証。 |
| EX03 | [testJSONExportIsValidAndRoundTrips](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:33) | JSON が Transcript として読め本文等を保持 | **維持**。Model 層 TM01 と異なり export の encoder 設定を通す。metadata は未確認。 |
| EX04 | [testSRTExportFormat](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:44) | SRT の番号・区間・文字列の形式 | **維持**。EX14 の弱い正常系を吸収できる。 |
| EX05 | [testVTTExportFormat](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:50) | VTT のヘッダーと時刻・文字列 | **維持**。SRT と出力形式が異なるため重複ではない。 |
| EX06 | [testSRTHandlesSpecialCharacters](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:57) | SRT でタグ・引用符・ampersand を保持 | **維持**。文字を過剰に消さない出力契約。 |
| EX07 | [testExportWithEmptySegmentsUsesFullText](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:69) | セグメントなしでも SRT／VTT に全文を出す | **維持**。EX10 と同一 fixture にまとめても、この本文 assertion は残す。 |
| EX08 | [testTimestampPrecision](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:81) | ミリ秒を字幕時刻に反映 | **維持**。分・時の繰上がりや丸め境界は未検証。 |
| EX09 | [testExportWithEmptySegmentsDoesNotUseZeroDuration](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:93) | 空セグメントの字幕がゼロ長にならない | **統合**。L12。同じ fixture の EX10 が 0→1 秒を明示的に要求する。 |
| EX10 | [testExportWithEmptySegmentsUsesMinimalDuration](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:105) | 空セグメントに 0→1 秒の代替区間を作る | **維持**。EX09 の統合先。本文確認は EX07 と相補的。 |
| EX11 | [testExportRejectsSegmentWithStartAfterEnd](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:116) | start > end を拒否 | **維持**。本番の validateSegments を通る。AppError の種類は未確認。 |
| EX12 | [testExportRejectsOverlappingSegments](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:125) | 重なる区間を拒否 | **維持**。単一区間の時刻検証とは別の連続性規則。 |
| EX13 | [testExportRejectsNegativeStartTime](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:137) | 負の start を拒否 | **維持**。VTT を入口に検証。NaN／無限大／ゼロ長は未検証。 |
| EX14 | [testExportAcceptsValidSegments](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:146) | 隣接する正しい区間が throw しない | **統合**。L12。EX04 が同じ有効区間構造を通り出力も検証。 |
| EX15 | [testJSONExportIncludesSchemaVersion](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:160) | JSON に schemaVersion 1 を出す意図 | **改善**。L15。キー文字列と任意の 1 を別々に検索。値が 999 でも他の時刻等に 1 があれば成功。 |
| EX16 | [testJSONDecodeWithoutSchemaVersionUsesDefault](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:166) | 旧 JSON に schemaVersion がなくても読む | **維持**。固定 legacy fixture を使うため往復テストとは異なる互換性保証。 |
| EX17 | [testMarkdownEscapesSpecialCharactersInFileName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:186) | Markdown のファイル名を escape | **維持**。見出し内の bracket／# を検証。 |
| EX18 | [testMarkdownEscapesSpecialCharactersInSegmentText](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ExportServiceTests.swift:196) | Markdown の segment.text を escape | **維持**。本文 fullText は非 escape のため、別フィールドを守る。 |

### MainWindowViewModelImportTests

対象: [MainWindowViewModelImportTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift)（9 件）。

実 ViewModel.selectFile → AudioImportService → validate。importsRoot は一時ディレクトリ。UI の NSItemProvider callback は経由しない。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| VI01 | [testSelectFileImportsExtensionlessM4APlaceholderName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:28) | 拡張子なし M4A の選択が sandbox 内の選択状態になる | **維持**。サービス単体と異なり error／selectedFile の結線を検証。 |
| VI02 | [testSelectFileImportsPlaceholderDropNameWithPreferredFileName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:47) | 推定できない placeholder 選択でエラーを出す | **改善**。L26。名前は preferredFileName 付き成功を示すが実際には未指定の負例。エラーの種類も未確認。 |
| VI03 | [testSelectFileImportsPlaceholderDropNameWithDropPreferredFileName](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:56) | ドロップから渡された preferredFileName を適用 | **維持**。VI02 の負例と対になる成功経路。 |
| VI04 | [testSelectFileImportsPlaceholderDropNameWithM4AContent](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:67) | file URL という placeholder でも内容から M4A を推定 | **維持**。VI01 と placeholder の分岐が異なる。入力表化は可能。 |
| VI05 | [testSelectFileAppliesImmediatelyWhenThereIsNoExistingResult](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:91) | 旧結果がなければ確認待ちなしで取り込む | **維持**。confirmFileImport／pendingFileImport も観測。名前推定テストだけでは代替不可。 |
| VI06 | [testSelectFileAwaitsConfirmationWhenAnExistingResultIsPresent](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:107) | 旧結果があればファイルと結果を維持して確認待ち | **維持**。旧 selectedFile は nil。実際の旧ファイル保持までの証明ではない。 |
| VI07 | [testApplyPendingFileImportReplacesResultAfterConfirmation](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:128) | 確認承認で前回結果を消して新ファイルへ切替 | **維持**。実 UI 確認ボタンの呼び出し先を直接実行。 |
| VI08 | [testCancelPendingFileImportKeepsExistingResult](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:148) | 確認キャンセルで旧結果を維持 | **維持**。旧 selectedFile が nil の fixture。旧 sandbox コピーの保持は未検証。 |
| VI09 | [testFileSelectionIsIgnoredWhileTranscriptionIsRunning](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:171) | 文字起こし busy 中はファイル選択を無視 | **改善**。L20。同期 guard は確認できるが、open が wait より先で AsyncGate が未解放になり得る。完了待ちもない。 |

### MainWindowViewModelProgressTests

対象: [MainWindowViewModelProgressTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift)（17 件）。

実 ViewModel と MockProgressTranscriber。AVPlayer／HistoryStore／AppSettings はデフォルト実装。setter 直接設定や専用 simulate helper は状態遷移を代替しない。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| VP01 | [testPartialTextUpdatesDuringTranscription](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:19) | 2 回の途中結果から最終結果へ更新し途中 export を禁止 | **維持**。実 ViewModel の非同期 callback 結線を確認。50 ms 表示窓と共有保存先には C01／C03 の問題。 |
| VP02 | [testPartialTextWithOnlySpecialTokenArtifactsDoesNotUpdateTranscript](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:49) | 特殊トークンだけの途中結果を表示しない | **改善**。L20。100 ms sleep までに該当 callback が届いたという同期がなく、未到着でも空のままで通る。 |
| VP03 | [testStartTranscriptionClearsPreviousResult](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:68) | 文字起こし開始直後に旧結果を消す | **維持**。開始時リセットと最終結果を両方観測。 |
| VP04 | [testModelDownloadButtonIsShownForModelThatIsNotDownloaded](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:95) | モデル未取得なら DL ボタンを表示し実行可能 | **維持**。ダウンロード可否の表示契約。モデル一覧は AppSettings.shared。 |
| VP05 | [testModelDownloadButtonIsHiddenForDownloadedModel](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:104) | モデル取得済みなら DL ボタンを隠し実行不可 | **維持**。未取得とは別の表示分岐。 |
| VP06 | [testModelDownloadButtonRemainsShownButCannotRunWhileDownloading](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:113) | DL 中もボタンを表示するが再実行不可 | **維持**。simulate helper による predicate テスト。実 downloadSelectedModel の多重実行は未検証。 |
| VP07 | [testModelDownloadGuidanceIsShownForModelThatIsNotDownloaded](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:123) | 未取得モデルの案内を表示 | **維持**。日本語部分文字列に固定。翻訳を切替えた環境での実行は未保証。 |
| VP08 | [testModelDownloadGuidanceIsHiddenForDownloadedModel](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:132) | 取得済みモデルの案内を隠す | **維持**。ボタン可視性と別の出力を確認。 |
| VP09 | [testCancelActionLabelsSwitchForModelDownload](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:140) | DL 中のキャンセルラベルと help を切替 | **維持**。表示契約は有用。ただし実ボタンの cancelModelDownload 呼出しは守らない。G01。 |
| VP10 | [testCancelActionLabelsStayOnTranscriptionDuringTranscription](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:156) | 文字起こし用キャンセル文言を表示 | **維持**。uiState の直接代入で実ジョブなし。取消処理をテストしたものではない。 |
| VP11 | [testCanCopyTranscriptRequiresNonEmptyResult](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:173) | 結果なしで copy 不可、非空結果なら可 | **維持**。空白のみ／結果なし途中テキストの copy は未検証。 |
| VP12 | [testRecoverableModelNotDownloadedErrorUsesInlineBannerOnly](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:182) | モデル未取得で critical alert ではなく inline 案内 | **維持**。実 startTranscription のエラー分岐と UI 状態を観測。 |
| VP13 | [testStartTranscriptionDisabledReasonTracksBlockingCondition](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:205) | ファイル未選択時の開始不可理由と選択後の許可 | **維持**。名前にある blocking condition 全般ではなく 2 状態のみ。 |
| VP14 | [testModelDownloadSuccessToastMessageWhenFileIsSelected](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:228) | ファイルありの DL 完了トーストが次の操作を案内 | **維持**。文言関数のみ。実 DL 完了時の toast 発行は未検証、ロケール依存。 |
| VP15 | [testModelDownloadSuccessToastMessageWhenNoFileIsSelected](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:242) | ファイルなしの DL 完了トーストが選択を案内 | **維持**。別の文言分岐。実 DL 完了は未検証、ロケール依存。 |
| VP16 | [testHasPlayableSegmentsReturnsFalseForEmptySegments](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:249) | segment なしなら再生可能と扱わない | **維持**。結果の編集／再生モード選択から使われる predicate。 |
| VP17 | [testHasPlayableSegmentsReturnsTrueWhenSegmentTextExists](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:255) | 非空 segment があれば再生可能と扱う | **維持**。空白のみ／複数の混在は未検証。 |

### ModelAvailabilityPathTests

対象: [ModelAvailabilityPathTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityPathTests.swift)（2 件）。

ModelAvailabilityService の検出パスと WhisperKit の実ロードを検証。MP02 は Nightly のみ。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| MP01 | [testModelFolderPointsToVariantDirectoryNotParentHubFolder](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityPathTests.swift:6) | hub 親ではなくモデル variant 自体を返す | **統合**。L12。MA05 と同じ階層・ファイル・assertion。MA05 に一本化可能。 |
| MP02 | [testWhisperKitLoadsFromDetectedModelFolder](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityPathTests.swift:27) | 実ダウンロードの検出パスで WhisperKit がロードできる | **維持**。外部 SDK と検出器の接続を守る。アプリの WhisperKitTranscriber 自体は通らない。 |

### ModelAvailabilityServiceTests

対象: [ModelAvailabilityServiceTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift)（16 件）。

ViewModel.refreshModelAvailability／WhisperKitTranscriber.prepareWhisperKit／ModelDownloadService から使う検出器。合成 FS で選択規則を隔離。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| MA01 | [testIsDownloadedReturnsFalseWhenDirectoryMissing](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:21) | 空 root にモデルなしと判定 | **維持**。名前は DirectoryMissing だが setUp で root は存在。root 自体の欠損分岐ではない。 |
| MA02 | [testIsDownloadedReturnsFalseWhenVariantPathMissing](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:30) | 必須ファイルのない variant を拒否 | **維持**。variant は存在する。欠けた required model の判定。 |
| MA03 | [testIsDownloadedReturnsTrueWhenRequiredModelsExist](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:42) | 必須 3 ファイルが非空なら存在を認める | **維持**。合成の通常ファイル。CoreML が読める保証は MP02 の役割。 |
| MA04 | [testIsDownloadedReturnsFalseWhenRequiredModelFileIsZeroBytes](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:59) | 必須ファイルが 0 バイトなら拒否 | **維持**。不完全ダウンロード判定。1 個だけ欠損／空のケースは未検証。 |
| MA05 | [testModelFolderIgnoresParentWhenModelsAreOnlyInChildDirectory](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:76) | 親でなく直下に必要ファイルを持つ子を選ぶ | **維持**。MP01 と実質重複。こちらを残す候補。 |
| MA06 | [testShortVariantNameDoesNotMatchUnrelatedDirectory](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:93) | database を base と誤認しない | **維持**。部分文字列一致への退行を防ぐ。 |
| MA07 | [testShortVariantNameDoesNotMatchSuffixWithoutHyphen](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:110) | itiny を tiny の suffix と誤認しない | **維持**。ハイフンの境界を守る。MA06 と異なる末尾一致ケース。 |
| MA08 | [testModelFolderPrefersNewerModificationDateOnEqualScores](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:152) | 同スコアなら新しい更新日時を優先 | **維持**。列挙順に依存しない選択。 |
| MA09 | [testModelFolderPrefersLexicographicallyOrderedNameOnEqualModificationDate](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:165) | 同スコア・同日時なら名前順 | **維持**。更新日時の試験だけでは守れない tie break。 |
| MA10 | [testModelFolderPrefersHigherScoreFolder](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:179) | 完全一致を新しい suffix 一致より優先 | **維持**。スコアと日時の優先順位。 |
| MA11 | [testExactVariantMatchBeatsOpenAIWhisperPrefixMatch](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:192) | 完全一致を openai_whisper prefix より優先 | **維持**。prefix 用 90 点と完全一致の境界。 |
| MA12 | [testModelFolderIgnoresHiddenCacheDirectory](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:205) | 新しい hidden cache より正規モデルを使う | **維持**。ステージングを誤ロードしない分離。 |
| MA13 | [testVariantDirectoriesExcludesHiddenByDefaultAndIncludesWhenRequested](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:224) | 通常列挙は hidden を除外し指定時だけ含める | **維持**。選択と失敗掃除に必要な API の違い。掃除の本番結線は L01。 |
| MA14 | [testModelFolderBreaksIdenticalNameTiesUsingFullPath](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:240) | 同名・同日時ならフルパスで安定選択 | **維持**。再現性のための最終 tie break。 |
| MA15 | [testIsDownloadedReturnsFalseWhenRequiredModelBundleDirectoryIsEmpty](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:256) | 空の mlmodelc bundle を拒否 | **維持**。通常ファイルの 0 バイトとは異なる FS 種別。 |
| MA16 | [testIsDownloadedReturnsTrueWhenRequiredModelBundleDirectoryHasContents](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelAvailabilityServiceTests.swift:273) | coremldata.bin を持つ bundle を認める | **維持**。payload は 5 バイトのダミー。構造判定を守る試験でありモデル整合性全体の保証ではない。 |

### ModelDownloadIntegrationTests

対象: [ModelDownloadIntegrationTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadIntegrationTests.swift)（2 件）。

Nightly で実 ModelDownloadService を使用。DI01 はアプリのモデル領域、DI02 は空の一時 root。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| DI01 | [testDownloadTinyModelToAppModelsDirectory](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadIntegrationTests.swift:6) | アプリモデル領域で tiny が利用可能になる | **統合**。L19。既存キャッシュ時は DL 不実行。保存領域を汚し、DI02／MD01 に対する増分が小さい。 |
| DI02 | [testDownloadTinyModelFromHub](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadIntegrationTests.swift:21) | 空 root へ tiny を Hub から取得して検出 | **維持**。本番 downloader を通る実通信。別インスタンスの availability で確認するため DL 前の cache の更新は未検証。実ロードは MP02。 |

### ModelDownloadServiceTests

対象: [ModelDownloadServiceTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadServiceTests.swift)（4 件）。

downloadIfNeeded の既存モデル経路と cleanup helper。失敗ダウンロード自体は起こさない。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| MD01 | [testDownloadIfNeededReturnsExistingPathWithoutNetwork](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadServiceTests.swift:24) | 既存モデルのパスを返す | **維持**。パスと存在判定を確認。ネットワーク呼出回数の spy はなく、WithoutNetwork は直接証明していない。 |
| MD02 | [testCleanUpFailedDownloadRemovesNewlyCreatedVariantFolderOnly](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadServiceTests.swift:45) | 新規 partial だけを削除し既存モデルを残す | **置換**。L01。単体の削除規則は有用だが download の失敗経路から helper が呼ばれていない。 |
| MD03 | [testCleanUpFailedDownloadRemovesNewlyCreatedHiddenStagingFolder](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadServiceTests.swift:87) | 新規 hidden staging を削除する | **置換**。L01。helper 直接呼び出しのため、本番で残骸が残っても成功。 |
| MD04 | [testCleanUpFailedDownloadPreservesHiddenStagingFolderThatExistedBeforeDownload](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelDownloadServiceTests.swift:115) | 事前にあった hidden staging を維持する | **置換**。L01。失敗注入を公開入口へ追加して本番との接続を守る必要。 |

### ModelResolveProbeTests

対象: [ModelResolveProbeTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelResolveProbeTests.swift)（1 件）。

実モデル領域を走査する調査用コード。通常 CI に含まれる。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| PR01 | [testProbeModelFolders](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/ModelResolveProbeTests.swift:8) | モデル解決結果をログに出す | **診断へ移動**。L07。assertion は true のみ。nil／誤ったモデルを返しても失敗しない。 |

### PerformanceBaselineTests

対象: [PerformanceBaselineTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/PerformanceBaselineTests.swift)（1 件）。

通常 CI／Release の選択対象。WhisperKit の fixture、固定 ffmpeg パス、ローカルモデルに依存。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| PB01 | [testBaselineTranscriptionSpeed](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/PerformanceBaselineTests.swift:33) | 合成長音声の処理秒数を print し全文が非空 | **診断へ移動**。L11。性能の合否基準なし。端末固定パスと本番と異なる model 名。通常回帰テストから分離。 |

### SecurityScopedFileAccessTests

対象: [SecurityScopedFileAccessTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/SecurityScopedFileAccessTests.swift)（5 件）。

ViewModel.exportTranscript から使う security-scoped access／bookmark。OS API を直接使う。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| SA01 | [testBeginAccessThrowsForMissingFile](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/SecurityScopedFileAccessTests.swift:19) | 存在しないファイルで fileNotFound | **維持**。正確なエラー case を検証。権限付き URL の開始成功は未検証。 |
| SA02 | [testLastExportDirectoryBookmarkRoundTrip](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/SecurityScopedFileAccessTests.swift:28) | 保存した export ディレクトリ bookmark を復元 | **維持**。実 OS bookmark。UserDefaults.standard の元値を復元せず削除するため C01 の隔離が必要。 |
| SA03 | [testEndAccessIsNoOpForUnknownURL](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/SecurityScopedFileAccessTests.swift:42) | 未開始 URL に endAccess しても壊れない意図 | **置換**。L09。無関係なファイル実在しか観測せず、start／stop の釣合いは守れない。 |
| SA04 | [testEndAllAccessIsSafeWhenNothingStarted](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/SecurityScopedFileAccessTests.swift:50) | 空の endAllAccess がクラッシュしない | **削除候補**。L09。本番呼出しなしで true のみ。実際の access 解放は未検証。 |
| SA05 | [testResolveBookmarkThrowsForInvalidData](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/SecurityScopedFileAccessTests.swift:56) | 壊れた bookmark data を拒否 | **維持**。OS の失敗伝播を検証。loadLastExportDirectory の nil 復旧は未検証。 |

### TranscriptModelTests

対象: [TranscriptModelTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift)（8 件）。

Transcript Codable は export／history／recovery 共通。AppConfig／AppSettings と HistoryStore もこのファイルに同居。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| TM01 | [testTranscriptCodableRoundTrip](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:5) | Transcript の基本フィールドと segment を JSON 往復保持 | **維持**。EX03 と encoder の入口が異なる。createdAt／segment ID／追加 metadata の欠落は検出しない。 |
| TM02 | [testTranscriptSegmentIdentifiable](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:46) | segment の ID が nil でない | **削除候補**。L08。id は非 Optional UUID。固定 UUID を全件に返しても通る。 |
| TM03 | [testExportFormatFileExtensions](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:51) | Markdown／SRT／VTT の拡張子 | **維持**。保存名と UTType に使う外部形式契約。TXT／JSON の追加は容易。 |
| TM04 | [testAppConfigDefaultValues](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:58) | 同梱設定が空でなく Models という保存名を持つ | **維持**。実 bundle 設定ロードの smoke。validationErrors や全必須キーの検証ではない。 |
| TM05 | [testAppConfigCustomInit](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:67) | 注入したカスタム設定値を保持 | **維持**。デフォルト値の固定利用への退行を検出。3 項目だけ確認。 |
| TM06 | [testAppSettingsSharedHasValidSelection](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:86) | shared settings の選択肢が解決できる | **改善**。L25。保存済み値／共有初期化に依存。無効 ID の fallback や persist 往復を誘発しない。 |
| TM07 | [testHistoryStoreSaveAndRecent](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:96) | 一時 root への保存を recent から読み戻す | **維持**。保存・読み込み結合。複数件ソート／limit／壊れた JSON／検索は未検証。 |
| TM08 | [testHistoryStoreDelete](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptModelTests.swift:118) | 保存した履歴を delete すると recent が空 | **維持**。削除直前の存在確認を足すと保存失敗による偽陽性を防げる。 |

### TranscriptPartialTextBuilderTests

対象: [TranscriptPartialTextBuilderTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift)（8 件）。

WhisperKitTranscriber.segmentDiscoveryCallback → builder。5 件の differential は累積配列版との同値性を確認。サニタイザーは新旧で共有。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| PT01 | [testJoinedPresentableTextRemovesSpecialTokens](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:5) | ウィンドウ内のタグを除きタグだけの segment を落とす | **維持**。sanitizer 呼出しと compactMap／join の接続。 |
| PT02 | [testAppendPresentableWindowTextAccumulatesAcrossCalls](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:14) | 複数回のウィンドウ通知を順に累積 | **維持**。返り値と inout の状態を両方観測。 |
| PT03 | [testAppendPresentableWindowTextIgnoresTagOnlySegments](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:31) | タグだけのウィンドウは nil で状態を変えない | **維持**。空累積状態の guard。 |
| PT04 | [testDifferential_SingleSegment](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:54) | 単一 segment の旧実装同値性 | **維持**。空・空白・特殊トークンの表。共有 sanitizer の退行は TS 群で検出。 |
| PT05 | [testDifferential_MultiSegment_Window](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:71) | 複数 segment の 2 ウィンドウを旧実装と比較 | **維持**。ウィンドウ内結合とウィンドウ間結合を区別。 |
| PT06 | [testDifferential_MultiWindow_MixedTokens](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:86) | 日本語・英語・タグ・空白混在の累積同値性 | **維持**。内容の異なる複数通知で比較。 |
| PT07 | [testDifferential_AllTagOnlyWindows](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:103) | 全ウィンドウがタグのみでも新旧とも nil | **維持**。累積状態を汚さない繰返し。PT03 の一回限りとは範囲が異なる。 |
| PT08 | [testDifferential_100Windows](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:119) | 100 回の累積を毎回旧実装と比較 | **維持**。長い累積列の正しさ。実行時間は測らないため性能保証とは数えない。 |

### TranscriptTextSanitizerTests

対象: [TranscriptTextSanitizerTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift)（8 件）。

WhisperKit の mapping／部分結果 builder／ViewModel 表示で使う本番 sanitizer。固定期待値を使用。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| TS01 | [testRemovesWhisperSpecialTokens](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:5) | Whisper の言語・時刻・制御タグを消す | **維持**。代表的な固定 expected text。 |
| TS02 | [testRemovesTagsFromRealWorldSample](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:10) | nocaptions と通常文が混在する実例を整形 | **維持**。単一タグ列より複雑な結合ケース。 |
| TS03 | [testRemovesNoCaptionsAndEndOfTextTokens](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:15) | nocaptions／endoftext だけなら空文字 | **維持**。sanitize の返り値契約。nil を返す presentableText とは別。 |
| TS04 | [testCollapsesWhitespace](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:20) | 連続する半角空白と前後空白を整える | **維持**。改行・tab の扱いはこのテストの範囲外。 |
| TS05 | [testContainsSpecialTokenArtifactsDetectsTags](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:25) | 特殊トークン残骸ありを検出 | **維持**。presentableText の最後の guard から使われる判定。 |
| TS06 | [testContainsSpecialTokenArtifactsReturnsFalseForCleanText](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:31) | 通常の文を特殊トークンと誤認しない | **維持**。検出器の負例。 |
| TS07 | [testPresentableTextReturnsNilForTagOnlyInput](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:35) | タグだけの表示用テキストを nil にする | **維持**。sanitize の空文字契約から表示 API への変換。 |
| TS08 | [testPresentableTextReturnsCleanText](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptTextSanitizerTests.swift:43) | 表示用テキストをきれいな文として返す | **維持**。presentableText の正例。全角縦棒や壊れたタグは未検証。 |

### TranscriptionProgressDisplayTests

対象: [TranscriptionProgressDisplayTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift)（8 件）。

進捗 callback → TranscriptionProgressDisplay → StatusBarView。表示値の純粋変換を直接実行。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| PD01 | [testDownloadingModelShowsPercentDetail](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:5) | DL 45% を determinate・割合・モデル名と表示 | **維持**。exact な数値と文言結合を確認。 |
| PD02 | [testDownloadingModelShowsByteDetailWhenAvailable](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:23) | バイト進捗時にモデル名と / を表示 | **改善**。L16。64／100 の数値・単位・取り違えを観測していない。 |
| PD03 | [testLoadingModelUsesIndeterminateStyle](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:43) | モデルロードを不定進捗にし時間案内を表示 | **維持**。PD05 より assertion が強い。翻訳の日本語部分一致は C02。 |
| PD04 | [testTranscribingUsesDeterminateStyle](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:61) | 文字起こし 32% を determinate にする | **維持**。DL と異なるフェーズ分岐。 |
| PD05 | [testLoadingModelIncludesGuidanceDetail](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:77) | モデルロード時の時間案内 | **統合**。L12。PD03 とモデル名以外同じ分岐。モデル名を表にして統合可能。 |
| PD06 | [testTranscribingWithPartialTextIncludesPartialGuidance](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:91) | 途中結果ありなら案内と割合を併記 | **維持**。ViewModel のテキスト更新とは異なる表示契約。 |
| PD07 | [testIdleDisplayUsesWaitingLabel](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:104) | idle の待機中ラベル | **維持**。done と同じ phase を使うため文字ラベルを区別する価値がある。 |
| PD08 | [testAccessibilityLabelsForDownloadProgress](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionProgressDisplayTests.swift:113) | DL の VoiceOver 用ラベル・値 | **維持**。通常表示とは別のアクセシビリティ出力を exact 比較。 |

### TranscriptionSmokeTests

対象: [TranscriptionSmokeTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionSmokeTests.swift)（1 件）。

本番 downloader → WhisperKitTranscriber の実文字起こし。ローカル sample.wav がある場合のみ実行。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| SM01 | [testSmokeTranscriptionWithFixtureIfAvailable](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptionSmokeTests.swift:23) | 実音声の結果本文と segment が非空 | **置換**。L10。fixture は未追跡で CI に供給手順なし。通常 checkout では skip。Nightly の実行対象にもない。 |

### UpdateCheckServiceTests

対象: [UpdateCheckServiceTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift)（16 件）。

UpdateCheckViewModel → 実 UpdateCheckService → URLSession（MockURLProtocol 差替え）。JSON decoding／版比較／URL 検証を結合。全件が shared defaults の時刻と ETag を消す。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| UC01 | [testCheckForUpdateReturnsOfferWhenNewerVersionExists](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:46) | 新版の版番号・URL・notes を offer に反映 | **維持**。サービスを通る正常系。URL validator 単体と役割が異なる。 |
| UC02 | [testCheckForUpdateReturnsNilWhenUpToDate](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:93) | 同版なら offer を出さない | **維持**。AppVersion とサービスの接続を守る。 |
| UC03 | [testCheckForUpdateUsesFallbackWhenAssetMissing](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:128) | DMG asset 欠落なら設定 fallback を使う | **維持**。許可 URL の fallback 分岐。 |
| UC04 | [testCheckForUpdateUsesFallbackWhenAssetURLIsNotAllowed](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:163) | 許可外 asset URL なら fallback を使う | **維持**。欠落ではなく存在する危険 URL の拒否。 |
| UC05 | [testCheckForUpdateReturnsNilWhenNoAllowedDownloadURL](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:203) | asset と fallback の両方が危険なら offer を出さない | **維持**。信頼境界での閉じた失敗。 |
| UC06 | [testCheckForUpdateUsesFallbackWhenOnlyUnexpectedDMGExists](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:258) | 別名の DMG を誤選択しない | **維持**。拡張子一致だけの実装への退行を防ぐ。 |
| UC07 | [testCheckForUpdateReturnsNilWhenRepositoryDoesNotMatch](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:298) | 別リポジトリのレスポンスを拒否 | **維持**。full_name の早期拒否。HTML 側の証明は UC10／UC12 が担当。 |
| UC08 | [testCheckForUpdateReturnsNilWhenRepositoryHTMLURLContainsExpectedPath](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:338) | URL に正規 repo 文字列があっても拒否する意図 | **統合**。L13。先に不一致 full_name で拒否され HTML 検証に届かない。UC07／UC10 に吸収。 |
| UC09 | [testCheckForUpdateReturnsOfferWhenRepositoryFieldIsAbsent](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:378) | repository field がなくても正規 html_url なら許可 | **維持**。実 REST 応答相当の形を保護。 |
| UC10 | [testCheckForUpdateReturnsNilWhenRepositoryFieldIsAbsentAndHTMLURLIsUnrelated](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:421) | repository field 欠落時に埋込み URL を拒否 | **維持**。HTML の検証に到達する重要な負例。UC08 の統合先。 |
| UC11 | [testCheckForUpdateReturnsNilWhenRepositoryFullNameConflictsWithHTMLURL](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:458) | html_url が正しくても full_name 不一致を拒否 | **維持**。2 つの検証を OR に変える回帰を検出。 |
| UC12 | [testCheckForUpdateReturnsNilWhenRepositoryFullNameMatchesButHTMLURLDoesNot](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:498) | full_name が正しくても html_url 不一致を拒否 | **維持**。反対側の不一致。UC11 とは別の短絡条件。 |
| UC13 | [testCheckForUpdateReturnsOfferWhenRepositoryFieldIsNull](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:538) | repository が JSON null の正規リリースを許可 | **維持**。field 欠落とは wire format が異なる。入力表化しても null ケースは残す。 |
| UC14 | [testCheckForUpdateReturnsNilWhenHTMLURLLacksReleaseTag](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:580) | タグのない releases ページを拒否 | **維持**。helper をサービスが使い続けることを確認。 |
| UC15 | [testCheckForUpdateReturnsNilOnHTTPError](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:617) | HTTP 500 を更新なしにする意図 | **改善**。L27。body が空で JSON decode でも失敗する。HTTP status guard を消しても nil のまま。 |
| UC16 | [testCheckForUpdateSkipsWhenDisabled](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:641) | 設定無効時にネットワークへ行かない | **維持**。handler 内 XCTFail で検知できる。fatalError は不要で呼出回数の assertion が望ましい。 |

### UpdateURLValidatorTests

対象: [UpdateURLValidatorTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift)（10 件）。

UpdateCheckService の download／fallback／repository 検証に使用。ローカルの純粋関数として境界値を検証。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| UV01 | [testIsAllowedDownloadURLAcceptsExactHostMatch](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:10) | 許可ホストの HTTPS URL を受理 | **維持**。github.com／objects の両方を確認。 |
| UV02 | [testIsAllowedDownloadURLRejectsSubdomainWildcard](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:28) | 許可ホストの subdomain を暗黙に許可しない | **維持**。完全一致の安全境界。 |
| UV03 | [testIsAllowedDownloadURLRejectsNonHTTPSAndUnknownHosts](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:46) | HTTP と未知ホストを拒否 | **維持**。scheme／host の別条件。 |
| UV04 | [testMatchesReleaseHTMLURLAcceptsGitHubReleasePage](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:64) | 正規 repo の releases/tag ページを受理 | **維持**。repository validator の正例。 |
| UV05 | [testMatchesReleaseHTMLURLRejectsEmbeddedRepositorySubstring](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:76) | query への repo 文字列埋込みを拒否 | **維持**。helper 単体で URL 検証を必ず通る。 |
| UV06 | [testMatchesReleaseHTMLURLRejectsOtherRepository](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:88) | 他 owner／repo の release を拒否 | **維持**。正しい host でも repo が異なる負例。 |
| UV07 | [testMatchesReleaseHTMLURLRejectsRepositoryNamePrefix](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:100) | repo 名の prefix 一致を拒否 | **維持**。Transnote-malware の境界。 |
| UV08 | [testMatchesReleaseHTMLURLRejectsNonGitHubHostsAndHTTP](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:112) | 非 HTTPS と github.com.evil.com を拒否 | **維持**。URL の文字列 prefix 判定への退行を検出。 |
| UV09 | [testMatchesReleaseHTMLURLRejectsReleasesPathWithoutTag](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:130) | releases／latest／anything でタグなしを拒否 | **維持**。パス構造の 3 つの負例。 |
| UV10 | [testMatchesReleaseHTMLURLAcceptsTagContainingSlash](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateURLValidatorTests.swift:154) | タグに slash／encoded slash があっても受理 | **維持**。厳格すぎる拒否への退行を防ぐ正例。 |

### WhisperKitTranscriberTests

対象: [WhisperKitTranscriberTests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/WhisperKitTranscriberTests.swift)（1 件）。

実 WhisperKitTranscriber に空の一時モデル root を注入。音声は空ファイル。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| WT01 | [testTranscribeFailsWhenModelNotDownloaded](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/WhisperKitTranscriberTests.swift:22) | 未取得モデルを正確な modelNotDownloaded で拒否 | **維持**。adapter の先行チェックを守る。実 inference は行わない。固定一時ファイル名は並列実行時の衝突要因。 |

### LocalTranscriberUITests

対象: [LocalTranscriberUITests.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberUITests/LocalTranscriberUITests.swift)（3 件）。

実 XCUIApplication を起動。通常 PR CI と Nightly では非選択、Release では選択。locale／モデル／UserDefaults／recovery を隔離していない。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| UI01 | [testMainWindowLaunchesAndShowsEmptyState](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberUITests/LocalTranscriberUITests.swift:4) | 起動後に指定の空状態メッセージを表示する意図 | **改善**。L21。未取得モデルの初期状態では別の案内文が表示される。本テストは必要なモデル状態を作らない。 |
| UI02 | [testExportMenuAvailableAfterEmptyState](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberUITests/LocalTranscriberUITests.swift:12) | 空状態でも export menu が存在する | **改善**。L21。disabled／有効化／実保存を確認しないため Available という名前より保証が狭い。 |
| UI03 | [testSettingsSheetOpensAndCloses](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberUITests/LocalTranscriberUITests.swift:20) | 設定シートを上部・下部ボタンと Escape で閉じる | **維持**。3 つの実操作を確認。recovery を破棄する処理は実データへの副作用で C01。 |

### app.test

対象: [app.test.js](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js)（6 件）。

require で本番 app.js を読み、export された helper を検証。DOM は保存しない stub、fetch は両 URL に空配列を即返却。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| JS01 | [isAllowedDownloadURL allows github.com](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js:42) | github.com HTTPS を許可 | **維持**。本番 download URL validator を呼ぶ正例。 |
| JS02 | [isAllowedDownloadURL rejects http](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js:49) | HTTP を拒否 | **維持**。scheme の安全境界。 |
| JS03 | [isAllowedDownloadURL rejects other host](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js:53) | 未知ホストを拒否 | **維持**。host の安全境界。subdomain／壊れた URL／objects host は未検証。 |
| JS04 | [formatDate formats ISO date](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js:57) | ISO 日付を日本語表示にする | **改善**。L22。ローカル TZ 依存。America/Los_Angeles では実際に 1 月 14 日となり失敗。 |
| JS05 | [findDmgAsset matches versioned dmg](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js:61) | versioned DMG を選ぶ意図 | **改善**。L23。正解を先頭に置くため assets[0] の誤実装が実際に通過。 |
| JS06 | [findSha256Asset matches expected name](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js:69) | 対応する SHA256 asset を選ぶ意図 | **改善**。L23。同様に先頭要素の無条件選択が実際に通過。 |

### test-release-scripts

対象: [test-release-scripts.sh](/Users/fukutomiteppei/Documents/GitHub/Transnote/scripts/test-release-scripts.sh)（2 件）。

本番 set-marketing-version.sh を一時 workspace へコピーして実行。Release／Pages 全体ではなく版更新だけの 2 シナリオ。

| ID | テスト | 守る動作と実際の観測 | 判定と根拠 |
| --- | --- | --- | --- |
| SH01 | [正常版更新](/Users/fukutomiteppei/Documents/GitHub/Transnote/scripts/test-release-scripts.sh:20) | MARKETING_VERSION を更新する | **改善**。L24。grep -q は 1 件しか要求せず、2 行のうち 1 行だけ更新する mutant が実際に通過。 |
| SH02 | [不正版拒否](/Users/fukutomiteppei/Documents/GitHub/Transnote/scripts/test-release-scripts.sh:27) | bad-version の入力を非ゼロ終了で拒否 | **維持**。本番引数検査を通る。拒否後のファイル不変・引数不足・欠損 project は未検証。 |

## 補助コードと設定チェックの台帳

| 対象 | 守ること／監査結果 | 対応 |
| --- | --- | --- |
| [LocalizedStringTestSupport.swift](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/LocalizedStringTestSupport.swift:6) | L() でアプリ bundle の翻訳を期待値に使う。独立した test メソッドはない。 | 維持。日本語部分一致を使う既存テストの locale 方針を揃える。 |
| [PartialCopyThenFailFileManager](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioImportServiceTests.swift:236) | 空の部分コピーを残して失敗する。streaming fallback の試験に有用。 | AI10 で実際のコピー先と残骸を観測する。chmod による unreadable は実行 UID／FS 条件に依存。 |
| [AsyncGate と MockTranscriber](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelImportTests.swift:199) | 待機中のジョブを作る意図。opened を wait が参照せず、open-before-wait を失う。cancel は空実装。 | L20 の修正対象。実行開始と終了を待ち、取消も再開／解放につなぐ。 |
| [MockProgressTranscriber と waitUntil](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/MainWindowViewModelProgressTests.swift:277) | 途中結果を送って最終結果を返す。timeout は XCTFail する。 | mock 自体を本番推論保証と数えない。固定 delay を callback acknowledgment に替える。 |
| [legacyAppend](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/TranscriptPartialTextBuilderTests.swift:46) | 旧配列累積と新 String 累積の差分 oracle。sanitizer は共有。 | 累積の同値性の用途では有効。TS の固定 expected text を別に残し、これを速度測定とは呼ばない。 |
| [MockURLProtocol](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/UpdateCheckServiceTests.swift:673) | URLSession の通信境界だけを置換し、本番 decode と検証を実行する。 | request URL／headers／呼出回数を記録。UC16 の fatalError は不要。session を終了させる。 |
| [makeSilentWAV](/Users/fukutomiteppei/Documents/GitHub/Transnote/LocalTranscriberTests/AudioPlayerServiceTests.swift:144) | AVPlayer を動かす PCM fixture をケースごとに生成。 | 維持。ロード失敗を正常終了と誤認しない前提 assertion を足す。 |
| [noopElement と fetch stub](/Users/fukutomiteppei/Documents/GitHub/Transnote/site/app.test.js:2) | require 時の DOM／fetch 例外を避けるが、append／attributes を保存しない。fetch は両 endpoint とも空配列。 | helper 単体用としては妥当。画面の振る舞いは結果が観測できる DOM と制御可能な promise で別に検証する。 |
| [verify-readme-version.py](/Users/fukutomiteppei/Documents/GitHub/Transnote/scripts/verify-readme-version.py:31) | README と project の版一致を CI で検証。実行成功。本文の regex が見つかると表の regex は調べない。 | 本文と表の全表記一致を守るなら両方を集計する。この checker 自体の不一致／欠損 fixture テストはない。 |
| [generate-site-config.py](/Users/fukutomiteppei/Documents/GitHub/Transnote/scripts/generate-site-config.py:44) | 設定から app.js の生成 block が最新かを確認。実測は marker 不在で失敗。 | 配置を修復し、PR で --check する。marker 欠落、差分あり、変更不要の各 fixture を checker 自体にも用意する。 |
| [generate_xcodeproj.py](/Users/fukutomiteppei/Documents/GitHub/Transnote/scripts/generate_xcodeproj.py:54) | ソース登録と scheme を生成するが、現 project と同期していない。AST 比較と一時コピーでの再生成の両方で、SecurityScopedFileAccessTests と全 UI テスト、アプリの HistoryStore が外れることを確認。 | 現 project では全テスト登録済みだが、再生成すると 5 単体＋3 UI の登録と UI target が消え、HistoryStore も外れる。一時コピーでの再生成と全ソース登録の一致を検証する gate が必要。 |
| [CI の lint／Package.resolved 検査](/Users/fukutomiteppei/Documents/GitHub/Transnote/.github/workflows/ci.yml:55) | ShellCheck、generate_xcodeproj の Python 構文、README、lockfile の存在・差分を検査。swift-format は `\|\| echo` で非 blocking。 | 整合性・構文の gate と動作テストを区別する。SBOM 生成や archive／DMG 作成の成功をテストケースとして水増ししない。 |

## 対応順と完了条件

1. **P1 の本番接続と偽陽性を修復する。** DL 失敗、import 一時ファイル、取消、実文字起こしに、実際の入口と失敗を観測するテストを置く。現状の弱いテストを消す前に、守るべき失敗を新テストが検出することを確認する。
2. **fixture と実行状態を隔離する。** shared defaults、History／recovery、実モデル、UI locale、async gate を制御する。通常 CI と Nightly の選択対象だけでなく、skip 理由と実行件数を確認できるようにする。
3. **重複を統合し、未使用コードのテストと診断 probe を整理する。** L12 の統合先に入力と assertion を残し、L04〜09 は本番呼出しの有無を再確認してコードと一緒に判断する。
4. **少数の具体的な誤実装で改善を確認する。** 先頭 asset 固定、1 か所だけの版更新、cleanup 呼出し削除、誤った schemaVersion、キャンセル先の誤接続を新しいテストが失敗として検出することを完了条件にする。単に全テストが緑という条件だけにはしない。

この監査で未確定の製品仕様は、日付のタイムゾーン、全文と複数 segment の編集同期、checkpoint からの再開範囲など。台帳は観測できる現状と保護の欠落までを記録した。実装修正時には既存の期待動作を確認してから期待値を定める。
