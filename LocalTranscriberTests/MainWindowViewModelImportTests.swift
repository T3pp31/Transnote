import XCTest
@testable import LocalTranscriber

@MainActor
final class MainWindowViewModelImportTests: XCTestCase {
    private var importsRoot: URL!
    private var sourceRoot: URL!
    private var originalSelectedModelID: String!
    private var viewModel: MainWindowViewModel!

    override func setUpWithError() throws {
        originalSelectedModelID = AppSettings.shared.selectedModelID
        importsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        viewModel = MainWindowViewModel(
            audioImportService: AudioImportService(importsRoot: importsRoot)
        )
    }

    override func tearDownWithError() throws {
        AppSettings.shared.selectedModelID = originalSelectedModelID
        try? FileManager.default.removeItem(at: importsRoot)
        try? FileManager.default.removeItem(at: sourceRoot)
    }

    func testSelectFileImportsExtensionlessM4APlaceholderName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertTrue(viewModel.selectedFile?.fileName.hasSuffix(".m4a") == true)
        XCTAssertTrue(
            viewModel.selectedFile?.url.path.hasPrefix(importsRoot.path) == true
        )
    }

    func testSelectFileRejectsUnresolvablePlaceholderNameAndPreservesPreviousResult() throws {
        let existingURL = sourceRoot.appendingPathComponent("previous.wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: existingURL.path, contents: Data("prev".utf8)))
        viewModel.selectFile(url: existingURL)
        let previousSelected = try XCTUnwrap(viewModel.selectedFile)

        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        XCTAssertTrue(FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8)))

        viewModel.selectFile(url: sourceURL)

        XCTAssertEqual(viewModel.errorMessage, AppError.unsupportedFileExtension("unknown").errorDescription)
        XCTAssertEqual(viewModel.selectedFile, previousSelected)
    }

    func testSelectFileRemovesPreviousSandboxCopyInInjectedImportsRoot() throws {
        let firstSource = sourceRoot.appendingPathComponent("first.wav")
        let secondSource = sourceRoot.appendingPathComponent("second.wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: firstSource.path, contents: Data("first".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: secondSource.path, contents: Data("second".utf8)))

        viewModel.selectFile(url: firstSource)
        let firstImported = try XCTUnwrap(viewModel.selectedFile?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstImported.path))

        viewModel.selectFile(url: secondSource)
        let secondImported = try XCTUnwrap(viewModel.selectedFile?.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstImported.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondImported.path))
    }

    func testSelectFileImportsPlaceholderDropNameWithDropPreferredFileName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8))

        viewModel.selectFile(url: sourceURL, preferredFileName: "recording.m4a")

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertEqual(viewModel.selectedFile?.fileName, "recording.m4a")
    }

    func testSelectFileImportsPlaceholderDropNameWithM4AContent() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertEqual(viewModel.selectedFile?.fileName, "imported-audio.m4a")
    }

    private func seedExistingTranscriptResult() {
        viewModel.currentTranscript = Transcript(
            sourceFileName: "old.wav",
            fullText: "existing text"
        )
        viewModel.transcriptText = "existing text"
    }

    func testSelectFileAppliesImmediatelyWhenThereIsNoExistingResult() throws {
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertNotNil(viewModel.selectedFile)
    }

    func testSelectFileAwaitsConfirmationWhenAnExistingResultIsPresent() throws {
        seedExistingTranscriptResult()
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        let previousFile = viewModel.selectedFile

        viewModel.selectFile(url: sourceURL)

        // Confirmation is pending, file not switched yet
        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertNotNil(viewModel.pendingFileImport)
        XCTAssertEqual(viewModel.selectedFile, previousFile)
        XCTAssertEqual(viewModel.transcriptText, "existing text")
    }

    func testApplyPendingFileImportReplacesResultAfterConfirmation() throws {
        seedExistingTranscriptResult()
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)
        viewModel.applyPendingFileImport()

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertEqual(viewModel.transcriptText, "")
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertNil(viewModel.transcriptionTask)
        XCTAssertFalse(viewModel.isBusy)
    }

    func testCancelPendingFileImportKeepsExistingResult() throws {
        seedExistingTranscriptResult()
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        let previousFile = viewModel.selectedFile

        viewModel.selectFile(url: sourceURL)
        viewModel.cancelPendingFileImport()

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertEqual(viewModel.selectedFile, previousFile)
        XCTAssertEqual(viewModel.transcriptText, "existing text")
    }

    // MARK: - transcription restart confirmation regression (#703)

    func testConfirmedTranscriptionRestartUsesSelectedFileWithoutPendingImport() async throws {
        // saveTemporary は historyRoot に関係なく固定パスへ書くため、既存データを保存・復元する。
        let recoveryURL = AppDirectories.tempTranscriptsDirectory.appendingPathComponent("recovery.json")
        let recoveryData: Data?
        if FileManager.default.fileExists(atPath: recoveryURL.path) {
            recoveryData = try Data(contentsOf: recoveryURL)
        } else {
            recoveryData = nil
        }
        defer {
            if let recoveryData {
                try? recoveryData.write(to: recoveryURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: recoveryURL)
            }
        }
        let gate = AsyncGate()
        defer { gate.open() }
        let selectedFile = try prepareTranscriptionRestart(gate: gate)
        viewModel.transcriptText = "edited text"

        viewModel.startTranscription()

        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertNil(viewModel.transcriptionTask)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertEqual(viewModel.transcriptText, "edited text")
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "existing text")

        viewModel.applyPendingFileImport()

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertEqual(viewModel.selectedFile, selectedFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: selectedFile.url.path))
        XCTAssertTrue(viewModel.isBusy)
        XCTAssertEqual(viewModel.uiState, .preparing)
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertEqual(viewModel.transcriptText, "")
        let task = try XCTUnwrap(viewModel.transcriptionTask)

        gate.open()
        await task.value

        XCTAssertEqual(viewModel.uiState, .done)
        XCTAssertEqual(viewModel.currentTranscript?.sourceFileName, selectedFile.fileName)
        XCTAssertEqual(viewModel.transcriptText, "done")
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertNil(viewModel.transcriptionTask)

        // 承認は今回の再実行にだけ有効で、次回は再び確認する。
        viewModel.startTranscription()
        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.transcriptionTask)
        XCTAssertEqual(viewModel.transcriptText, "done")
        viewModel.cancelPendingFileImport()
    }

    func testApplyPendingFileImportDoesNotRestartTranscriptionWhenImportFails() throws {
        let gate = AsyncGate()
        defer { gate.open() }
        let selectedFile = try prepareTranscriptionRestart(gate: gate)
        // 未保存の編集が失われないことを検証するため、baseline と異なる内容にする。
        viewModel.transcriptText = "edited text"

        viewModel.startTranscription()
        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)

        // インポート元が存在しないため、applyFileImport は失敗する。
        viewModel.selectFile(url: sourceRoot.appendingPathComponent("missing.wav"))
        XCTAssertNotNil(viewModel.pendingFileImport)

        viewModel.applyPendingFileImport()

        XCTAssertNil(viewModel.transcriptionTask, "インポート失敗後に旧ファイルの文字起こしを開始しないこと")
        XCTAssertEqual(viewModel.selectedFile, selectedFile)
        XCTAssertEqual(viewModel.currentTranscript?.fullText, "existing text")
        XCTAssertEqual(viewModel.transcriptText, "edited text", "未保存の編集を保持すること")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: selectedFile.url.path),
            "インポート失敗時に旧ファイルの sandbox コピーを削除しないこと"
        )
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testCancelledTranscriptionRestartKeepsResultAndRequiresConfirmationAgain() throws {
        let gate = AsyncGate()
        defer { gate.open() }
        let selectedFile = try prepareTranscriptionRestart(gate: gate)
        let transcriptID = viewModel.currentTranscript?.id
        viewModel.transcriptText = "edited text"

        viewModel.startTranscription()
        viewModel.cancelPendingFileImport()
        // キャンセル後に承認処理が呼ばれても再実行しない。
        viewModel.applyPendingFileImport()

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertNil(viewModel.transcriptionTask)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertEqual(viewModel.selectedFile, selectedFile)
        XCTAssertEqual(viewModel.currentTranscript?.id, transcriptID)
        XCTAssertEqual(viewModel.transcriptText, "edited text")

        viewModel.startTranscription()
        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.transcriptionTask)
        viewModel.cancelPendingFileImport()
    }

    func testHandleImportsClearedClearsSelectionUnderImportsDirectory() throws {
        let importsDirectory = AppDirectories.importsDirectory
        let copiedURL = importsDirectory.appendingPathComponent("cleared-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: copiedURL) }
        try Data("audio".utf8).write(to: copiedURL)

        viewModel.selectedFile = AudioFileInfo(
            url: copiedURL,
            fileName: copiedURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 5,
            formattedFileSize: "5 bytes"
        )
        AppSettings.shared.selectedModelID = "base"
        viewModel.downloadedModelIDs = ["base"]
        XCTAssertTrue(viewModel.canStartTranscription)

        viewModel.playingSegmentID = UUID()
        viewModel.isSegmentPaused = true
        try FileManager.default.removeItem(at: copiedURL)
        viewModel.handleImportsCleared()

        XCTAssertNil(viewModel.selectedFile)
        XCTAssertNil(viewModel.playingSegmentID)
        XCTAssertFalse(viewModel.isSegmentPaused)
        XCTAssertFalse(viewModel.canStartTranscription)
        XCTAssertEqual(
            viewModel.startTranscriptionDisabledReason,
            L("音声ファイルを選択してください", comment: "Select an audio file")
        )
    }

    func testCannotStartTranscriptionWhenSelectedFileWasDeleted() throws {
        let externalURL = sourceRoot.appendingPathComponent("deleted.wav")
        try Data("audio".utf8).write(to: externalURL)
        viewModel.selectedFile = AudioFileInfo(
            url: externalURL,
            fileName: externalURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 5,
            formattedFileSize: "5 bytes"
        )
        AppSettings.shared.selectedModelID = "base"
        viewModel.downloadedModelIDs = ["base"]
        XCTAssertTrue(viewModel.canStartTranscription)

        try FileManager.default.removeItem(at: externalURL)

        XCTAssertNotNil(viewModel.selectedFile)
        XCTAssertFalse(viewModel.canStartTranscription)
        XCTAssertEqual(
            viewModel.startTranscriptionDisabledReason,
            L("音声ファイルを選択してください", comment: "Select an audio file")
        )
    }

    func testHandleImportsClearedKeepsSelectionOutsideImportsDirectory() throws {
        let externalURL = sourceRoot.appendingPathComponent("external.wav")
        try Data("audio".utf8).write(to: externalURL)
        viewModel.selectedFile = AudioFileInfo(
            url: externalURL,
            fileName: externalURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 5,
            formattedFileSize: "5 bytes"
        )

        viewModel.handleImportsCleared()

        XCTAssertEqual(viewModel.selectedFile?.url, externalURL)
    }

    func testConfirmedTranscriptionRestartStillRequiresDownloadedModel() throws {
        let gate = AsyncGate()
        defer { gate.open() }
        _ = try prepareTranscriptionRestart(gate: gate)
        let transcriptID = viewModel.currentTranscript?.id

        viewModel.startTranscription()
        viewModel.downloadedModelIDs = []
        viewModel.applyPendingFileImport()

        XCTAssertFalse(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.pendingFileImport)
        XCTAssertNil(viewModel.transcriptionTask)
        XCTAssertFalse(viewModel.isBusy)
        XCTAssertNotNil(viewModel.inlineErrorMessage)
        XCTAssertEqual(viewModel.currentTranscript?.id, transcriptID)
        XCTAssertEqual(viewModel.transcriptText, "existing text")

        // 開始できなかった場合にも承認状態を持ち越さない。
        viewModel.downloadedModelIDs = ["base"]
        viewModel.startTranscription()
        XCTAssertTrue(viewModel.confirmFileImport)
        XCTAssertNil(viewModel.transcriptionTask)
        viewModel.cancelPendingFileImport()
    }

    private func prepareTranscriptionRestart(gate: AsyncGate) throws -> AudioFileInfo {
        viewModel = MainWindowViewModel(
            transcriber: MockTranscriber(gate: gate),
            audioImportService: AudioImportService(importsRoot: importsRoot),
            historyStore: HistoryStore(historyRoot: importsRoot.appendingPathComponent("history"))
        )
        AppSettings.shared.selectedModelID = "base"
        viewModel.downloadedModelIDs = ["base"]
        let sourceURL = sourceRoot.appendingPathComponent("restart.wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: sourceURL.path, contents: Data("audio".utf8)))
        viewModel.selectFile(url: sourceURL)
        let selectedFile = try XCTUnwrap(viewModel.selectedFile)
        viewModel.restoreTranscript(Transcript(sourceFileName: selectedFile.fileName, fullText: "existing text"))
        return selectedFile
    }

    // MARK: - file change race regression (#246)

    func testFileSelectionIsIgnoredWhileTranscriptionIsRunning() async throws {
        let gate = AsyncGate()
        let transcriber = MockTranscriber(gate: gate)
        let vm = MainWindowViewModel(
            transcriber: transcriber,
            audioImportService: AudioImportService(importsRoot: importsRoot)
        )

        AppSettings.shared.selectedModelID = "base"
        vm.downloadedModelIDs = ["base"]
        let sourceURL = sourceRoot.appendingPathComponent("race.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("audio".utf8))
        vm.selectFile(url: sourceURL)

        vm.startTranscription()
        XCTAssertTrue(vm.isBusy)

        let before = vm.selectedFile?.url
        let replacement = sourceRoot.appendingPathComponent("other.wav")
        FileManager.default.createFile(atPath: replacement.path, contents: Data("x".utf8))
        vm.selectFile(url: replacement)

        XCTAssertEqual(vm.selectedFile?.url, before)
        gate.open()

        try await waitUntil { !vm.isBusy }
        XCTAssertEqual(vm.currentTranscript?.fullText, "done")
        XCTAssertEqual(vm.transcriptText, "done")
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

    func testAsyncGateOpenBeforeWaitResumesLaterWaiter() async {
        let gate = AsyncGate()
        gate.open()

        await gate.wait()
    }
    func testStaleSuccessfulTaskDoesNotClearNewOperation() async throws {
        try await assertStaleTaskIsIgnored(completion: .success("stale"))
    }

    func testStaleFailedTaskDoesNotClearNewOperation() async throws {
        try await assertStaleTaskIsIgnored(completion: .failure)
    }

    func testStaleCancelledTaskDoesNotClearNewOperation() async throws {
        try await assertStaleTaskIsIgnored(completion: .cancelled)
    }

    func testStaleTaskCannotOverwriteCompletedNewTranscript() async throws {
        try await assertStaleTaskIsIgnored(completion: .success("stale"), completeNewFirst: true)
    }

    private func assertStaleTaskIsIgnored(
        completion: SequentialGateTranscriber.Completion,
        completeNewFirst: Bool = false
    ) async throws {
        let oldGate = AsyncGate()
        let newGate = AsyncGate()
        defer {
            oldGate.open()
            newGate.open()
        }
        let oldStarted = expectation(description: "Old transcription started")
        let newStarted = expectation(description: "New transcription started")
        let transcriber = SequentialGateTranscriber(
            gates: [oldGate, newGate],
            started: [oldStarted, newStarted],
            completions: [completion, .success("new result")]
        )
        let vm = MainWindowViewModel(
            transcriber: transcriber,
            audioImportService: AudioImportService(importsRoot: importsRoot),
            historyStore: HistoryStore(historyRoot: importsRoot.appendingPathComponent("history"))
        )

        AppSettings.shared.selectedModelID = "base"
        vm.downloadedModelIDs = ["base"]
        let sourceURL = sourceRoot.appendingPathComponent("stale-task.wav")
        XCTAssertTrue(FileManager.default.createFile(atPath: sourceURL.path, contents: Data("audio".utf8)))
        vm.selectFile(url: sourceURL)

        vm.startTranscription()
        let oldTask = try XCTUnwrap(vm.transcriptionTask)
        await fulfillment(of: [oldStarted], timeout: 5)
        vm.cancelTranscription()
        XCTAssertFalse(vm.isBusy)

        vm.startTranscription()
        let newTask = try XCTUnwrap(vm.transcriptionTask)
        await fulfillment(of: [newStarted], timeout: 5)
        XCTAssertTrue(vm.isBusy)

        if completeNewFirst {
            newGate.open()
            await newTask.value
        }

        oldGate.open()
        // ViewModel側の後処理まで待ち、yield回数やスケジューラに依存しない。
        await oldTask.value
        XCTAssertEqual(vm.isBusy, !completeNewFirst)
        XCTAssertEqual(vm.currentTranscript?.fullText, completeNewFirst ? "new result" : nil)
        XCTAssertNil(vm.errorMessage)

        newGate.open()
        await newTask.value
        XCTAssertFalse(vm.isBusy)
        XCTAssertEqual(vm.currentTranscript?.fullText, "new result")
        XCTAssertEqual(vm.transcriptText, "new result")
        XCTAssertNil(vm.transcriptionTask)
    }

}

// 完了を待機できる非同期ゲート
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                cont.resume()
            } else {
                continuations.append(cont)
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

// テスト用の Transcriber モック
final class MockTranscriber: Transcriber, @unchecked Sendable {
    private let gate: AsyncGate
    init(gate: AsyncGate) { self.gate = gate }
    func transcribe(_ job: TranscriptionJob, progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?) async throws -> Transcript {
        await gate.wait()
        return Transcript(sourceFileName: job.sourceFileName, fullText: "done")
    }
    func cancel(jobID: UUID) {}
}


private actor SequentialGateTranscriber: Transcriber {
    enum Completion: Sendable {
        case success(String)
        case failure
        case cancelled
    }

    private struct TestFailure: Error {}
    private let gates: [AsyncGate]
    private let started: [XCTestExpectation]
    private let completions: [Completion]
    private var nextIndex = 0

    init(gates: [AsyncGate], started: [XCTestExpectation], completions: [Completion]) {
        self.gates = gates
        self.started = started
        self.completions = completions
    }

    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        let index = nextIndex
        nextIndex += 1
        started[index].fulfill()
        await gates[index].wait()
        switch completions[index] {
        case .success(let text):
            return Transcript(sourceFileName: job.sourceFileName, fullText: text)
        case .failure:
            throw TestFailure()
        case .cancelled:
            throw CancellationError()
        }
    }

    func cancel(jobID: UUID) {}
}
