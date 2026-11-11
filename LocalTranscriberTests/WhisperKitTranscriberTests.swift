import AVFoundation
import WhisperKit
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
        XCTAssertEqual(chunks.map(\.overlapSeconds), [0])
        for (fraction, expected) in [(-0.5, 0.0), (0, 0), (0.5, 0.5), (1, 1), (1.5, 1)] {
            XCTAssertEqual(
                WhisperKitTranscriber.normalizedChunkProgress(
                    chunks: chunks, currentChunkIndex: 0, chunkFraction: fraction
                ),
                expected, accuracy: 0.000001
            )
        }
    }

    func testOverlappingChunkProgressDoesNotFinishBeforeLastChunk() async throws {
        let source = try makeAudioFile(name: "progress.m4a")
        let duration = try await AVURLAsset(url: source).load(.duration).seconds
        let chunks = try await transcriber.splitAudioIntoChunks(
            url: source, chunkDuration: duration / 2,
            outputDirectory: temporaryRoot.appendingPathComponent("chunks", isDirectory: true)
        )
        // チャンク長で割ると2個だが、オーバーラップを含む実際の分割結果は3個になる。
        XCTAssertEqual(chunks.count, 3)
        let expectedFractions = [
            [0.0, 1.0 / 6, 1.0 / 3],
            [1.0 / 3, 0.5, 2.0 / 3],
            [2.0 / 3, 5.0 / 6, 1.0],
        ]
        var previousFraction = 0.0
        for (index, expected) in expectedFractions.enumerated() {
            for (chunkFraction, expectedFraction) in zip([0.0, 0.5, 1.0], expected) {
                let fraction = WhisperKitTranscriber.normalizedChunkProgress(
                    chunks: chunks, currentChunkIndex: index, chunkFraction: chunkFraction
                )
                XCTAssertEqual(fraction, expectedFraction, accuracy: 0.000001)
                XCTAssertGreaterThanOrEqual(fraction, previousFraction)
                if index < chunks.count - 1 {
                    XCTAssertLessThan(fraction, 1)
                }
                previousFraction = fraction
            }
        }
        XCTAssertEqual(previousFraction, 1)
    }

    func testNonPositiveChunkDurationKeepsSingleChunkProgress() async throws {
        let source = try makeAudioFile(name: "unsplit.m4a")
        for chunkDuration in [0.0, -1.0] {
            let chunks = try await transcriber.splitAudioIntoChunks(url: source, chunkDuration: chunkDuration)
            XCTAssertEqual(chunks.map(\.url), [source])
            XCTAssertEqual(chunks.map(\.startSeconds), [0])
            for fraction in [0.0, 0.5, 1.0] {
                XCTAssertEqual(
                    WhisperKitTranscriber.normalizedChunkProgress(
                        chunks: chunks, currentChunkIndex: 0, chunkFraction: fraction
                    ),
                    fraction, accuracy: 0.000001
                )
            }
        }
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
        XCTAssertGreaterThan(first.count, 1)
        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(first.first?.startSeconds, 0)
        XCTAssertEqual(first[1].startSeconds, 0.3, accuracy: 0.001)
        XCTAssertEqual(first[0].overlapSeconds, 0)
        XCTAssertEqual(first[1].overlapSeconds, 0.1, accuracy: 0.001)
        XCTAssertTrue(Set(first.map(\.url)).isDisjoint(with: second.map(\.url)))
        for chunk in first + second {
            XCTAssertNotEqual(chunk.url, source)
            XCTAssertTrue(FileManager.default.fileExists(atPath: chunk.url.path))
            let duration = try await AVURLAsset(url: chunk.url).load(.duration).seconds
            XCTAssertGreaterThan(duration, 0)
        }
    }

    func testSplitTracksActualOverlapForFullyCoveredTail() async throws {
        let source = try makeAudioFile(name: "tail.m4a")
        let duration = try await AVURLAsset(url: source).load(.duration).seconds
        let chunks = try await transcriber.splitAudioIntoChunks(
            url: source, chunkDuration: duration * 0.6,
            outputDirectory: temporaryRoot.appendingPathComponent("tail-chunks", isDirectory: true)
        )

        XCTAssertEqual(chunks.count, 3)
        let tail = try XCTUnwrap(chunks.last)
        XCTAssertEqual(tail.overlapSeconds, duration - tail.startSeconds, accuracy: 0.001)
        XCTAssertGreaterThan(tail.overlapSeconds, 0)
        XCTAssertLessThan(tail.overlapSeconds, duration * 0.15)
    }

    func testChunkResultsRemoveOverlapFromBothTextAndSegmentsBeforeMerge() throws {
        let firstChunk = WhisperKitTranscriber.AudioChunk(url: temporaryRoot, startSeconds: 0)
        let nextChunk = WhisperKitTranscriber.AudioChunk(
            url: temporaryRoot, startSeconds: 599, overlapSeconds: 1
        )
        let first = makeResult(segments: [
            makeSegment(start: 0, end: 1, text: "はじめ"),
            makeSegment(start: 599.1, end: 599.3, text: "重複"),
            makeSegment(start: 599.4, end: 600, text: "境界内"),
        ])
        let overlapOnly = makeResult(segments: [
            makeSegment(start: 0.1, end: 0.3, text: "重複"),
        ])
        let mixed = makeResult(segments: [
            makeSegment(start: 0.4, end: 1, text: "境界内"),
            makeSegment(start: 0.8, end: 1.5, text: "境界をまたぐ発話"),
            // 同じ文字列でも、重複区間外での実際の繰り返しは残す。
            makeSegment(start: 1.5, end: 2, text: "重複"),
        ])

        let adjustedFirst = firstChunk.adjustedResult(first)
        let adjustedOverlap = nextChunk.adjustedResult(overlapOnly)
        let adjustedMixed = nextChunk.adjustedResult(mixed)
        XCTAssertTrue(adjustedOverlap.segments.isEmpty)
        XCTAssertEqual(adjustedOverlap.text, "")
        XCTAssertEqual(adjustedMixed.text, "境界をまたぐ発話 重複")
        XCTAssertEqual(adjustedMixed.language, mixed.language)
        let crossing = try XCTUnwrap(adjustedMixed.segments.first)
        let repeated = try XCTUnwrap(adjustedMixed.segments.last)
        XCTAssertEqual(crossing.start, 599.8, accuracy: 0.001)
        XCTAssertEqual(crossing.end, 600.5, accuracy: 0.001)
        XCTAssertEqual(repeated.start, 600.5, accuracy: 0.001)
        XCTAssertEqual(repeated.end, 601, accuracy: 0.001)

        let merged = TranscriptionUtilities.mergeTranscriptionResults([
            adjustedFirst, adjustedOverlap, adjustedMixed,
        ])
        XCTAssertEqual(merged.segments.map(\.text), ["はじめ", "重複", "境界内", "境界をまたぐ発話", "重複"])
        XCTAssertEqual(merged.text.components(separatedBy: "重複").count - 1, 2)
        XCTAssertEqual(merged.text.components(separatedBy: "境界内").count - 1, 1)
    }

    func testChunkWithoutOverlapPreservesTextAndAllSegments() throws {
        let result = makeResult(segments: [
            makeSegment(start: 0, end: 0, text: "先頭"),
            makeSegment(start: 0.2, end: 1, text: "発話"),
        ], text: " 先頭  発話 ")

        for startSeconds in [0.0, 599.0] {
            let chunk = WhisperKitTranscriber.AudioChunk(url: temporaryRoot, startSeconds: startSeconds)
            let adjusted = chunk.adjustedResult(result)
            XCTAssertEqual(adjusted.text, result.text)
            XCTAssertEqual(adjusted.segments.map(\.text), result.segments.map(\.text))
            let first = try XCTUnwrap(adjusted.segments.first)
            let last = try XCTUnwrap(adjusted.segments.last)
            XCTAssertEqual(first.start, Float(startSeconds), accuracy: 0.001)
            XCTAssertEqual(last.end, Float(startSeconds + 1), accuracy: 0.001)
        }
    }

    func testChunkWithOverlapButNoRemovedSegmentsPreservesText() {
        let chunk = WhisperKitTranscriber.AudioChunk(
            url: temporaryRoot, startSeconds: 599, overlapSeconds: 1
        )
        let originalText = " 境界をまたぐ発話  次の発話 "
        let result = makeResult(segments: [
            makeSegment(start: 0.9, end: 1.5, text: "境界をまたぐ発話"),
            makeSegment(start: 1.5, end: 2, text: "次の発話"),
        ], text: originalText)

        let adjusted = chunk.adjustedResult(result)
        XCTAssertEqual(adjusted.text, originalText)
        XCTAssertEqual(adjusted.segments.map(\.text), ["境界をまたぐ発話", "次の発話"])
    }

    func testPartialTextFiltersOverlapAcrossDiscoveryWindows() {
        let firstChunk = WhisperKitTranscriber.AudioChunk(url: temporaryRoot, startSeconds: 0)
        let nextChunk = WhisperKitTranscriber.AudioChunk(
            url: temporaryRoot, startSeconds: 599, overlapSeconds: 1
        )
        var completedText = ""
        let firstText = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: firstChunk.adjustedSegments([
                makeSegment(start: 599.2, end: 600, text: "重複"),
            ]).map(\.text),
            to: &completedText
        )
        XCTAssertEqual(firstText, "重複")

        let overlapText = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: nextChunk.adjustedSegments([
                makeSegment(start: 0.2, end: 1, text: "重複"),
            ]).map(\.text),
            to: &completedText
        )
        XCTAssertNil(overlapText)
        XCTAssertEqual(completedText, "重複")

        let nextText = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: nextChunk.adjustedSegments([
                makeSegment(start: 0.9, end: 1.5, text: "境界をまたぐ発話"),
                makeSegment(start: 1.5, end: 2, text: "新しい発話"),
            ]).map(\.text),
            to: &completedText
        )
        XCTAssertEqual(nextText, "重複 境界をまたぐ発話 新しい発話")
        XCTAssertEqual(completedText, nextText)
    }

    func testShortTailUsesActualOverlapBoundary() throws {
        let tail = WhisperKitTranscriber.AudioChunk(
            url: temporaryRoot, startSeconds: 0.9, overlapSeconds: 0.05
        )
        let adjusted = tail.adjustedResult(makeResult(segments: [
            makeSegment(start: 0, end: 0.05, text: "重複"),
            makeSegment(start: 0.04, end: 0.06, text: "またぐ"),
        ]))
        XCTAssertEqual(adjusted.text, "またぐ")
        XCTAssertEqual(adjusted.segments.count, 1)
        let segment = try XCTUnwrap(adjusted.segments.first)
        XCTAssertEqual(segment.start, 0.94, accuracy: 0.001)
        XCTAssertEqual(segment.end, 0.96, accuracy: 0.001)
    }

    private func makeSegment(start: Float, end: Float, text: String) -> TranscriptionSegment {
        TranscriptionSegment(
            id: 0, seek: 0, start: start, end: end, text: text,
            tokens: [], tokenLogProbs: [], temperature: 0, avgLogprob: 0,
            compressionRatio: 0, noSpeechProb: 0
        )
    }

    private func makeResult(segments: [TranscriptionSegment], text: String? = nil) -> TranscriptionResult {
        TranscriptionResult(
            text: text ?? segments.map(\.text).joined(separator: " "),
            segments: segments,
            language: "ja",
            timings: TranscriptionTimings()
        )
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
