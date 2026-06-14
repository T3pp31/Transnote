import XCTest
@testable import LocalTranscriber
import WhisperKit

final class ModelDownloadIntegrationTests: XCTestCase {
    func testDownloadTinyModelToAppModelsDirectory() async throws {
        let modelsRoot = AppDirectories.modelsDirectory
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)

        let service = ModelDownloadService(modelsRoot: modelsRoot)
        let path = try await service.downloadIfNeeded(
            whisperKitModelName: "tiny",
            modelDisplayName: "Tiny"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        let availability = ModelAvailabilityService(modelsRoot: modelsRoot)
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "tiny"))
    }

    func testDownloadTinyModelFromHub() async throws {
        let modelsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: modelsRoot) }

        let service = ModelDownloadService(modelsRoot: modelsRoot)
        let path = try await service.downloadIfNeeded(
            whisperKitModelName: "tiny",
            modelDisplayName: "Tiny"
        ) { update in
            print("DL progress: \(update.fraction)")
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        let availability = ModelAvailabilityService(modelsRoot: modelsRoot)
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "tiny"))
    }
}
