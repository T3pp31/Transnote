import Darwin
import XCTest
@testable import LocalTranscriber

final class AudioImportServiceTests: XCTestCase {
    private var importsRoot: URL!
    private var service: AudioImportService!

    override func setUpWithError() throws {
        importsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        service = AudioImportService(importsRoot: importsRoot)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: importsRoot)
    }

    func testImportFileCopiesIntoSandboxDirectory() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("sample.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("RIFF".utf8))

        let importedURL = try service.importFile(from: sourceURL)

        XCTAssertTrue(importedURL.path.hasPrefix(importsRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

    func testImportFileSkipsCopyWhenAlreadyInImportsDirectory() throws {
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        let importedURL = importsRoot.appendingPathComponent("sample.m4a")
        FileManager.default.createFile(atPath: importedURL.path, contents: Data("test".utf8))

        let result = try service.importFile(from: importedURL)

        XCTAssertEqual(result.standardizedFileURL, importedURL.standardizedFileURL)
    }

    func testImportFileUsesPreferredFileNameWhenSourceNameIsPlaceholder() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8))

        let importedURL = try service.importFile(from: sourceURL, preferredFileName: "recording.m4a")

        XCTAssertEqual(importedURL.pathExtension.lowercased(), "m4a")
        XCTAssertEqual(importedURL.lastPathComponent, "recording.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

    func testImportFileInfersM4AExtensionFromContentTypeForPlaceholderName() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        let importedURL = try service.importFile(from: sourceURL)

        XCTAssertEqual(importedURL.pathExtension.lowercased(), "m4a")
        XCTAssertTrue(importedURL.lastPathComponent.hasPrefix("imported-audio"))
    }

    func testImportFileThrowsWhenFileExceedsSizeLimit() throws {
        let limitedService = AudioImportService(importsRoot: importsRoot, maxImportFileSizeBytes: 10)

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("large.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data(repeating: 0, count: 11))

        XCTAssertThrowsError(try limitedService.importFile(from: sourceURL)) { error in
            guard case AppError.fileTooLarge = error else {
                XCTFail("Expected fileTooLarge, got \(error)")
                return
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: importsRoot.appendingPathComponent("large.wav").path))
    }

    func testImportFileSucceedsWhenFileWithinSizeLimit() throws {
        let limitedService = AudioImportService(importsRoot: importsRoot, maxImportFileSizeBytes: 10)

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("small.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data(repeating: 0, count: 10))

        let importedURL = try limitedService.importFile(from: sourceURL)

        XCTAssertTrue(importedURL.path.hasPrefix(importsRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
        XCTAssertEqual(try Data(contentsOf: importedURL), Data(repeating: 0, count: 10))
    }

    func testImportFileRejectsDirectoryWithSupportedExtension() throws {
        let sourceRoot = try makeSourceRoot()
        let directoryURL = sourceRoot.appendingPathComponent("evil.mp3", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let childURL = directoryURL.appendingPathComponent("large.dat")
        try Data(repeating: 0, count: 1024).write(to: childURL)

        XCTAssertThrowsError(try service.importFile(from: directoryURL)) { error in
            guard case AppError.fileAccessDenied = error else {
                return XCTFail("Expected fileAccessDenied, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: importsRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: childURL.path))
    }

    func testImportFileRejectsFIFOWithoutOpeningIt() throws {
        let sourceRoot = try makeSourceRoot()
        let fifoURL = sourceRoot.appendingPathComponent("pipe.wav")
        try fifoURL.withUnsafeFileSystemRepresentation { path in
            let path = try XCTUnwrap(path)
            XCTAssertEqual(mkfifo(path, 0o600), 0)
        }

        // 検証ガードが退行しても FIFO の open でテストが停止しないよう、
        // 実際の FIFO 属性を取得した直後にテスト用の通常ファイルへ置き換える。
        let fifoService = AudioImportService(importsRoot: importsRoot, fileManager: FIFOAttributesFileManager())
        XCTAssertThrowsError(try fifoService.importFile(from: fifoURL)) { error in
            guard case AppError.fileAccessDenied = error else {
                return XCTFail("Expected fileAccessDenied, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: importsRoot.path))
    }

    func testImportFileRejectsDirectoryAlreadyInsideImports() throws {
        let directoryURL = importsRoot.appendingPathComponent("evil.mp3", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try service.importFile(from: directoryURL)) { error in
            guard case AppError.fileAccessDenied = error else {
                return XCTFail("Expected fileAccessDenied, got \(error)")
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: importsRoot.path), ["evil.mp3"])
    }

    func testImportFileChecksSizeEvenWhenAlreadyInsideImports() throws {
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        let sourceURL = importsRoot.appendingPathComponent("large.wav")
        let content = Data(repeating: 0, count: 11)
        try content.write(to: sourceURL)
        let limitedService = AudioImportService(importsRoot: importsRoot, maxImportFileSizeBytes: 10)

        XCTAssertThrowsError(try limitedService.importFile(from: sourceURL)) { error in
            guard case AppError.fileTooLarge = error else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: sourceURL), content, "既存ファイルは削除しない")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: importsRoot.path), ["large.wav"])
    }

    func testImportFileRejectsMissingSizeAttribute() throws {
        let sourceURL = try makeSourceRoot().appendingPathComponent("sample.wav")
        try Data("audio".utf8).write(to: sourceURL)
        let missingSizeService = AudioImportService(importsRoot: importsRoot, fileManager: MissingSizeFileManager())

        XCTAssertThrowsError(try missingSizeService.importFile(from: sourceURL)) { error in
            guard case AppError.fileAccessDenied = error else {
                return XCTFail("Expected fileAccessDenied, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: importsRoot.path))
    }

    func testImportFileStopsBeforeWritingPastLimitWhenSourceGrowsAfterValidation() throws {
        let sourceURL = try makeSourceRoot().appendingPathComponent("growing.wav")
        try Data("audio".utf8).write(to: sourceURL)
        // 1 チャンクは書き込めるが、2 チャンク目で累積サイズが上限を超える。
        let limit = 64 * 1024 + 10
        let grownContent = Data(repeating: 0x5a, count: limit + 1)
        let growingManager = GrowingSourceFileManager(sourceURL: sourceURL, grownContent: grownContent)
        let limitedService = AudioImportService(
            importsRoot: importsRoot,
            fileManager: growingManager,
            maxImportFileSizeBytes: Int64(limit)
        )

        XCTAssertThrowsError(try limitedService.importFile(from: sourceURL)) { error in
            guard case AppError.fileTooLarge = error else {
                return XCTFail("Expected fileTooLarge, got \(error)")
            }
        }
        XCTAssertEqual(growingManager.removedTemporaryFileSizes.count, 1)
        let partialSize = try XCTUnwrap(growingManager.removedTemporaryFileSizes.first)
        XCTAssertGreaterThan(partialSize, 0)
        XCTAssertLessThanOrEqual(partialSize, Int64(limit), "事後検査ではなく書き込み前に上限を守る")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: importsRoot.path), [])
        XCTAssertEqual(try Data(contentsOf: sourceURL), grownContent, "ソースは削除・切り詰めしない")
    }

    func testImportFileCopiesGrowingSourceExactlyAtLimitAcrossMultipleBuffers() throws {
        let sourceURL = try makeSourceRoot().appendingPathComponent("growing.wav")
        try Data("audio".utf8).write(to: sourceURL)
        let content = Data((0..<(64 * 1024 * 2 + 17)).map { UInt8($0 % 251) })
        let growingManager = GrowingSourceFileManager(sourceURL: sourceURL, grownContent: content)
        let limitedService = AudioImportService(
            importsRoot: importsRoot,
            fileManager: growingManager,
            maxImportFileSizeBytes: Int64(content.count)
        )

        let importedURL = try limitedService.importFile(from: sourceURL)

        XCTAssertEqual(try Data(contentsOf: importedURL), content)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: importsRoot.path), ["growing.wav"])
        XCTAssertTrue(growingManager.removedTemporaryFileSizes.isEmpty)
    }

    func testImportFileAcceptsEmptyFileAtZeroLimit() throws {
        let sourceURL = try makeSourceRoot().appendingPathComponent("empty.wav")
        try Data().write(to: sourceURL)
        let limitedService = AudioImportService(importsRoot: importsRoot, maxImportFileSizeBytes: 0)

        let importedURL = try limitedService.importFile(from: sourceURL)

        XCTAssertEqual(try Data(contentsOf: importedURL), Data())
    }

    func testValidateAcceptsExtensionFromPreferredFileName() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("PasteboardTemp")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("not-audio".utf8))

        let audioFileService = AudioFileService()
        let info = try audioFileService.validate(url: sourceURL, preferredFileName: "memo.m4a")

        XCTAssertEqual(info.fileExtension, "m4a")
        XCTAssertEqual(info.fileName, "PasteboardTemp")
    }

    // MARK: - partial import file cleanup (#140)

    func testRemoveFileIfExistsIfFailedDeletesZeroByteFile() throws {
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        let zeroByteURL = importsRoot.appendingPathComponent("partial-zero-byte.m4a")
        XCTAssertTrue(FileManager.default.createFile(atPath: zeroByteURL.path, contents: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: zeroByteURL.path))

        service.removeFileIfExistsIfFailed(zeroByteURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: zeroByteURL.path))
    }

    func testRemoveFileIfExistsIfFailedIsNoOpForMissingFile() {
        let missingURL = importsRoot.appendingPathComponent("missing.m4a")

        // 存在しないパスでも throw せず何もしない
        service.removeFileIfExistsIfFailed(missingURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
    }

    func testImportFileRemovesPartialFileWhenStreamingDestinationCreationFails() throws {
        let failingManager = PartialCreationThenFailFileManager()
        let serviceWithFailingManager = AudioImportService(
            importsRoot: importsRoot,
            fileManager: failingManager
        )

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("sample.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("audio".utf8))

        let destinationURL = importsRoot.appendingPathComponent("sample.wav")

        XCTAssertThrowsError(try serviceWithFailingManager.importFile(from: sourceURL)) { error in
            guard case AppError.fileAccessDenied = error else {
                XCTFail("Expected fileAccessDenied, got \(error)")
                return
            }
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destinationURL.path),
            "ストリーミングの準備に失敗した場合、Imports/ に部分ファイルが残ってはならない"
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: importsRoot.path), [])
    }

    func testImportFileStreamsWithoutUsingCopyItem() throws {
        let failingManager = CopyItemForbiddenFileManager()
        let serviceWithFailingManager = AudioImportService(
            importsRoot: importsRoot,
            fileManager: failingManager
        )

        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("readable.wav")
        let content = Data("streaming fallback content".utf8)
        FileManager.default.createFile(atPath: sourceURL.path, contents: content)

        let importedURL = try serviceWithFailingManager.importFile(from: sourceURL)

        let importedData = try Data(contentsOf: importedURL)
        XCTAssertEqual(importedData, content)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

// MARK: - cleanup (#187)

    func testCleanupExpiredImportsRemovesOldFilesAndKeepsRecentOnes() throws {
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)

        let oldURL = importsRoot.appendingPathComponent("old.m4a")
        let recentURL = importsRoot.appendingPathComponent("recent.m4a")
        FileManager.default.createFile(atPath: oldURL.path, contents: Data("old".utf8))
        FileManager.default.createFile(atPath: recentURL.path, contents: Data("recent".utf8))

        let oldDate = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldURL.path)

        try service.cleanupExpiredImports(maxAge: 30 * 24 * 60 * 60, now: Date())

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }

    func testCleanupExpiredImportsIsNoOpWhenImportsRootMissing() throws {
        // importsRoot が存在しない場合でも throw しない
        XCTAssertNoThrow(try service.cleanupExpiredImports())
    }

    func testCleanupExpiredImportsRemovesHiddenTemporaryFile() throws {
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        let hiddenTmpURL = importsRoot.appendingPathComponent(".audio.m4a.tmp-UUID")
        FileManager.default.createFile(atPath: hiddenTmpURL.path, contents: Data("tmp".utf8))

        let oldDate = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: hiddenTmpURL.path)

        try service.cleanupExpiredImports(maxAge: 30 * 24 * 60 * 60, now: Date())

        XCTAssertFalse(FileManager.default.fileExists(atPath: hiddenTmpURL.path))
    }

    func testImportedOldSourceIsNotImmediatelyExpired() throws {
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("old-recording.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("audio".utf8))
        let oldDate = Date(timeIntervalSinceNow: -40 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: sourceURL.path)

        let importedURL = try service.importFile(from: sourceURL)
        try service.cleanupExpiredImports(maxAge: 30 * 24 * 60 * 60, now: Date())

        XCTAssertTrue(FileManager.default.fileExists(atPath: importedURL.path))
    }

    private func makeSourceRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }
}

/// 出力ファイルの作成が途中で失敗し、一時ファイルだけが残る状況を再現する。
private final class PartialCreationThenFailFileManager: FileManager, @unchecked Sendable {
    override func createFile(
        atPath path: String,
        contents data: Data?,
        attributes attr: [FileAttributeKey: Any]? = nil
    ) -> Bool {
        _ = super.createFile(atPath: path, contents: Data("partial".utf8), attributes: attr)
        return false
    }
}

private final class CopyItemForbiddenFileManager: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        XCTFail("コピー量を制限できない copyItem を呼び出してはならない")
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
    }
}

