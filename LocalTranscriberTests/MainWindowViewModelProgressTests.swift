import XCTest
@testable import LocalTranscriber

@MainActor
final class MainWindowViewModelProgressTests: XCTestCase {
    private var audioURL: URL!
    private var isolatedRoot: URL!
    private var defaultsSuiteName: String!
    private var isolatedDefaults: UserDefaults!
    private var isolatedSettings: AppSettings!
    private var isolatedHistoryStore: HistoryStore!
    private var viewModel: MainWindowViewModel!

    override func setUpWithError() throws {
        isolatedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedRoot, withIntermediateDirectories: true)
        audioURL = isolatedRoot.appendingPathComponent("\(UUID().uuidString).wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: audioURL.path, contents: Data(count: 64)))

        defaultsSuiteName = "MainWindowViewModelProgressTests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: defaultsSuiteName)
        isolatedSettings = AppSettings(defaults: isolatedDefaults)
        isolatedHistoryStore = HistoryStore(
            historyRoot: isolatedRoot.appendingPathComponent("History", isDirectory: true),
            temporaryRoot: isolatedRoot.appendingPathComponent("TempTranscripts", isDirectory: true)
        )
    }

    override func tearDownWithError() throws {
        viewModel?.cancelActiveOperation()
        if let defaultsSuiteName {
            isolatedDefaults?.removePersistentDomain(forName: defaultsSuiteName)
        }
        try? FileManager.default.removeItem(at: isolatedRoot)
    }

    private func makeIsolatedViewModel(
        transcriber: any Transcriber = WhisperKitTranscriber(),
        modelsRoot: URL? = nil,
        modelAvailability: ModelAvailabilityService? = nil,
        modelDownloadService: ModelDownloadService? = nil
    ) -> MainWindowViewModel {
        let root = modelsRoot ?? isolatedRoot.appendingPathComponent("Models", isDirectory: true)
        let availability = modelAvailability ?? ModelAvailabilityService(modelsRoot: root)
        let dependencies = AppDependencies(
            transcriber: transcriber,
            audioImportService: AudioImportService(importsRoot: isolatedRoot.appendingPathComponent("Imports", isDirectory: true)),
            settings: isolatedSettings,
            modelAvailability: availability,
            modelDownloadService: modelDownloadService ?? ModelDownloadService(modelsRoot: root, modelAvailability: availability),
            historyStore: isolatedHistoryStore
        )
        return MainWindowViewModel(dependencies: dependencies)
    }

