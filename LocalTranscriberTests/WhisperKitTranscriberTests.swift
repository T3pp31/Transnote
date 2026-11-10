import AVFoundation
import XCTest

@testable import LocalTranscriber

final class WhisperKitTranscriberTests: XCTestCase {
    private var temporaryRoot: URL!
    private var transcriber: WhisperKitTranscriber!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let availability = ModelAvailabilityService(modelsRoot: temporaryRoot)
        transcriber = WhisperKitTranscriber(modelAvailability: availability)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
        transcriber = nil
    }

    func testTranscribeFailsWhenModelNotDownloaded() async {
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-model-test.wav")
        FileManager.default.createFile(atPath: audioURL.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let job = TranscriptionJob(
            audioFileURL: audioURL,
            sourceFileName: audioURL.lastPathComponent,
            modelID: "base",
            whisperKitModelName: "base",
            modelDisplayName: "Base",
            languageID: "auto"
        )

        do {
            _ = try await transcriber.transcribe(job)
            XCTFail("Expected modelNotDownloaded error")
        } catch let error as AppError {
            guard case .modelNotDownloaded("Base") = error else {
                return XCTFail("Unexpected AppError: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    func testSplitShortAudioReturnsOriginalFile() async throws {
        let source = try makeAudioFile(name: "short.m4a")
        let chunks = try await transcriber.splitAudioIntoChunks(url: source, chunkDuration: 10)
        XCTAssertEqual(chunks.map(\.url), [source])
        XCTAssertEqual(chunks.map(\.startSeconds), [0])
    }

    func testSplitAudioPreservesOffsetsAndUsesUniqueFiles() async throws {
        let source = try makeAudioFile(name: "source.m4a")
        let output = temporaryRoot.appendingPathComponent("chunks", isDirectory: true)
        let first = try await transcriber.splitAudioIntoChunks(
            url: source, chunkDuration: 0.4, outputDirectory: output
        )
        let second = try await transcriber.splitAudioIntoChunks(
            url: source, chunkDuration: 0.4, outputDirectory: output
        )
        assertChunkOffsets(first)
        XCTAssertEqual(first.count, second.count)
        XCTAssertTrue(Set(first.map(\.url)).isDisjoint(with: second.map(\.url)))
        for chunk in first + second {
            XCTAssertNotEqual(chunk.url, source)
            XCTAssertTrue(FileManager.default.fileExists(atPath: chunk.url.path))
            let duration = try await AVURLAsset(url: chunk.url).load(.duration).seconds
            XCTAssertGreaterThan(duration, 0)
        }
    }

    func testChunkOffsetAssertionReportsFailureForEmptyChunks() {
        XCTExpectFailure("Empty chunks must report an assertion failure without trapping") {
            assertChunkOffsets([])
        }
    }

    func testChunkOffsetAssertionReportsFailureForSingleChunk() {
        let chunk = WhisperKitTranscriber.AudioChunk(
            url: temporaryRoot.appendingPathComponent("source.m4a"), startSeconds: 0
        )
        XCTExpectFailure("A single chunk must report an assertion failure without trapping") {
            assertChunkOffsets([chunk])
        }
    }

    private func assertChunkOffsets(
        _ chunks: [WhisperKitTranscriber.AudioChunk],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard chunks.count > 1 else {
            return XCTFail("Expected multiple chunks, got \(chunks.count)", file: file, line: line)
        }
        XCTAssertEqual(chunks.first?.startSeconds, 0, file: file, line: line)
        XCTAssertEqual(chunks[1].startSeconds, 0.3, accuracy: 0.001, file: file, line: line)
    }

    func testMissingExportSessionThrowsWithoutLeavingPartialChunks() async throws {
        let source = try makeAudioFile(name: "source.m4a")
        let output = temporaryRoot.appendingPathComponent("chunks", isDirectory: true)
        var sessionCount = 0
        do {
            _ = try await transcriber.splitAudioIntoChunks(
                url: source, chunkDuration: 0.4, outputDirectory: output,
                makeExportSession: { asset in
                    sessionCount += 1
                    guard sessionCount == 1 else { return nil }
                    return AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
                }
            )
            XCTFail("Expected session creation to fail on the second chunk")
        } catch let error as WhisperKitTranscriber.ChunkExportFailure {
            XCTAssertEqual(error.statusText, "export session unavailable")
        }
        XCTAssertEqual(sessionCount, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testCancelledSplitDoesNotCreateFiles() async throws {
        let source = try makeAudioFile(name: "source.m4a")
        let output = temporaryRoot.appendingPathComponent("chunks", isDirectory: true)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transcriber.splitAudioIntoChunks(
                url: source, chunkDuration: 0.4, outputDirectory: output
            )
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    private func makeAudioFile(name: String) throws -> URL {
        let url = temporaryRoot.appendingPathComponent(name)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        samples.initialize(repeating: 0, count: Int(buffer.frameLength))
        let settings: [String: Any] =
            name.hasSuffix(".wav")
            ? format.settings
            : [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
            ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        return url
    }

    func testFailedExportThrowsAndDeletesPartialOutput() async throws {
        // A session with no media tracks must fail to export.
        let source = try makeAudioFile(name: "source.m4a")
        let output = temporaryRoot.appendingPathComponent("chunks", isDirectory: true)
        do {
            _ = try await transcriber.splitAudioIntoChunks(
                url: source, chunkDuration: 0.4, outputDirectory: output,
                makeExportSession: { _ in
                    AVAssetExportSession(asset: AVMutableComposition(), presetName: AVAssetExportPresetPassthrough)
                }
            )
            XCTFail("Expected an empty asset export to fail")
        } catch let error as WhisperKitTranscriber.ChunkExportFailure {
            XCTAssertFalse(error.statusText.isEmpty)
            XCTAssertTrue(error.outputURL.path.hasPrefix(output.path))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

}
