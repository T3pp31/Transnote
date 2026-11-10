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
        _ = try await downloadModelForSmokeTest {
            try await downloadService.downloadIfNeeded(
                whisperKitModelName: "tiny",
                modelDisplayName: "Tiny"
            )
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

    func testSmokeModelDownloadReturnsSuccessfulPath() async throws {
        let expected = URL(fileURLWithPath: "/tmp/smoke-test-model", isDirectory: true)
        let path = try await downloadModelForSmokeTest { expected }
        XCTAssertEqual(path, expected)
    }

    func testSmokeModelDownloadSkipsOnlyTransientNetworkErrors() async {
        let codes: [URLError.Code] = [.notConnectedToInternet, .timedOut, .networkConnectionLost]
        for code in codes {
            let errors: [Error] = [
                URLError(code),
                NSError(
                    domain: NSURLErrorDomain,
                    code: code.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "Temporary network outage"]
                )
            ]
            for expected in errors {
                do {
                    _ = try await downloadModelForSmokeTest { throw expected }
                    XCTFail("Expected a skip for \(expected)")
                } catch let skip as XCTSkip {
                    let diagnostic = String(describing: skip)
                    XCTAssertTrue(diagnostic.contains(String(code.rawValue)))
                    XCTAssertTrue(diagnostic.contains(String(describing: expected)))
                } catch {
                    XCTFail("Expected XCTSkip, got \(error)")
                }
            }
        }
    }

    func testSmokeModelDownloadPropagatesOtherURLErrors() async {
        let codes: [URLError.Code] = [
            .badURL, .unsupportedURL, .cannotFindHost, .badServerResponse,
            .secureConnectionFailed, .serverCertificateUntrusted,
            .fileDoesNotExist, .noPermissionsToReadFile, .cannotWriteToFile,
            .cannotDecodeContentData, .cancelled, .unknown
        ]
        for code in codes {
            let expected = URLError(code)
            do {
                _ = try await downloadModelForSmokeTest { throw expected }
                XCTFail("Expected an error for \(code)")
            } catch {
                XCTAssertFalse(error is XCTSkip, "Must not skip \(expected)")
                XCTAssertEqual((error as? URLError)?.code, code)
            }
        }
    }

    func testSmokeModelDownloadPropagatesModelAndFileErrors() async {
        let errors: [Error] = [
            AppError.modelNotDownloaded("missing-model"),
            AppError.transcriptionFailed("Invalid model files"),
            CocoaError(.fileReadCorruptFile),
            CocoaError(.fileWriteOutOfSpace),
            CocoaError(.fileWriteNoPermission),
            CancellationError(),
            NSError(domain: "SmokeTest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Model network configuration is invalid"
            ])
        ]
        for expected in errors {
            do {
                _ = try await downloadModelForSmokeTest { throw expected }
                XCTFail("Expected an error for \(expected)")
            } catch {
                XCTAssertFalse(error is XCTSkip, "Must not skip \(expected)")
                let actual = error as NSError
                let original = expected as NSError
                XCTAssertEqual(actual.domain, original.domain)
                XCTAssertEqual(actual.code, original.code)
                XCTAssertEqual(actual.localizedDescription, original.localizedDescription)
            }
        }
    }

    /// スキップを一時的な通信断に限定し、モデルや保存先の異常はテスト失敗として伝播する。
    /// クロージャ注入により、fixture・ネットワークなしで実際の変換経路を検証する。
    private func downloadModelForSmokeTest(_ download: () async throws -> URL) async throws -> URL {
        do {
            return try await download()
        } catch {
            guard let urlError = error as? URLError else { throw error }
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost:
                throw XCTSkip("Model download temporarily unavailable (URLError \(urlError.code.rawValue)): \(error)")
            default:
                throw error
            }
        }
    }
}
