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
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
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

    func testCleanUpFailedDownloadRemovesNewlyCreatedVariantFolderOnly() throws {
        // Given: ダウンロード開始前に存在していた既存の完全なモデルフォルダ（削除してはならない）
        let existingFolder = temporaryRoot
            .appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = existingFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // Given: ダウンロード開始時点のスナップショット（既存モデルフォルダのみ）
        let directoriesBeforeDownload = Set(
            availability.variantDirectories(named: "base").map { $0.path }
        )
        XCTAssertEqual(directoriesBeforeDownload.count, 1)
        XCTAssertTrue(
            directoriesBeforeDownload.contains { $0.hasSuffix("models/openai_whisper-base") }
        )

        // Given: ダウンロード失敗で新規生成された部分フォルダ（削除対象）
        let partialFolder = temporaryRoot
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: partialFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = partialFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When: ダウンロード失敗時のクリーンアップを実行
        service.cleanUpFailedDownload(
            whisperKitModelName: "base",
            directoriesBeforeDownload: directoriesBeforeDownload
        )

        // Then: 新規生成された部分フォルダだけが削除される
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialFolder.path))

        // Then: 既存の完全なモデルフォルダは保持される
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFolder.path))
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
    }

    func testCleanUpFailedDownloadRemovesNewlyCreatedHiddenStagingFolder() throws {
        // Given: ダウンロード開始前に隠しステージングは存在しない
        let directoriesBeforeDownload = Set(
            availability.variantDirectories(named: "base", includingHidden: true).map { $0.path }
        )
        XCTAssertTrue(directoriesBeforeDownload.isEmpty)

        // Given: 失敗した WhisperKit ダウンロードが .cache 配下に残した部分フォルダ
        let stagingFolder = temporaryRoot.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = stagingFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        service.cleanUpFailedDownload(
            whisperKitModelName: "base",
            directoriesBeforeDownload: directoriesBeforeDownload
        )

        // Then: 選択候補からは除外しつつ、クリーンアップでは削除できる
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingFolder.path))
    }

    func testCleanUpFailedDownloadPreservesHiddenStagingFolderThatExistedBeforeDownload() throws {
        // Given: ダウンロード開始前から存在する隠しステージングフォルダ（削除してはならない）
        let existingStaging = temporaryRoot.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: existingStaging, withIntermediateDirectories: true)

        let directoriesBeforeDownload = Set(
            availability.variantDirectories(named: "base", includingHidden: true).map { $0.path }
        )
        XCTAssertTrue(directoriesBeforeDownload.contains { $0.hasSuffix("openai_whisper-base") })

        // When: 失敗クリーンアップ
        service.cleanUpFailedDownload(
            whisperKitModelName: "base",
            directoriesBeforeDownload: directoriesBeforeDownload
        )

        // Then: 事前存在していた隠しフォルダは残る
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingStaging.path))
    }
}
