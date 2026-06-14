import XCTest
@testable import LocalTranscriber
import WhisperKit

final class ModelAvailabilityPathTests: XCTestCase {
    func testModelFolderPointsToVariantDirectoryNotParentHubFolder() throws {
        let modelsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: modelsRoot) }

        let hubRoot = modelsRoot
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: hubRoot, withIntermediateDirectories: true)

        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = hubRoot.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        let service = ModelAvailabilityService(modelsRoot: modelsRoot)
        let folder = service.modelFolder(for: "base")

        XCTAssertEqual(folder?.lastPathComponent, "openai_whisper-base")
    }

    func testWhisperKitLoadsFromDetectedModelFolder() async throws {
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
        XCTAssertEqual(detectedPath.path, downloadedPath.path)

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