    func testPartialTextUpdatesDuringTranscription() async throws {
        // Given: partialText を2回 emit する Mock Transcriber
        let firstPartialGate = ProgressGate()
        let secondPartialGate = ProgressGate()
        let mock = MockProgressTranscriber(
            partialTexts: ["Hello", "Hello world"],
            finalText: "Hello world final",
            delayNanoseconds: 50_000_000,
            progressGates: [firstPartialGate, secondPartialGate]
        )
        viewModel = makeIsolatedViewModel(transcriber: mock)
        configureForTranscription()

        // When
        viewModel.startTranscription()

        // Then: 1回目の partialText が反映される
        try await waitUntil { self.viewModel.transcriptText == "Hello" }
        XCTAssertEqual(viewModel.uiState, .transcribing)
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertFalse(viewModel.canExport)
        firstPartialGate.open()

        // Then: 2回目の partialText が反映される
        try await waitUntil { self.viewModel.transcriptText == "Hello world" }
        XCTAssertFalse(viewModel.canExport)
        secondPartialGate.open()

        // Then: 完了後は最終 Transcript で上書きされる
        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "Hello world final")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "Hello world final")
        XCTAssertTrue(viewModel.canExport)
    }

    func testPartialTextWithOnlySpecialTokenArtifactsDoesNotUpdateTranscript() async throws {
        let mock = MockProgressTranscriber(
            partialTexts: ["<|startoftranscript|><|nocaptions|><|endoftext|>"],
            finalText: "final",
            delayNanoseconds: 50_000_000,
            finalDelayNanoseconds: 500_000_000
        )
        viewModel = makeIsolatedViewModel(transcriber: mock)
        configureForTranscription()

        viewModel.startTranscription()

        try await waitUntil { self.viewModel.uiState == .transcribing }
        try await waitUntil { mock.partialTextCount == 1 }
        XCTAssertEqual(viewModel.transcriptText, "")
        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "final")
    }

    func testPartialGuidanceAndTranscriptShareSanitizedResult() async throws {
        let rawTexts = [
            "<|ja|> こんにちは 🌏 <|endoftext|>",
            "<｜nocaptions｜>",
            " \t\n ",
            "<|ja|>こんにちは 🌏   続き<｜endoftext｜>",
        ]
        let presentableTexts: [String?] = ["こんにちは 🌏", nil, nil, "こんにちは 🌏 続き"]
        let gates = rawTexts.map { _ in ProgressGate() }
        let mock = MockProgressTranscriber(
            partialTexts: rawTexts,
            finalText: "final",
            delayNanoseconds: 0,
            progressGates: gates
        )
        viewModel = makeIsolatedViewModel(transcriber: mock)
        configureForTranscription()
        defer {
            gates.forEach { $0.open() }
            viewModel.cancelTranscription()
        }

        viewModel.startTranscription()
        var lastPresentableText = ""
        let guidance = L("途中結果を表示中", comment: "Partial transcription guidance")
        for index in rawTexts.indices {
            let fraction = Double(index + 1) / Double(rawTexts.count + 1)
            // emit 済みかではなく、メインアクターで適用済みかを待つ。
            try await waitUntil { self.viewModel.progressDisplay.fraction == fraction }
            let presentable = presentableTexts[index]
            if let presentable {
                lastPresentableText = presentable
            }
            let percent = Int(fraction * 100)
            XCTAssertEqual(viewModel.transcriptText, lastPresentableText)
            XCTAssertEqual(viewModel.progressDisplay.presentablePartialText, presentable)
            XCTAssertEqual(
                viewModel.progressDisplay.detailLabel,
                presentable == nil ? "\(percent)%" : "\(guidance) · \(percent)%"
            )
            XCTAssertEqual(viewModel.uiState, .transcribing)
            gates[index].open()
        }

        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "final")
    }

    func testStartTranscriptionClearsPreviousResult() async throws {
        // Given: 前回の文字起こし結果が残っている
        let mock = MockProgressTranscriber(
            partialTexts: [],
            finalText: "new result",
            delayNanoseconds: 100_000_000
        )
        viewModel = makeIsolatedViewModel(transcriber: mock)
        configureForTranscription()
        viewModel.transcriptText = "previous result"
        viewModel.currentTranscript = Transcript(
            sourceFileName: "old.wav",
            fullText: "previous result"
        )

        // When
        viewModel.startTranscription()
        // 既存結果がある場合は確認が表示され、完了するまで結果を保持する。
        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertEqual(viewModel.transcriptText, "previous result")
        XCTAssertNotNil(viewModel.currentTranscript)

        viewModel.cancelPendingFileImport()
        XCTAssertFalse(viewModel.confirmFileImport)

        // Then: 開始直後に前回結果がクリアされる
        XCTAssertEqual(viewModel.transcriptText, "previous result")
        XCTAssertNotNil(viewModel.currentTranscript)
    }

    func testModelDownloadButtonIsShownForModelThatIsNotDownloaded() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.downloadedModelIDs = []

        XCTAssertTrue(viewModel.shouldShowModelDownloadButton)
        XCTAssertTrue(viewModel.canDownloadSelectedModel)
    }

    func testModelDownloadButtonIsHiddenForDownloadedModel() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.downloadedModelIDs = ["base"]

        XCTAssertFalse(viewModel.shouldShowModelDownloadButton)
        XCTAssertFalse(viewModel.canDownloadSelectedModel)
    }

    func testModelDownloadButtonRemainsShownButCannotRunWhileDownloading() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.downloadedModelIDs = []
        viewModel.simulateModelDownloadForTesting()

        XCTAssertTrue(viewModel.shouldShowModelDownloadButton)
        XCTAssertFalse(viewModel.canDownloadSelectedModel)
    }

    func testStartTranscriptionIsRejectedWhileModelDownloadIsSimulated() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.downloadedModelIDs = ["base"]
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        viewModel.simulateModelDownloadForTesting()

        viewModel.startTranscription()

        XCTAssertEqual(viewModel.uiState, .preparing)
        XCTAssertEqual(viewModel.progressDisplay.phase, .downloadingModel)
        XCTAssertTrue(viewModel.isDownloadingModel)
        XCTAssertTrue(viewModel.isBusy)
        XCTAssertTrue(viewModel.canCancel)
        XCTAssertNil(viewModel.transcriptionTask)
        XCTAssertEqual(viewModel.inlineErrorTitle, L("処理中", comment: "Busy title"))
        XCTAssertEqual(
            viewModel.inlineErrorMessage,
            L("別の処理を実行中のため開始できません。", comment: "Busy message")
        )
        XCTAssertFalse(viewModel.canRetryError)
        XCTAssertEqual(
            viewModel.cancelActionAccessibilityLabel,
            L("ダウンロードをキャンセル", comment: "Cancel model download accessibility label")
        )
        XCTAssertEqual(
            viewModel.cancelActionHelp,
            L("ダウンロードをキャンセル（⌘.）", comment: "Cancel model download shortcut help")
        )
        XCTAssertEqual(
            viewModel.startTranscriptionDisabledReason,
            L("文字起こし処理中です", comment: "Transcription is busy")
        )
    }

    func testRejectedTranscriptionStartPreservesActiveTranscriptionState() async throws {
        let gate = ProgressGate()
        let mock = MockProgressTranscriber(
            partialTexts: ["partial"],
            finalText: "final",
            delayNanoseconds: 0,
            progressGates: [gate]
        )
        viewModel = makeIsolatedViewModel(transcriber: mock)
        configureForTranscription()
        defer {
            gate.open()
            viewModel.cancelTranscription()
        }
        viewModel.startTranscription()
        try await waitUntil { self.viewModel.uiState == .transcribing }

        viewModel.startTranscription()

        XCTAssertEqual(viewModel.uiState, .transcribing)
        XCTAssertEqual(viewModel.progressDisplay.phase, .transcribing)
        XCTAssertEqual(viewModel.transcriptText, "partial")
        XCTAssertTrue(viewModel.isBusy)
        XCTAssertFalse(viewModel.isDownloadingModel)
        XCTAssertEqual(viewModel.inlineErrorTitle, L("処理中", comment: "Busy title"))
        XCTAssertFalse(viewModel.canRetryError)

        gate.open()
        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "final")
    }

    func testTranscriptionFailureStillResetsUIStateToIdle() async throws {
        viewModel = makeIsolatedViewModel(transcriber: FailingProgressTranscriber())
        configureForTranscription()

        viewModel.startTranscription()
        XCTAssertEqual(viewModel.uiState, .preparing)
        try await waitUntil { self.viewModel.inlineErrorMessage != nil && !self.viewModel.isBusy }

        XCTAssertEqual(viewModel.uiState, .idle)
        XCTAssertEqual(viewModel.inlineErrorTitle, L("文字起こしエラー", comment: "Transcription error title"))
        XCTAssertTrue(viewModel.canRetryError)
        XCTAssertFalse(viewModel.canCancel)
        XCTAssertNil(viewModel.transcriptionTask)
    }

    func testModelDownloadGuidanceIsShownForModelThatIsNotDownloaded() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.downloadedModelIDs = []

        XCTAssertNotNil(viewModel.modelDownloadGuidance)
        XCTAssertTrue(viewModel.modelDownloadGuidance?.contains("ダウンロード") == true)
    }

    func testModelDownloadGuidanceIsHiddenForDownloadedModel() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.downloadedModelIDs = ["base"]

        XCTAssertNil(viewModel.modelDownloadGuidance)
    }

    func testCancelActionLabelsSwitchForModelDownload() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.simulateModelDownloadForTesting()

        XCTAssertEqual(
            viewModel.cancelActionAccessibilityLabel,
            L("ダウンロードをキャンセル", comment: "Cancel model download accessibility label")
        )
        XCTAssertEqual(viewModel.cancelMenuTitle, viewModel.cancelActionAccessibilityLabel)
        XCTAssertEqual(
            viewModel.cancelActionHelp,
            L("ダウンロードをキャンセル（⌘.）", comment: "Cancel model download shortcut help")
        )
    }

    func testCancelActionLabelsStayOnTranscriptionDuringTranscription() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.uiState = .transcribing
        

        XCTAssertEqual(
            viewModel.cancelActionAccessibilityLabel,
            L("文字起こしをキャンセル", comment: "Cancel transcription accessibility label")
        )
        XCTAssertEqual(viewModel.cancelMenuTitle, viewModel.cancelActionAccessibilityLabel)
        XCTAssertEqual(
            viewModel.cancelActionHelp,
            L("文字起こしをキャンセル（⌘.）", comment: "Cancel transcription shortcut help")
        )
    }

    func testCanCopyTranscriptRequiresNonEmptyResult() {
        viewModel = makeIsolatedViewModel()
        XCTAssertFalse(viewModel.canCopyTranscript)

        viewModel.currentTranscript = Transcript(sourceFileName: "a.wav", fullText: "text")
        viewModel.transcriptText = "text"
        XCTAssertTrue(viewModel.canCopyTranscript)
    }

    func testCanExportTracksTranscriptTextUpdatesIncludingWhitespaceOnly() {
        viewModel = makeIsolatedViewModel()
        viewModel.currentTranscript = Transcript(sourceFileName: "a.wav", fullText: "text")
        XCTAssertFalse(viewModel.canExport)

        viewModel.transcriptText = "text"
        XCTAssertTrue(viewModel.canExport)

        viewModel.transcriptText = "   \n\t "
        XCTAssertFalse(viewModel.canExport)

        viewModel.transcriptText = "  text  "
        XCTAssertTrue(viewModel.canExport)

        viewModel.transcriptText = ""
        XCTAssertFalse(viewModel.canExport)
    }

    func testRecoverableModelNotDownloadedErrorUsesInlineBannerOnly() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        viewModel.downloadedModelIDs = []

        viewModel.startTranscription()

        XCTAssertEqual(
            viewModel.inlineErrorTitle,
            L("モデル未ダウンロード", comment: "Model not downloaded title")
        )
        XCTAssertNotNil(viewModel.inlineErrorMessage)
        XCTAssertNil(viewModel.criticalErrorMessage)
        XCTAssertEqual(viewModel.uiState, .idle)
    }

    func testStartTranscriptionDisabledReasonTracksBlockingCondition() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.downloadedModelIDs = ["base"]

        // No file selected: reason points at the missing file
        XCTAssertEqual(
            viewModel.startTranscriptionDisabledReason,
            L("音声ファイルを選択してください", comment: "Select an audio file")
        )

        // File selected: no blocking condition remains, start is available
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        XCTAssertNil(viewModel.startTranscriptionDisabledReason)
        XCTAssertTrue(viewModel.canStartTranscription)
    }

    func testModelDownloadSuccessToastMessageWhenFileIsSelected() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )

        XCTAssertTrue(viewModel.modelDownloadSuccessToastMessage().contains("文字起こしを開始"))
    }

    func testModelDownloadSuccessToastMessageWhenNoFileIsSelected() {
        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel()

        XCTAssertTrue(viewModel.modelDownloadSuccessToastMessage().contains("音声ファイルを選択"))
    }

    func testHasPlayableSegmentsReturnsFalseForEmptySegments() {
        let transcript = Transcript(sourceFileName: "test.wav", fullText: "hello", segments: [])

        XCTAssertFalse(MainWindowViewModel.hasPlayableSegments(in: transcript))
    }

    func testHasPlayableSegmentsReturnsTrueWhenSegmentTextExists() {
        let transcript = Transcript(
            sourceFileName: "test.wav",
            fullText: "hello",
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "hello")]
        )

        XCTAssertTrue(MainWindowViewModel.hasPlayableSegments(in: transcript))
    }

    func testUpdateSegmentTextRebuildsFullText() {
        viewModel = makeIsolatedViewModel()
        let segmentIDs = [UUID(), UUID()]
        viewModel.currentTranscript = Transcript(
            sourceFileName: "test.wav",
            fullText: "old first\nold second",
            segments: [
                TranscriptSegment(id: segmentIDs[0], startTime: 0, endTime: 1, text: "old first"),
                TranscriptSegment(id: segmentIDs[1], startTime: 1, endTime: 2, text: "old second")
            ]
        )

        viewModel.updateSegmentText(id: segmentIDs[1], text: "new second")

        XCTAssertEqual(viewModel.transcriptText, "old first\nnew second")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "old first\nnew second")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testSegmentEditsMatchJoinedTextAcrossUnicodeAndEmptySegments() {
        viewModel = makeIsolatedViewModel()
        var segments = ["先頭\r", "", "e\u{301} 👨‍👩‍👧‍👦", "末尾\n行"].enumerated().map { index, text in
            TranscriptSegment(startTime: Double(index), endTime: Double(index + 1), text: text)
        }
        // 初回編集は、セグメント結合と異なる全文も従来どおり置き換える。
        viewModel.restoreTranscript(Transcript(sourceFileName: "test.wav", fullText: "別の全文", segments: segments))
        let edits: [(Int, String)] = [
            (0, "先頭\r更新"), (0, "先頭\r"), (0, ""),
            (1, "\u{301}🇯🇵"), (1, "\n\n"), (1, ""),
            (2, "👩🏽‍💻"), (2, "e\u{301}"), (2, ""),
            (3, "末尾\r\n次の行"), (3, ""), (3, "復元"),
            (0, "再び先頭"), (2, "中間"), (1, "空でなくなった行")
        ]

        for (index, text) in edits {
            let snapshot = viewModel.currentTranscript
            let oldTexts = snapshot?.segments.map(\.text)
            segments[index].text = text
            viewModel.updateSegmentText(id: segments[index].id, text: text)

            let expected = segments.map(\.text).joined(separator: "\n")
            XCTAssertEqual(viewModel.transcriptText, expected)
            XCTAssertEqual(viewModel.currentTranscript?.fullText, expected)
            XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.text), segments.map(\.text))
            XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.id), segments.map(\.id))
            XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.startTime), segments.map(\.startTime))
            XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.endTime), segments.map(\.endTime))
            XCTAssertEqual(snapshot?.segments.map(\.text), oldTexts, "既存のスナップショットを変更しない")
        }
        XCTAssertEqual(viewModel.baselineTranscriptText, "別の全文")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.canExport)
        XCTAssertTrue(viewModel.canCopyTranscript)
    }

    func testSegmentEditLocationIsInvalidatedByFullTextEditing() {
        viewModel = makeIsolatedViewModel()
        for count in [1, 3] {
            let initialSegments = (0..<count).map { index in
                TranscriptSegment(startTime: Double(index), endTime: Double(index + 1), text: "行\(index)")
            }
            viewModel.restoreTranscript(Transcript(sourceFileName: "test.wav", fullText: "元の全文", segments: initialSegments))
            let index = count - 1
            viewModel.updateSegmentText(id: initialSegments[index].id, text: "最初の編集")
            viewModel.updateTranscriptText("全文編集で長さが変わる 👨‍👩‍👧‍👦\n")
            XCTAssertEqual(viewModel.currentTranscript?.fullText, viewModel.transcriptText)

            var syncedSegments = viewModel.currentTranscript?.segments ?? []
            XCTAssertEqual(syncedSegments.count, count)
            syncedSegments[index].text = "セグメント編集へ戻る"
            viewModel.updateSegmentText(id: syncedSegments[index].id, text: syncedSegments[index].text)
            XCTAssertEqual(viewModel.transcriptText, syncedSegments.map(\.text).joined(separator: "\n"))
            XCTAssertEqual(viewModel.currentTranscript?.fullText, viewModel.transcriptText)
            // 再初期化後の差分置換も正しい位置へ適用する。
            syncedSegments[index].text = "もう一文字"
            viewModel.updateSegmentText(id: syncedSegments[index].id, text: syncedSegments[index].text)
            XCTAssertEqual(viewModel.transcriptText, syncedSegments.map(\.text).joined(separator: "\n"))
        }
    }

    // MARK: - Full Text & segment synchronization (#195)

    func testUpdateTranscriptTextSyncsMultiSegmentLinesOneToOne() {
        viewModel = MainWindowViewModel()
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 1, text: "一行目"),
            TranscriptSegment(startTime: 1, endTime: 2, text: "二行目"),
            TranscriptSegment(startTime: 2, endTime: 3, text: "三行目")
        ]
        viewModel.restoreTranscript(
            Transcript(sourceFileName: "sync.wav", fullText: "一行目\n二行目\n三行目", segments: segments)
        )

        viewModel.updateTranscriptText("一行目\n編集後の二行目\n三行目")

        XCTAssertEqual(viewModel.currentTranscript?.fullText, "一行目\n編集後の二行目\n三行目")
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.text), ["一行目", "編集後の二行目", "三行目"])
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.id), segments.map(\.id))
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.startTime), [0, 1, 2])
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.endTime), [1, 2, 3])
    }

    func testUpdateTranscriptTextSyncsInsertedAndDeletedLinesAnchoringUnchangedSegments() {
        viewModel = MainWindowViewModel()
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 1, text: "先頭"),
            TranscriptSegment(startTime: 1, endTime: 2, text: "中間"),
            TranscriptSegment(startTime: 2, endTime: 3, text: "末尾")
        ]
        viewModel.restoreTranscript(
            Transcript(sourceFileName: "sync.wav", fullText: "先頭\n中間\n末尾", segments: segments)
        )

        // 中間に複数行を挿入しても、先頭と末尾セグメントは元のまま保持される。
        viewModel.updateTranscriptText("先頭\n中間A\n中間B\n末尾")
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.text), ["先頭", "中間A\n中間B", "末尾"])

        // 中間行を削除した場合も先頭と末尾は保持され、削除区間が空になる。
        viewModel.updateTranscriptText("先頭\n末尾")
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.text), ["先頭", "", "末尾"])
    }

    func testUpdateTranscriptTextSyncsSingleLineEditAcrossMultipleSegments() {
        viewModel = MainWindowViewModel()
        let segments = [
            TranscriptSegment(startTime: 0, endTime: 1, text: "Hello"),
            TranscriptSegment(startTime: 1, endTime: 2, text: "world"),
            TranscriptSegment(startTime: 2, endTime: 3, text: "today")
        ]
        viewModel.restoreTranscript(
            Transcript(sourceFileName: "en.wav", fullText: "Hello world today", segments: segments)
        )

        viewModel.updateTranscriptText("Hello Swift today")
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.text), ["Hello", "Swift", "today"])

        // 日本語（空白区切りなし）の単一行編集でも旧テキストを残さず配分する。
        let jpSegments = [
            TranscriptSegment(startTime: 0, endTime: 1, text: "こんにちは"),
            TranscriptSegment(startTime: 1, endTime: 2, text: "世界")
        ]
        viewModel.restoreTranscript(
            Transcript(sourceFileName: "ja.wav", fullText: "こんにちは世界", segments: jpSegments)
        )
        viewModel.updateTranscriptText("こんにちは日本")
        XCTAssertEqual(viewModel.currentTranscript?.segments.map(\.text), ["こんにちは", "日本"])
    }

    func testSegmentEditLocationIsInvalidatedWhenTranscriptIsReplaced() {
        viewModel = makeIsolatedViewModel()
        let first = TranscriptSegment(startTime: 0, endTime: 1, text: "先頭")
        var second = TranscriptSegment(startTime: 1, endTime: 2, text: "末尾")
        var transcript = Transcript(sourceFileName: "test.wav", fullText: "先頭\n末尾", segments: [first, second])
        viewModel.restoreTranscript(transcript)
        viewModel.updateSegmentText(id: second.id, text: "末尾の編集")

        // 同じ Transcript/segment ID でも、復元で順序と長さが変わり得る。
        second.text = "復元後は先頭"
        transcript.segments = [second, first]
        viewModel.restoreTranscript(transcript)
        viewModel.updateSegmentText(id: second.id, text: "復元後の編集")
        XCTAssertEqual(viewModel.transcriptText, "復元後の編集\n先頭")

        // 公開プロパティ経由の更新でも古い位置を使わない。
        viewModel.currentTranscript?.segments[0].text = "外部更新で長くなったテキスト"
        viewModel.updateSegmentText(id: second.id, text: "再編集")
        XCTAssertEqual(viewModel.transcriptText, "再編集\n先頭")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, viewModel.transcriptText)
    }

    func testUnknownSegmentIDDoesNotChangeTranscriptOrEditLocation() {
        viewModel = makeIsolatedViewModel()
        viewModel.updateSegmentText(id: UUID(), text: "無視する")
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertEqual(viewModel.transcriptText, "")

        viewModel.restoreTranscript(Transcript(sourceFileName: "test.wav", fullText: "全文のみ"))
        viewModel.updateSegmentText(id: UUID(), text: "無視する")
        XCTAssertEqual(viewModel.transcriptText, "全文のみ")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "全文のみ")
        XCTAssertFalse(viewModel.hasUnsavedChanges)

        let segment = TranscriptSegment(startTime: 0, endTime: 1, text: "元")
        viewModel.restoreTranscript(Transcript(sourceFileName: "test.wav", fullText: "元", segments: [segment]))
        viewModel.updateSegmentText(id: segment.id, text: "編集")
        viewModel.updateSegmentText(id: UUID(), text: "無視する")
        XCTAssertEqual(viewModel.transcriptText, "編集")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "編集")
        XCTAssertEqual(viewModel.currentTranscript?.segments.first?.text, "編集")
        viewModel.updateSegmentText(id: segment.id, text: "")
        XCTAssertEqual(viewModel.transcriptText, "")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "")
        XCTAssertFalse(viewModel.canExport)
        XCTAssertFalse(viewModel.canCopyTranscript)
        viewModel.updateSegmentText(id: segment.id, text: "元")
        XCTAssertEqual(viewModel.transcriptText, "元")
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    // 外部音声・モデル不要の計測。固定の時間閾値は設けず、CI で連続入力のコストを記録する。
    func testMeasureRepeatedSegmentTextEditsInLongTranscript() {
        viewModel = makeIsolatedViewModel()
        let segments = (0..<3_000).map { index in
            TranscriptSegment(startTime: Double(index), endTime: Double(index + 1), text: "行\(index) 日本語と emoji 👩🏽‍💻")
        }
        let transcript = Transcript(
            sourceFileName: "long.wav",
            fullText: segments.map(\.text).joined(separator: "\n"),
            segments: segments
        )
        let id = segments[segments.count - 1].id

        measure {
            viewModel.restoreTranscript(transcript)
            for index in 0..<100 {
                viewModel.updateSegmentText(id: id, text: "入力\(index)")
            }
        }
        let expected = segments.dropLast().map(\.text).joined(separator: "\n") + "\n入力99"
        XCTAssertEqual(viewModel.transcriptText, expected)
        XCTAssertEqual(viewModel.currentTranscript?.fullText, expected)
        XCTAssertEqual(viewModel.currentTranscript?.segments.last?.text, "入力99")
    }

    func testCancelActiveOperationCancelsModelDownloadAndAllowsRestart() async throws {
        let modelsRoot = isolatedRoot.appendingPathComponent("DownloadCancelModels", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let availability = ModelAvailabilityService(modelsRoot: modelsRoot)
        let downloadStarted = ProgressGate()
        let downloadCancelled = ProgressGate()
        let attemptCount = DownloadAttemptBox()

        let downloadService = ModelDownloadService(
            modelsRoot: modelsRoot,
            modelAvailability: availability,
            downloadModel: { variant, downloadBase, _ in
                let currentAttempt = attemptCount.increment()
                if currentAttempt == 1 {
                    downloadStarted.open()
                    try await withTaskCancellationHandler {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                    } onCancel: {
                        downloadCancelled.open()
                    }
                }
                let folder = downloadBase.appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
                    try Data("model".utf8).write(to: folder.appendingPathComponent("\(name).mlmodelc"))
                }
                return folder
            },
            retryDelayNanoseconds: { _ in 0 }
        )

        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel(
            modelsRoot: modelsRoot,
            modelAvailability: availability,
            modelDownloadService: downloadService
        )
        XCTAssertTrue(viewModel.canDownloadSelectedModel)

        viewModel.downloadSelectedModel()
        await downloadStarted.wait()
        XCTAssertTrue(viewModel.isDownloadingModel)
        XCTAssertTrue(viewModel.canCancel)

        // UI から呼ばれる cancelActiveOperation がモデルダウンロードの Task を実際にキャンセルする
        viewModel.cancelActiveOperation()
        await downloadCancelled.wait()
        XCTAssertEqual(viewModel.uiState, .idle)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertNil(viewModel.errorMessage)

        // キャンセル後に再度ダウンロードを開始して正常完了できること
        viewModel.downloadSelectedModel()
        try await waitUntil { self.viewModel.downloadedModelIDs.contains("base") && !self.viewModel.isBusy }
        XCTAssertEqual(attemptCount.value, 2)
    }

    func testModelDownloadCancelFailureAndCompletionPreserveDoneStateWithExistingTranscript() async throws {
        let modelsRoot = isolatedRoot.appendingPathComponent("DownloadDoneStateModels", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        let availability = ModelAvailabilityService(modelsRoot: modelsRoot)
        let cancelStarted = ProgressGate()
        let cancelObserved = ProgressGate()
        let attemptCount = DownloadAttemptBox()

        let downloadService = ModelDownloadService(
            modelsRoot: modelsRoot,
            modelAvailability: availability,
            downloadModel: { variant, downloadBase, _ in
                let currentAttempt = attemptCount.increment()
                switch currentAttempt {
                case 1:
                    cancelStarted.open()
                    try await withTaskCancellationHandler {
                        try await Task.sleep(nanoseconds: 10_000_000_000)
                    } onCancel: {
                        cancelObserved.open()
                    }
                    throw CancellationError()
                case 2:
                    throw AppError.fileAccessDenied
                default:
                    let folder = downloadBase.appendingPathComponent("openai_whisper-\(variant)", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
                        try Data("model".utf8).write(to: folder.appendingPathComponent("\(name).mlmodelc"))
                    }
                    return folder
                }
            },
            retryDelayNanoseconds: { _ in 0 }
        )

        isolatedSettings.selectedModelID = "base"
        viewModel = makeIsolatedViewModel(
            modelsRoot: modelsRoot,
            modelAvailability: availability,
            modelDownloadService: downloadService
        )
        let existing = Transcript(sourceFileName: "done.wav", fullText: "完了済みテキスト")
        viewModel.restoreTranscript(existing)
        XCTAssertEqual(viewModel.uiState, .done)
        XCTAssertEqual(viewModel.progressDisplay, .done())

        // 1) ダウンロードキャンセル時に .done / .done() が復元されること
        viewModel.downloadSelectedModel()
        await cancelStarted.wait()
        XCTAssertTrue(viewModel.isDownloadingModel)
        viewModel.cancelModelDownload()
        await cancelObserved.wait()
        XCTAssertEqual(viewModel.uiState, .done)
        XCTAssertEqual(viewModel.progressDisplay, .done())
        XCTAssertEqual(viewModel.currentTranscript?.id, existing.id)

        // 2) ダウンロード失敗時にも .done / .done() が維持されること
        viewModel.downloadSelectedModel()
        try await waitUntil { !self.viewModel.isBusy && self.viewModel.inlineErrorMessage != nil }
        XCTAssertEqual(viewModel.uiState, .done)
        XCTAssertEqual(viewModel.progressDisplay, .done())
        XCTAssertEqual(viewModel.currentTranscript?.id, existing.id)

        // 3) ダウンロード完了時にも .done / .done() が維持されること
        viewModel.downloadSelectedModel()
        try await waitUntil { self.viewModel.downloadedModelIDs.contains("base") && !self.viewModel.isBusy }
        XCTAssertEqual(viewModel.uiState, .done)
        XCTAssertEqual(viewModel.progressDisplay, .done())
        XCTAssertEqual(viewModel.currentTranscript?.id, existing.id)
    }

    func testCancelActiveOperationCancelsRunningTranscription() async throws {
        let gate = ProgressGate()
        let mock = MockProgressTranscriber(
            partialTexts: ["途中"],
            finalText: "完了",
            delayNanoseconds: 50_000_000,
            progressGates: [gate]
        )
        viewModel = makeIsolatedViewModel(transcriber: mock)
        configureForTranscription()
        defer { gate.open() }

        viewModel.startTranscription()
        try await waitUntil { self.viewModel.transcriptText == "途中" }
        XCTAssertTrue(viewModel.canCancel)

        viewModel.cancelActiveOperation()
        XCTAssertEqual(viewModel.uiState, .idle)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertNil(viewModel.currentTranscript)
    }

    func testSegmentEditPublishesChangeAndPreservesTranscriptTextAcrossReplacement() {
        viewModel = makeIsolatedViewModel()
        let first = TranscriptSegment(startTime: 0, endTime: 1, text: "先頭")
        let second = TranscriptSegment(startTime: 1, endTime: 2, text: "末尾")
        let transcript = Transcript(sourceFileName: "edit.wav", fullText: "先頭\n末尾", segments: [first, second])
        viewModel.restoreTranscript(transcript)

        var notifications = 0
        let cancellable = viewModel.objectWillChange.sink { _ in notifications += 1 }
        defer { cancellable.cancel() }

        viewModel.updateSegmentText(id: second.id, text: "更新1")
        viewModel.updateSegmentText(id: second.id, text: "更新12")
        XCTAssertEqual(notifications, 2, "連続セグメント編集で変更通知が毎回送出されること")
        XCTAssertEqual(viewModel.transcriptText, "先頭\n更新12")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "先頭\n更新12")
        XCTAssertTrue(viewModel.canExport)

        // 不明 ID では不要な通知を出さない。
        viewModel.updateSegmentText(id: UUID(), text: "無視")
        XCTAssertEqual(notifications, 2)

        // currentTranscript を別インスタンスへ差し替えても transcriptText が空落ちしないこと。
        viewModel.currentTranscript = Transcript(sourceFileName: "other.wav", fullText: "別本文")
        XCTAssertEqual(viewModel.transcriptText, "先頭\n更新12")
    }

    private func configureForTranscription() {
        isolatedSettings.selectedModelID = "base"
        viewModel.selectedFile = AudioFileInfo(
            url: audioURL,
            fileName: audioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        viewModel.downloadedModelIDs = ["base"]
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        pollNanoseconds: UInt64 = 10_000_000,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
        XCTFail("Condition not met within timeout")
    }
}