private final class FIFOAttributesFileManager: FileManager, @unchecked Sendable {
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        let attributes = try super.attributesOfItem(atPath: path)
        if attributes[.type] as? FileAttributeType == .typeFifo {
            try super.removeItem(atPath: path)
            _ = super.createFile(atPath: path, contents: Data())
        }
        return attributes
    }
}

private final class MissingSizeFileManager: FileManager, @unchecked Sendable {
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        var attributes = try super.attributesOfItem(atPath: path)
        attributes.removeValue(forKey: .size)
        return attributes
    }
}

/// 事前検証に返す属性は元のサイズのまま、実ファイルだけを増加させる。
private final class GrowingSourceFileManager: FileManager, @unchecked Sendable {
    private let sourceURL: URL
    private let grownContent: Data
    private var didGrow = false
    private(set) var removedTemporaryFileSizes: [Int64] = []

    init(sourceURL: URL, grownContent: Data) {
        self.sourceURL = sourceURL
        self.grownContent = grownContent
        super.init()
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        let attributes = try super.attributesOfItem(atPath: path)
        if path == sourceURL.path, !didGrow {
            didGrow = true
            try grownContent.write(to: sourceURL)
        }
        return attributes
    }

    override func removeItem(at url: URL) throws {
        if url.lastPathComponent.contains(".tmp-"),
           let size = try super.attributesOfItem(atPath: url.path)[.size] as? NSNumber {
            removedTemporaryFileSizes.append(size.int64Value)
        }
        try super.removeItem(at: url)
    }
}
