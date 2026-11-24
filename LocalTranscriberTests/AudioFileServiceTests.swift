import CryptoKit
import UniformTypeIdentifiers
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
        for fileName in ["sample.m4a", "recording.m4a"] {
            let url = tempRoot.appendingPathComponent(fileName)
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8)))

            let info = try service.validate(url: url)

            XCTAssertEqual(info.fileExtension, "m4a")
            XCTAssertEqual(info.fileName, fileName)
        }
    }

    func testSHA256ReturnsNilForMissingFile() {
        XCTAssertNil(
            AudioFileService.sha256(
                of: tempRoot.appendingPathComponent("missing.wav")
            )
        )
    }

    func testSHA256ReturnsDigestForExistingFile() throws {
        let url = tempRoot.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: url)

        XCTAssertEqual(
            AudioFileService.sha256(of: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testSHA256ReturnsDigestForEmptyFile() throws {
        let url = tempRoot.appendingPathComponent("empty.bin")
        try Data().write(to: url)

        XCTAssertEqual(
            AudioFileService.sha256(of: url),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testSHA256ReadsAcrossMultipleChunks() throws {
        let url = tempRoot.appendingPathComponent("large.bin")
        let data = Data(repeating: 0x61, count: 200_000)
        try data.write(to: url)

        var hasher = SHA256()
        hasher.update(data: data)
        let expected = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(AudioFileService.sha256(of: url), expected)
    }

    // MARK: - drop services / supported audio types (#244)

    func testSupportedAudioTypesResolveExtension() {
        XCTAssertEqual(SupportedAudioTypes.resolveExtension(for: URL(fileURLWithPath: "/a/b.wav")), "wav")
        XCTAssertEqual(SupportedAudioTypes.resolveExtension(for: URL(fileURLWithPath: "/a/b.MP3")), "mp3")
        XCTAssertNil(SupportedAudioTypes.resolveExtension(for: URL(fileURLWithPath: "/a/b")))
    }

    func testSupportedAudioTypesAllowedContentTypes() {
        let types = SupportedAudioTypes.allowedContentTypes(for: ["wav", "mp3", "m4a"])
        XCTAssertEqual(types, [.wav, .mp3, .mpeg4Audio])

        let withUnknown = SupportedAudioTypes.allowedContentTypes(for: ["wav", "unknown-format", "mp3", "m4a"])
        XCTAssertEqual(withUnknown, [.wav, .mp3, .mpeg4Audio])
    }

    func testDropImportServiceHasSupportedExtension() {
        XCTAssertTrue(DropImportService.hasSupportedExtension("recording.m4a", supportedExtensions: ["m4a"]))
        XCTAssertFalse(DropImportService.hasSupportedExtension("recording.mov", supportedExtensions: ["m4a"]))
    }

    func testDropImportServicePrefersAudioTypesOverFileURLAndPreservesFallbacks() {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.mpeg4Audio.identifier, visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }

        let ordered = DropImportService.preferredTypeIdentifiers(from: provider)
        guard let m4aIndex = ordered.firstIndex(of: UTType.mpeg4Audio.identifier),
              let fileURLIndex = ordered.firstIndex(of: UTType.fileURL.identifier),
              let plainTextIndex = ordered.firstIndex(of: UTType.plainText.identifier) else {
            return XCTFail("Expected registered identifiers in \(ordered)")
        }
        XCTAssertLessThan(m4aIndex, fileURLIndex)
        XCTAssertLessThan(fileURLIndex, plainTextIndex)
        XCTAssertEqual(Set(ordered).count, ordered.count, "重複する識別子を含めないこと")
    }
}
