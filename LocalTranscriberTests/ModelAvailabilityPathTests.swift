import XCTest
@testable import LocalTranscriber
import WhisperKit

final class ModelAvailabilityPathTests: XCTestCase {
    func testWhisperKitLoadsFromDetectedModelFolder() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_MODEL_INTEGRATION_TESTS"] == "1",
            "Set RUN_MODEL_INTEGRATION_TESTS=1 to run the real-model integration test."
        )

        let modelsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: modelsRoot) }

        let downloadedPath = try await WhisperKit.download(
            variant: "tiny",
            downloadBase: modelsRoot
        ) { _ in }

        let service = ModelAvailabilityService(modelsRoot: modelsRoot)
        let detectedPath = try XCTUnwrap(service.modelFolder(for: "tiny"))
        XCTAssertEqual(
            detectedPath.resolvingSymlinksInPath().standardizedFileURL.path,
            downloadedPath.resolvingSymlinksInPath().standardizedFileURL.path
        )

        let config = WhisperKitConfig(
            model: "tiny",
            modelFolder: detectedPath.path,
            verbose: false,
            logLevel: .error,
            load: true,
            download: false
        )

        _ = try await WhisperKit(config)
    }
}
