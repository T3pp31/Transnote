import XCTest
@testable import LocalTranscriber

final class WhisperKitTranscriberTests: XCTestCase {
    private var temporaryRoot: URL!
    private var transcriber: WhisperKitTranscriber!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let availability = ModelAvailabilityService(modelsRoot: temporaryRoot)
        transcriber = WhisperKitTranscriber(modelAvailability: availability)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
        transcriber = nil
    }

    func testTranscribeFailsWhenModelNotDownloaded() async {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-model-test.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let job = TranscriptionJob(
            audioFileURL: audioURL,
            sourceFileName: audioURL.lastPathComponent,
            modelID: "base",
            whisperKitModelName: "base",
            modelDisplayName: "Base",
            languageID: "auto"
        )

        do {
            _ = try await transcriber.transcribe(job)
            XCTFail("Expected modelNotDownloaded error")
        } catch let error as AppError {
            XCTAssertEqual(error, .modelNotDownloaded("Base"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
