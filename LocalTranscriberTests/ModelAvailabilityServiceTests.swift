import XCTest
@testable import LocalTranscriber

final class ModelAvailabilityServiceTests: XCTestCase {
    private var temporaryRoot: URL!
    private var service: ModelAvailabilityService!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        service = ModelAvailabilityService(modelsRoot: temporaryRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
        service = nil
    }

    func testIsDownloadedReturnsFalseWhenDirectoryMissing() {
        // Given: 空の一時ディレクトリ
        // When: モデル存在を確認
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: 未ダウンロード
        XCTAssertFalse(result)
    }

    func testIsDownloadedReturnsFalseWhenVariantPathMissing() {
        // Given: 必須ファイルのない variant フォルダ
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try? FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then
        XCTAssertFalse(result)
    }

    func testIsDownloadedReturnsTrueWhenRequiredModelsExist() throws {
        // Given: 必須 CoreML ファイルを含む variant フォルダ
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = variantFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then
        XCTAssertTrue(result)
        XCTAssertNotNil(service.modelFolder(for: "base"))
    }

    func testModelFolderIgnoresParentWhenModelsAreOnlyInChildDirectory() throws {
        // Given: 親フォルダにはモデルがなく、子フォルダのみに配置
        let parentFolder = temporaryRoot.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        let childFolder = parentFolder.appendingPathComponent("openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = childFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        let folder = service.modelFolder(for: "base")

        // Then: 親ではなく variant フォルダを返す
        XCTAssertEqual(folder?.lastPathComponent, "openai_whisper-base")
    }

    func testShortVariantNameDoesNotMatchUnrelatedDirectory() throws {
        // Given: "base" を含む無関係ディレクトリに必須モデルファイルを配置
        let decoyFolder = temporaryRoot.appendingPathComponent("models/database", isDirectory: true)
        try FileManager.default.createDirectory(at: decoyFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = decoyFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: "database" は "base" を含むがハイフン区切りではないためマッチしない
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "base"))
    }

    func testShortVariantNameDoesNotMatchSuffixWithoutHyphen() throws {
        // Given: "tiny" で終わるがハイフン区切りではない無関係ディレクトリ
        let decoyFolder = temporaryRoot.appendingPathComponent("models/itiny", isDirectory: true)
        try FileManager.default.createDirectory(at: decoyFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = decoyFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "tiny")

        // Then: "itiny" は "tiny" で終わるがハイフン区切りではないためマッチしない
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "tiny"))
    }
}
