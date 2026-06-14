import XCTest
@testable import LocalTranscriber

@MainActor
final class MainWindowViewModelImportTests: XCTestCase {
    private var importsRoot: URL!
    private var sourceRoot: URL!
    private var viewModel: MainWindowViewModel!

    override func setUpWithError() throws {
        importsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: importsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        viewModel = MainWindowViewModel(
            audioImportService: AudioImportService(importsRoot: importsRoot)
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: importsRoot)
        try? FileManager.default.removeItem(at: sourceRoot)
    }

    func testSelectFileImportsExtensionlessM4APlaceholderName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("CFNetworkDownload_tmp")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertTrue(viewModel.selectedFile?.fileName.hasSuffix(".m4a") == true)
        XCTAssertTrue(
            viewModel.selectedFile?.url.path.hasPrefix(importsRoot.path) == true
        )
    }

    func testSelectFileImportsPlaceholderDropNameWithPreferredFileName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8))

        viewModel.selectFile(url: sourceURL)

        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSelectFileImportsPlaceholderDropNameWithDropPreferredFileName() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data("fake audio".utf8))

        viewModel.selectFile(url: sourceURL, preferredFileName: "recording.m4a")

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertEqual(viewModel.selectedFile?.fileName, "recording.m4a")
    }

    func testSelectFileImportsPlaceholderDropNameWithM4AContent() throws {
        let sourceURL = sourceRoot.appendingPathComponent("file URL")
        let m4aHeader = Data([
            0x00, 0x00, 0x00, 0x1c, 0x66, 0x74, 0x79, 0x70,
            0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
            0x6d, 0x70, 0x34, 0x32, 0x69, 0x73, 0x6f, 0x6d
        ])
        FileManager.default.createFile(atPath: sourceURL.path, contents: m4aHeader)

        viewModel.selectFile(url: sourceURL)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedFile?.fileExtension, "m4a")
        XCTAssertEqual(viewModel.selectedFile?.fileName, "imported-audio.m4a")
    }
}
