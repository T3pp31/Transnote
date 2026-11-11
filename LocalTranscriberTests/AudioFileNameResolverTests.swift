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

        XCTAssertEqual(resolved, "source.mp3")
        XCTAssertFalse(resolved.contains("/"))
        XCTAssertFalse(resolved.contains(".."))
    }

    func testResolveDetectsWaveMagicBytes() throws {
        let sourceURL = tempDirectory.appendingPathComponent("recording.bin")
        let header = Data("RIFF".utf8) + Data([0x04, 0x00, 0x00, 0x00]) + Data("WAVE".utf8)
        try header.write(to: sourceURL)

        let resolved = AudioFileNameResolver.resolve(
            sourceURL: sourceURL,
            supportedExtensions: supportedExtensions
        )

        XCTAssertEqual(resolved, "recording.wav")
    }

    func testResolveRejectsNonWaveRIFFMagicBytes() throws {
        for formType in ["AVI ", "WEBP", "RMID", "????"] {
            let sourceURL = tempDirectory.appendingPathComponent("recording-\(UUID().uuidString).bin")
            let header = Data("RIFF".utf8) + Data([0x04, 0x00, 0x00, 0x00]) + Data(formType.utf8)
            try header.write(to: sourceURL)

            let resolved = AudioFileNameResolver.resolve(
                sourceURL: sourceURL,
                supportedExtensions: supportedExtensions
            )

            XCTAssertEqual(resolved, "imported-audio", "RIFF form type: \(formType)")
        }
    }

    func testResolveRejectsTruncatedRIFFMagicBytes() throws {
        let header = Data("RIFF".utf8) + Data([0x04, 0x00, 0x00, 0x00]) + Data("WAVE".utf8)
        for byteCount in 0..<header.count {
            let sourceURL = tempDirectory.appendingPathComponent("truncated-\(byteCount).bin")
            try Data(header.prefix(byteCount)).write(to: sourceURL)

            let resolved = AudioFileNameResolver.resolve(
                sourceURL: sourceURL,
                supportedExtensions: supportedExtensions
            )

            XCTAssertEqual(resolved, "imported-audio", "Header length: \(byteCount)")
        }
    }

    func testResolveDoesNotDetectWaveWhenExtensionIsUnsupported() throws {
        let sourceURL = tempDirectory.appendingPathComponent("recording.bin")
        let header = Data("RIFF".utf8) + Data([0x04, 0x00, 0x00, 0x00]) + Data("WAVE".utf8)
        try header.write(to: sourceURL)

        let resolved = AudioFileNameResolver.resolve(
            sourceURL: sourceURL,
            supportedExtensions: ["mp3", "m4a", "flac"]
        )

        XCTAssertEqual(resolved, "imported-audio")
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
