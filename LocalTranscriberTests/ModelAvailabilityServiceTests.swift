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
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then
        XCTAssertTrue(result)
        XCTAssertNotNil(service.modelFolder(for: "base"))
    }

    func testIsDownloadedReturnsFalseWhenRequiredModelFileIsZeroBytes() throws {
        // Given: 必須ファイルが0バイト（ダウンロード途中失敗）の variant フォルダ
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = variantFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: 0バイトは不完全扱いのため未ダウンロード
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "base"))
    }

    func testModelFolderIgnoresParentWhenModelsAreOnlyInChildDirectory() throws {
        // Given: 親フォルダにはモデルがなく、子フォルダのみに配置
        let parentFolder = temporaryRoot.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
        let childFolder = parentFolder.appendingPathComponent("openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = childFolder.appendingPathComponent("\(name).mlmodelc")
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
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
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
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
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "tiny")

        // Then: "itiny" は "tiny" で終わるがハイフン区切りではないためマッチしない
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "tiny"))
    }

    // MARK: - 同スコア時の決定的な選択

    /// /var は /private/var へのシンボリックリンクのため、enumerator の返す URL と
    /// temporaryDirectory から生成した URL で実パス表現が異なる。両者を正規化して比較する。
    private func standardize(_ url: URL?) -> URL? {
        url?.resolvingSymlinksInPath().standardizedFileURL
    }

    private func makeVariantFolder(_ name: String, modificationDate: Date?) throws -> URL {
        let folder = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for coreMLName in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let fileURL = folder.appendingPathComponent("\(coreMLName).mlmodelc")
            // 0バイトは #138 の「不完全ダウンロード」判定で除外されるため、非ゼロデータで作成する
            FileManager.default.createFile(atPath: fileURL.path, contents: Data("model".utf8))
        }
        if let modificationDate {
            try FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: folder.path
            )
        }
        return folder
    }

    func testModelFolderPrefersNewerModificationDateOnEqualScores() throws {
        // Given: 同スコア（接尾辞一致 80）の2つの候補フォルダを用意
        let older = try makeVariantFolder("alpha-base", modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let newer = try makeVariantFolder("beta-base", modificationDate: Date(timeIntervalSince1970: 2_000_000))

        // When
        let folder = service.modelFolder(for: "base")

        // Then: 更新日時が新しい方が選択される
        XCTAssertEqual(standardize(folder), standardize(newer))
        XCTAssertNotEqual(standardize(folder), standardize(older))
    }

    func testModelFolderPrefersLexicographicallyOrderedNameOnEqualModificationDate() throws {
        // Given: 同スコアかつ同一更新日時の2つの候補フォルダを用意
        let sameDate = Date(timeIntervalSince1970: 1_500_000)
        let alpha = try makeVariantFolder("alpha-base", modificationDate: sameDate)
        let beta = try makeVariantFolder("beta-base", modificationDate: sameDate)

        // When
        let folder = service.modelFolder(for: "base")

        // Then: 列挙順ではなく名前の昇順で決定的に選択される
        XCTAssertEqual(standardize(folder), standardize(alpha))
        XCTAssertNotEqual(standardize(folder), standardize(beta))
    }

    func testModelFolderPrefersHigherScoreFolder() throws {
        // Given: 高スコア（完全一致 100）と低スコア（接尾辞一致 80）の候補を用意
        let exactMatch = try makeVariantFolder("base", modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let suffixMatch = try makeVariantFolder("custom-base", modificationDate: Date(timeIntervalSince1970: 2_000_000))

        // When
        let folder = service.modelFolder(for: "base")

        // Then: 更新日時に関わらず高スコアのフォルダが選択される
        XCTAssertEqual(standardize(folder), standardize(exactMatch))
        XCTAssertNotEqual(standardize(folder), standardize(suffixMatch))
    }

    func testExactVariantMatchBeatsOpenAIWhisperPrefixMatch() throws {
        // Given: 完全一致（100）と openai_whisper- 一致（90）の候補を用意
        let exactMatch = try makeVariantFolder("base", modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let prefixMatch = try makeVariantFolder("openai_whisper-base", modificationDate: Date(timeIntervalSince1970: 2_000_000))

        // When
        let folder = service.modelFolder(for: "base")

        // Then: 更新日時に関わらず完全一致（スコア 100）が優先される
        XCTAssertEqual(standardize(folder), standardize(exactMatch))
        XCTAssertNotEqual(standardize(folder), standardize(prefixMatch))
    }

    func testModelFolderIgnoresHiddenCacheDirectory() throws {
        // Given: 実際のモデルフォルダ（古い）と HuggingFace ステージングの隠しフォルダ（新しい）を用意
        let realFolder = try makeVariantFolder(
            "openai_whisper-base",
            modificationDate: Date(timeIntervalSince1970: 1_000_000)
        )
        let cacheFolder = try makeVariantFolder(
            ".cache/huggingface/download/openai_whisper-base",
            modificationDate: Date(timeIntervalSince1970: 2_000_000)
        )

        // When
        let folder = service.modelFolder(for: "base")

        // Then: 更新日時が新しい隠しフォルダではなく実フォルダが選択される
        XCTAssertEqual(standardize(folder), standardize(realFolder))
        XCTAssertNotEqual(standardize(folder), standardize(cacheFolder))
    }

    func testVariantDirectoriesExcludesHiddenByDefaultAndIncludesWhenRequested() throws {
        let visible = try makeVariantFolder("openai_whisper-base", modificationDate: nil)
        let hidden = try makeVariantFolder(
            ".cache/huggingface/download/openai_whisper-base",
            modificationDate: nil
        )

        let visibleOnly = service.variantDirectories(named: "base")
        let withHidden = service.variantDirectories(named: "base", includingHidden: true)

        XCTAssertTrue(visibleOnly.contains { standardize($0) == standardize(visible) })
        XCTAssertFalse(visibleOnly.contains { standardize($0) == standardize(hidden) })
        XCTAssertTrue(withHidden.contains { standardize($0) == standardize(visible) })
        XCTAssertTrue(withHidden.contains { standardize($0) == standardize(hidden) })
    }

    func testModelFolderBreaksIdenticalNameTiesUsingFullPath() throws {
        // Given: 同一葉名・同一更新日時で親だけが異なる 2 つの候補
        let sameDate = Date(timeIntervalSince1970: 1_500_000)
        let repoA = try makeVariantFolder("repo-a/openai_whisper-base", modificationDate: sameDate)
        let repoB = try makeVariantFolder("repo-b/openai_whisper-base", modificationDate: sameDate)

        // When
        let folder = service.modelFolder(for: "base")

        // Then: 列挙順ではなく正規化パスの昇順で決定的に選択される
        let expectedPath: String? = [repoA, repoB]
            .compactMap { standardize($0)?.path }
            .min()
        XCTAssertEqual(standardize(folder)?.path, expectedPath)
    }

    func testIsDownloadedReturnsFalseWhenRequiredModelBundleDirectoryIsEmpty() throws {
        // Given: .mlmodelc が空ディレクトリ（ダウンロード途中のバンドル）
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let bundleURL = variantFolder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        }

        // When
        let result = service.isDownloaded(whisperKitModelName: "base")

        // Then: 空バンドルは不完全扱い
        XCTAssertFalse(result)
        XCTAssertNil(service.modelFolder(for: "base"))
    }

    func testIsDownloadedReturnsTrueWhenRequiredModelBundleDirectoryHasContents() throws {
        // Given: .mlmodelc が中身のあるディレクトリ（実際の CoreML バンドル）
        let variantFolder = temporaryRoot.appendingPathComponent("models/openai_whisper-base", isDirectory: true)
        try FileManager.default.createDirectory(at: variantFolder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let bundleURL = variantFolder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: bundleURL.appendingPathComponent("coremldata.bin").path,
                contents: Data("model".utf8)
            )
        }

        // When / Then
        XCTAssertTrue(service.isDownloaded(whisperKitModelName: "base"))
        XCTAssertNotNil(service.modelFolder(for: "base"))
    }
}
