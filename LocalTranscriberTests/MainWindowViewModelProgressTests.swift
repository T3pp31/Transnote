import XCTest
@testable import LocalTranscriber

@MainActor
final class MainWindowViewModelProgressTests: XCTestCase {
    private var audioURL: URL!
    private var viewModel: MainWindowViewModel!

    override func setUpWithError() throws {
        audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data(count: 64))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: audioURL)
    }

    func testPartialTextUpdatesDuringTranscription() async throws {
        // Given: partialText を2回 emit する Mock Transcriber
        let mock = MockProgressTranscriber(
            partialTexts: ["Hello", "Hello world"],
            finalText: "Hello world final",
            delayNanoseconds: 50_000_000
        )
        viewModel = MainWindowViewModel(transcriber: mock)
        configureForTranscription()

        // When
        viewModel.startTranscription()

        // Then: 1回目の partialText が反映される
        try await waitUntil { self.viewModel.transcriptText == "Hello" }
        XCTAssertEqual(viewModel.uiState, .transcribing)
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertFalse(viewModel.canExport)

        // Then: 2回目の partialText が反映される
        try await waitUntil { self.viewModel.transcriptText == "Hello world" }
        XCTAssertFalse(viewModel.canExport)

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
        viewModel = MainWindowViewModel(transcriber: mock)
        configureForTranscription()

        viewModel.startTranscription()

        try await waitUntil { self.viewModel.uiState == .transcribing }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(viewModel.transcriptText, "")
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
        viewModel = MainWindowViewModel(transcriber: mock)
        configureForTranscription()
        viewModel.transcriptText = "previous result"
        viewModel.currentTranscript = Transcript(
            sourceFileName: "old.wav",
            fullText: "previous result"
        )

        // When
        viewModel.startTranscription()

        // Then: 開始直後に前回結果がクリアされる
        XCTAssertEqual(viewModel.transcriptText, "")
        XCTAssertNil(viewModel.currentTranscript)
        XCTAssertFalse(viewModel.canExport)

        try await waitUntil { self.viewModel.uiState == .done }
        XCTAssertEqual(viewModel.transcriptText, "new result")
    }

    private func configureForTranscription() {
        AppSettings.shared.selectedModelID = "base"
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

private final class MockProgressTranscriber: Transcriber, @unchecked Sendable {
    private let partialTexts: [String]
    private let finalText: String
    private let delayNanoseconds: UInt64
    private let finalDelayNanoseconds: UInt64
    private var activeTasks: [UUID: Task<Transcript, Error>] = [:]
    private let lock = NSLock()

    init(
        partialTexts: [String],
        finalText: String,
        delayNanoseconds: UInt64,
        finalDelayNanoseconds: UInt64 = 0
    ) {
        self.partialTexts = partialTexts
        self.finalText = finalText
        self.delayNanoseconds = delayNanoseconds
        self.finalDelayNanoseconds = finalDelayNanoseconds
    }

    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        let task = Task<Transcript, Error> {
            for (index, text) in partialTexts.enumerated() {
                try Task.checkCancellation()
                progressHandler?(
                    .make(
                        phase: .transcribing,
                        fraction: Double(index + 1) / Double(partialTexts.count + 1),
                        modelDisplayName: job.modelDisplayName,
                        partialText: text
                    )
                )
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }

            if finalDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: finalDelayNanoseconds)
            }

            try Task.checkCancellation()
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
            lock.unlock()
        }

        return try await task.value
    }

    func cancel(jobID: UUID) {
        lock.lock()
        let task = activeTasks[jobID]
        lock.unlock()
        task?.cancel()
    }
}
