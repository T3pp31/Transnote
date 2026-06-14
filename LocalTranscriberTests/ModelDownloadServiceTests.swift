import XCTest
@testable import LocalTranscriber

final class ModelDownloadServiceTests: XCTestCase {
    private var temporaryRoot: URL!
    private var service: ModelDownloadService!
    private var availability: ModelAvailabilityService!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        availability = ModelAvailabilityService(modelsRoot: temporaryRoot)
        service = ModelDownloadService(modelsRoot: temporaryRoot, modelAvailability: availability)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
        service = nil
        availability = nil
    }

    func testDownloadIfNeededReturnsExistingPathWithoutNetwork() async throws {
        let variantFolder = temporaryRoot
            .appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = variantFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        let path = try await service.downloadIfNeeded(
            whisperKitModelName: "base",
            modelDisplayName: "Base"
        )

        XCTAssertEqual(
            path.resolvingSymlinksInPath().path,
            variantFolder.resolvingSymlinksInPath().path
        )
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
    }
}
