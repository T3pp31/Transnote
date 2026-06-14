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
}
