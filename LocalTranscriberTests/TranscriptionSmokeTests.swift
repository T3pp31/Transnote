import XCTest
@testable import LocalTranscriber

final class TranscriptionSmokeTests: XCTestCase {
    private var fixtureURL: URL? {
        let bundle = Bundle(for: TranscriptionSmokeTests.self)
        if let url = bundle.url(forResource: "sample", withExtension: "wav") {
            return url
        }

        let candidates = [
            URL(fileURLWithPath: "Fixtures/sample.wav"),
            URL(fileURLWithPath: "LocalTranscriberTests/Fixtures/sample.wav")
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    func testSmokeTranscriptionWithFixtureIfAvailable() async throws {
        guard let audioURL = fixtureURL else {
            throw XCTSkip("No local audio fixture available. Add LocalTranscriberTests/Fixtures/sample.wav to run this test.")
        }

        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_WHISPER_SMOKE_TEST"] == "1",
            "Set RUN_WHISPER_SMOKE_TEST=1 to run the real-model smoke test."
        )

        let transcriber = WhisperKitTranscriber()
        let downloadService = ModelDownloadService()
        do {
            _ = try await downloadService.downloadIfNeeded(
                whisperKitModelName: "tiny",
                modelDisplayName: "Tiny"
            )
        } catch {
            throw XCTSkip("Model download failed: \(error)")
        }

        let job = TranscriptionJob(
            audioFileURL: audioURL,
            sourceFileName: audioURL.lastPathComponent,
            modelID: "tiny",
            whisperKitModelName: "tiny",
            modelDisplayName: "Tiny",
            languageID: "auto"
        )

        let transcript = try await transcriber.transcribe(job)

        XCTAssertFalse(transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(transcript.segments.isEmpty)
    }
}
