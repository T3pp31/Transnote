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

    func testProbeDecodabilityReturnsTrueForRealWAV() throws {
        let url = tempRoot.appendingPathComponent("real-silence.wav")
        let wavHeader = Data([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x24, 0x00, 0x00, 0x00, // size
            0x57, 0x41, 0x56, 0x45, // WAVE
            0x66, 0x6d, 0x74, 0x20, // fmt
            0x10, 0x00, 0x00, 0x00, // fmt size
            0x01, 0x00, // PCM
            0x01, 0x00, // channels
            0x40, 0x1f, 0x00, 0x00, // sample rate 8000
            0x80, 0x3e, 0x00, 0x00, // byte rate
            0x02, 0x00, // block align
            0x10, 0x00, // bits
            0x64, 0x61, 0x74, 0x61, // data
            0x00, 0x00, 0x00, 0x00  // data size 0
        ])
        FileManager.default.createFile(atPath: url.path, contents: wavHeader)

        XCTAssertTrue(service.probeDecodability(url: url))
    }

    func testProbeDecodabilityReturnsFalseForGarbage() throws {
        let url = tempRoot.appendingPathComponent("garbage.wav")
        FileManager.default.createFile(atPath: url.path, contents: Data("not-audio".utf8))

        XCTAssertFalse(service.probeDecodability(url: url))
    }

}