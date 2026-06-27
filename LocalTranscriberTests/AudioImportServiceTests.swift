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
            guard case AppError.fileTooLarge = error as? AppError else {
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
}
