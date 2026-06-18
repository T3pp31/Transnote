import XCTest
@testable import LocalTranscriber

final class AudioFileNameResolverTests: XCTestCase {
    private let supportedExtensions = ["wav", "mp3", "m4a", "flac"]
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    func testSanitizeFileNameAcceptsNormalName() {
        XCTAssertEqual(AudioFileNameResolver.sanitizeFileName("normal.mp3"), "normal.mp3")
    }

    func testSanitizeFileNameNormalizesSubpath() {
        XCTAssertEqual(AudioFileNameResolver.sanitizeFileName("subdir/file.mp3"), "file.mp3")
    }

    func testSanitizeFileNameRejectsPathTraversal() {
        XCTAssertNil(AudioFileNameResolver.sanitizeFileName("../../../tmp/evil.mp3"))
        XCTAssertNil(AudioFileNameResolver.sanitizeFileName(".."))
        XCTAssertNil(AudioFileNameResolver.sanitizeFileName("."))
    }

    func testIsUsableFileNameRejectsUnsupportedExtension() {
        let supported = Set(supportedExtensions)
        XCTAssertFalse(AudioFileNameResolver.isUsableFileName("file.txt", supportedExtensions: supported))
    }

    func testResolveRejectsTraversalPreferredFileNameAndFallsBack() throws {
        let sourceURL = tempDirectory.appendingPathComponent("source")
        let mp3Header = Data([0xFF, 0xFB, 0x90, 0x00])
        try mp3Header.write(to: sourceURL)

        let resolved = AudioFileNameResolver.resolve(
            sourceURL: sourceURL,
            preferredFileName: "../../../tmp/evil.mp3",
            supportedExtensions: supportedExtensions
        )

        XCTAssertEqual(resolved, "source")
        XCTAssertFalse(resolved.contains("/"))
        XCTAssertFalse(resolved.contains(".."))
    }

    func testResolveAcceptsNormalPreferredFileName() throws {
        let sourceURL = tempDirectory.appendingPathComponent("source.wav")
        try Data("RIFF".utf8).write(to: sourceURL)

        let resolved = AudioFileNameResolver.resolve(
            sourceURL: sourceURL,
            preferredFileName: "recording.wav",
            supportedExtensions: supportedExtensions
        )

        XCTAssertEqual(resolved, "recording.wav")
    }
}
