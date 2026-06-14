import XCTest
@testable import LocalTranscriber

final class AudioFileServiceTests: XCTestCase {
    private var tempRoot: URL!
    private var service: AudioFileService!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        service = AudioFileService()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testValidateAcceptsM4AExtension() throws {
        let url = tempRoot.appendingPathComponent("sample.m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))

        let info = try service.validate(url: url)

        XCTAssertEqual(info.fileExtension, "m4a")
    }

    func testValidateRejectsExtensionlessTempFileLikeDrop() {
        let url = tempRoot.appendingPathComponent("CFNetworkDownload_tmp")
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))

        XCTAssertThrowsError(try service.validate(url: url)) { error in
            guard case AppError.unsupportedFileExtension(let ext) = error else {
                return XCTFail("Expected unsupportedFileExtension, got \(error)")
            }
            XCTAssertEqual(ext, "unknown")
        }
    }

    func testDropFileNameResolverUsesSuggestedNameForExtensionlessTemp() {
        let tempURL = tempRoot.appendingPathComponent("CFNetworkDownload_tmp")

        let resolved = DropFileNameResolver.resolve(
            suggestedName: "recording.m4a",
            tempURL: tempURL,
            typeIdentifiers: ["public.file-url"]
        )

        XCTAssertEqual(resolved, "recording.m4a")
    }

    func testDropFileNameResolverIgnoresPlaceholderSuggestedName() {
        let tempURL = tempRoot.appendingPathComponent("CFNetworkDownload_tmp")

        let resolved = DropFileNameResolver.resolve(
            suggestedName: "file URL",
            tempURL: tempURL,
            typeIdentifiers: ["public.mpeg-4-audio"]
        )

        XCTAssertEqual(resolved, "imported-audio.m4a")
    }

    func testDropFileNameResolverInfersM4AFromTypeIdentifier() {
        let tempURL = tempRoot.appendingPathComponent("CFNetworkDownload_tmp")

        let resolved = DropFileNameResolver.resolve(
            suggestedName: nil,
            tempURL: tempURL,
            typeIdentifiers: ["public.mpeg-4-audio"]
        )

        XCTAssertEqual(resolved, "imported-audio.m4a")
    }

    func testValidateAcceptsResolvedDropFileName() throws {
        let url = tempRoot.appendingPathComponent("recording.m4a")
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))

        let info = try service.validate(url: url)

        XCTAssertEqual(info.fileExtension, "m4a")
        XCTAssertEqual(info.fileName, "recording.m4a")
    }

    func testDropURLParserReadsDataRepresentation() throws {
        let original = URL(fileURLWithPath: "/Users/test/Music/recording.m4a")
        let data = original.dataRepresentation

        let parsed = DropURLParser.url(from: data as NSSecureCoding)

        XCTAssertEqual(parsed?.path, original.path)
    }

    func testDropURLParserReadsURLObject() {
        let original = URL(fileURLWithPath: "/Users/test/Music/recording.m4a")

        let parsed = DropURLParser.url(from: original as NSSecureCoding)

        XCTAssertEqual(parsed, original)
    }
}
