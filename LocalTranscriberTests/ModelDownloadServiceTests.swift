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

    func testDeleteModelInvalidatesCachedDirectoriesAndPreservesOtherModels() throws {
        let baseFolder = try makeModelFolder("openai_whisper-base")
        let tinyFolder = try makeModelFolder("openai_whisper-tiny")

        // 削除前に候補ディレクトリのキャッシュを構築する。
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
        XCTAssertEqual(availability.variantDirectories(named: "base").count, 1)

        try service.deleteModel(whisperKitModelName: "base")

        XCTAssertFalse(FileManager.default.fileExists(atPath: baseFolder.path))
        // modelFolder は毎回必須ファイルを検証するため、nil の確認だけでは
        // キャッシュ無効化漏れを検出できない。候補一覧からも即時に除外されることを確認する。
        XCTAssertTrue(availability.variantDirectories(named: "base").isEmpty)
        XCTAssertNil(availability.modelFolder(for: "base"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tinyFolder.path))
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "tiny"))
    }

    func testDeleteModelDoesNothingWhenModelIsNotDownloaded() throws {
        let tinyFolder = try makeModelFolder("openai_whisper-tiny")
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "tiny"))

        XCTAssertNoThrow(try service.deleteModel(whisperKitModelName: "base"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: tinyFolder.path))
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "tiny"))
        XCTAssertNil(availability.modelFolder(for: "base"))
    }

    func testDeleteModelPropagatesRemovalErrorAndPreservesModel() throws {
        let folder = try makeModelFolder("openai_whisper-base")
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
        let failingService = ModelDownloadService(
            modelsRoot: temporaryRoot,
            modelAvailability: availability,
            fileManager: ModelDeletionFailingFileManager()
        )

        XCTAssertThrowsError(try failingService.deleteModel(whisperKitModelName: "base")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(nsError.code, NSFileWriteNoPermissionError)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
    }

    private func makeModelFolder(_ name: String) throws -> URL {
        let folder = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for modelName in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try Data("model".utf8).write(to: folder.appendingPathComponent("\(modelName).mlmodelc"))
        }
        return folder
    }

    func testDiskSpaceCheckRejectsZeroAndOtherCapacitiesBelowMinimum() {
        let minimumRequired: Int64 = 5 * 1024 * 1024 * 1024
        for available in [0, -1, 1, minimumRequired - 1] {
            XCTAssertThrowsError(
                try ModelDownloadService.ensureEnoughDiskSpace(availableCapacity: available),
                "Expected insufficient disk space for \(available) bytes"
            ) { error in
                guard case AppError.transcriptionFailed(let message) = error else {
                    XCTFail("Expected transcriptionFailed, got \(error)")
                    return
                }
                XCTAssertEqual(
                    message,
                    L("モデルのダウンロードに必要な空き容量が不足しています。ディスクの空き容量を確認してください。")
                )
            }
        }
    }

    func testDiskSpaceCheckAcceptsMinimumOrGreaterCapacity() {
        let minimumRequired: Int64 = 5 * 1024 * 1024 * 1024
        for available in [minimumRequired, minimumRequired + 1, Int64.max] {
            XCTAssertNoThrow(
                try ModelDownloadService.ensureEnoughDiskSpace(availableCapacity: available),
                "Expected sufficient disk space for \(available) bytes"
            )
        }
    }

    func testDiskSpaceCheckSkipsUnavailableCapacity() {
        XCTAssertNoThrow(try ModelDownloadService.ensureEnoughDiskSpace(availableCapacity: nil))
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

    func testValidateModelFolderRejectsBundleWithZeroBytePayload() throws {
        let partialFolder = temporaryRoot.appendingPathComponent("openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: partialFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let bundle = partialFolder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let payload = bundle.appendingPathComponent("coremldata.bin")
            FileManager.default.createFile(atPath: payload.path, contents: Data())
            let filler = bundle.appendingPathComponent("weights.bin")
            FileManager.default.createFile(atPath: filler.path, contents: Data(count: 200 * 1024))
        }

        XCTAssertFalse(availability.validateModelFolder(partialFolder))
        XCTAssertFalse(availability.isDownloaded(whisperKitModelName: "base"))
    }

    func testValidateModelFolderAcceptsBundleWithNonZeroPayloadAndSize() throws {
        let completeFolder = temporaryRoot.appendingPathComponent("openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: completeFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let bundle = completeFolder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let payload = bundle.appendingPathComponent("coremldata.bin")
            FileManager.default.createFile(atPath: payload.path, contents: Data("coreml".utf8))
            let filler = bundle.appendingPathComponent("weights.bin")
            FileManager.default.createFile(atPath: filler.path, contents: Data(count: 200 * 1024))
        }

        XCTAssertTrue(availability.validateModelFolder(completeFolder))
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

    func testDownloadIfNeededCleansUpNewlyCreatedPartialAndHiddenStagingOnRetryExhaustion() async throws {
        // Given: ダウンロード前から存在する他モデルと既存隠しステージング
        let unrelatedModel = try makeModelFolder("openai_whisper-tiny")
        let preExistingHidden = temporaryRoot.appendingPathComponent(
            ".cache/existing/openai_whisper-base",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: preExistingHidden, withIntermediateDirectories: true)

        let attempts = AttemptCounter()
        let createdPartial = temporaryRoot.appendingPathComponent(
            "models/argmaxinc/whisperkit-coreml/openai_whisper-base",
            isDirectory: true
        )
        let createdHidden = temporaryRoot.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base",
            isDirectory: true
        )

        let service = ModelDownloadService(
            modelsRoot: temporaryRoot,
            modelAvailability: availability,
            downloadModel: { _, _, _ in
                attempts.increment()
                try FileManager.default.createDirectory(at: createdPartial, withIntermediateDirectories: true)
                FileManager.default.createFile(
                    atPath: createdPartial.appendingPathComponent("MelSpectrogram.mlmodelc").path,
                    contents: Data()
                )
                try FileManager.default.createDirectory(at: createdHidden, withIntermediateDirectories: true)
                throw URLError(.timedOut)
            },
            retryDelayNanoseconds: { _ in 0 }
        )

        do {
            _ = try await service.downloadIfNeeded(whisperKitModelName: "base", modelDisplayName: "Base")
            XCTFail("Expected downloadIfNeeded to throw after exhausting retries")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        }

        XCTAssertEqual(attempts.value, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdPartial.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdHidden.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preExistingHidden.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedModel.path))
    }

    func testDownloadIfNeededCleansUpImmediatelyOnNonRetryableErrorAndInvalidFolder() async throws {
        let createdPartial = temporaryRoot.appendingPathComponent(
            "models/openai_whisper-base",
            isDirectory: true
        )
        let attempts = AttemptCounter()
        let nonRetryableService = ModelDownloadService(
            modelsRoot: temporaryRoot,
            modelAvailability: availability,
            downloadModel: { _, _, _ in
                attempts.increment()
                try FileManager.default.createDirectory(at: createdPartial, withIntermediateDirectories: true)
                throw AppError.fileAccessDenied
            },
            retryDelayNanoseconds: { _ in 0 }
        )

        do {
            _ = try await nonRetryableService.downloadIfNeeded(whisperKitModelName: "base", modelDisplayName: "Base")
            XCTFail("Expected non-retryable error")
        } catch AppError.fileAccessDenied {
            // expected
        }
        XCTAssertEqual(attempts.value, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdPartial.path))

        // 取得後にファイル構成が不正な場合も新規フォルダを削除する。
        let invalidFolder = temporaryRoot.appendingPathComponent(
            "models/invalid/openai_whisper-base",
            isDirectory: true
        )
        let invalidResultService = ModelDownloadService(
            modelsRoot: temporaryRoot,
            modelAvailability: availability,
            downloadModel: { _, _, _ in
                try FileManager.default.createDirectory(at: invalidFolder, withIntermediateDirectories: true)
                return invalidFolder
            },
            retryDelayNanoseconds: { _ in 0 }
        )

        do {
            _ = try await invalidResultService.downloadIfNeeded(whisperKitModelName: "base", modelDisplayName: "Base")
            XCTFail("Expected validation failure")
        } catch AppError.transcriptionFailed {
            // expected
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidFolder.path))
    }

    func testDownloadIfNeededPreservesStagingAcrossRetryAndSucceedsOnSecondAttempt() async throws {
        let stagingFolder = temporaryRoot.appendingPathComponent(
            ".cache/huggingface/download/openai_whisper-base",
            isDirectory: true
        )
        let finalFolder = temporaryRoot.appendingPathComponent(
            "models/openai_whisper-base",
            isDirectory: true
        )
        let attempts = AttemptCounter()
        let stagingExistedOnRetry = LockedFlag()

        let service = ModelDownloadService(
            modelsRoot: temporaryRoot,
            modelAvailability: availability,
            downloadModel: { _, _, _ in
                let currentAttempt = attempts.increment()
                if currentAttempt == 1 {
                    try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
                    throw URLError(.networkConnectionLost)
                }
                stagingExistedOnRetry.set(FileManager.default.fileExists(atPath: stagingFolder.path))
                try FileManager.default.createDirectory(at: finalFolder, withIntermediateDirectories: true)
                for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
                    try Data("model".utf8).write(to: finalFolder.appendingPathComponent("\(name).mlmodelc"))
                }
                return finalFolder
            },
            retryDelayNanoseconds: { _ in 0 }
        )

        let result = try await service.downloadIfNeeded(whisperKitModelName: "base", modelDisplayName: "Base")

        XCTAssertEqual(attempts.value, 2)
        XCTAssertTrue(stagingExistedOnRetry.value, "再試行中に再開用ステージングフォルダを削除してはならない")
        XCTAssertEqual(result.resolvingSymlinksInPath().path, finalFolder.resolvingSymlinksInPath().path)
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "base"))
    }
}

private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        flag = newValue
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}

private final class ModelDeletionFailingFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError,
            userInfo: [NSFilePathErrorKey: URL.path]
        )
    }
}
