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
        // Given: 一時ディレクトリ上の wav ファイル
        let sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("sample.wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("RIFF".utf8))

        // When
        let importedURL = try service.importFile(from: sourceURL)

        // Then
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
}