private struct FailingProgressTranscriber: Transcriber {
    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        throw AppError.transcriptionFailed("Test transcription failure")
    }

    func cancel(jobID: UUID) async {}
}

private final class MockProgressTranscriber: Transcriber, @unchecked Sendable {
    private let partialTexts: [String]
    private let finalText: String
    private let delayNanoseconds: UInt64
    private let finalDelayNanoseconds: UInt64
    private let progressGates: [ProgressGate]
    private var activeTasks: [UUID: Task<Transcript, Error>] = [:]
    private var cancelledJobIDs: Set<UUID> = []
    private let lock = NSLock()
    private var emittedPartialTexts = 0

    init(
        partialTexts: [String],
        finalText: String,
        delayNanoseconds: UInt64,
        finalDelayNanoseconds: UInt64 = 0,
        progressGates: [ProgressGate] = []
    ) {
        self.partialTexts = partialTexts
        self.finalText = finalText
        self.delayNanoseconds = delayNanoseconds
        self.finalDelayNanoseconds = finalDelayNanoseconds
        self.progressGates = progressGates
    }

    var partialTextCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return emittedPartialTexts
    }

    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        try await withTaskCancellationHandler {
            lock.lock()
            if cancelledJobIDs.contains(job.id) {
                lock.unlock()
                throw CancellationError()
            }
            lock.unlock()

            let task = Task<Transcript, Error> {
                for (index, text) in partialTexts.enumerated() {
                    try Task.checkCancellation()
                    lock.lock()
                    let isCancelled = cancelledJobIDs.contains(job.id)
                    lock.unlock()
                    if isCancelled {
                        throw CancellationError()
                    }
                    lock.lock()
                    emittedPartialTexts += 1
                    lock.unlock()
                    progressHandler?(
                        .make(
                            phase: .transcribing,
                            fraction: Double(index + 1) / Double(partialTexts.count + 1),
                            modelDisplayName: job.modelDisplayName,
                            partialText: text
                        )
                    )
                    if index < progressGates.count {
                        await progressGates[index].wait()
                    }
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }

                if finalDelayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: finalDelayNanoseconds)
                }

                try Task.checkCancellation()
                lock.lock()
                let isCancelled = cancelledJobIDs.contains(job.id)
                lock.unlock()
                if isCancelled {
                    throw CancellationError()
                }
                return Transcript(
                    sourceFileName: job.sourceFileName,
                    fullText: finalText
                )
            }

            lock.lock()
            activeTasks[job.id] = task
            lock.unlock()

            defer {
                lock.lock()
                activeTasks.removeValue(forKey: job.id)
                cancelledJobIDs.remove(job.id)
                lock.unlock()
            }

            return try await task.value
        } onCancel: {
            cancel(jobID: job.id)
        }
    }

    func cancel(jobID: UUID) {
        lock.lock()
        cancelledJobIDs.insert(jobID)
        let task = activeTasks[jobID]
        lock.unlock()
        task?.cancel()
    }
}

private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                continuation.resume()
            } else {
                continuations.append(continuation)
            }
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let waiters = continuations
        continuations = []
        lock.unlock()

        for continuation in waiters {
            continuation.resume()
        }
    }
}

private final class DownloadAttemptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
