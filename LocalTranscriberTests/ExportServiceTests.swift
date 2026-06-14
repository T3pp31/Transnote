import XCTest
@testable import LocalTranscriber

final class ExportServiceTests: XCTestCase {
    private let exportService = ExportService()

    private var sampleTranscript: Transcript {
        Transcript(
            sourceFileName: "meeting.wav",
            language: "ja",
            fullText: "こんにちは世界",
            segments: [
                TranscriptSegment(startTime: 0.0, endTime: 1.5, text: "こんにちは"),
                TranscriptSegment(startTime: 1.5, endTime: 3.0, text: "世界")
            ]
        )
    }

    func testTXTExportReturnsFullTextOnly() throws {
        let content = try exportService.content(for: sampleTranscript, format: .txt)
        XCTAssertEqual(content, "こんにちは世界")
    }

    func testMarkdownExportIncludesHeaderAndSegments() throws {
        let content = try exportService.content(for: sampleTranscript, format: .markdown)
        XCTAssertTrue(content.contains("# Transcript: meeting.wav"))
        XCTAssertTrue(content.contains("## Full Text"))
        XCTAssertTrue(content.contains("## Segments"))
        XCTAssertTrue(content.contains("こんにちは世界"))
        XCTAssertTrue(content.contains("[00:00:00.000 --> 00:00:01.500] こんにちは"))
    }

    func testJSONExportIsValidAndRoundTrips() throws {
        let content = try exportService.content(for: sampleTranscript, format: .json)
        let data = content.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: data)
        XCTAssertEqual(decoded.sourceFileName, sampleTranscript.sourceFileName)
        XCTAssertEqual(decoded.fullText, sampleTranscript.fullText)
        XCTAssertEqual(decoded.segments.count, sampleTranscript.segments.count)
    }

    func testSRTExportFormat() throws {
        let content = try exportService.content(for: sampleTranscript, format: .srt)
        XCTAssertTrue(content.contains("1\n00:00:00,000 --> 00:00:01,500\nこんにちは"))
        XCTAssertTrue(content.contains("2\n00:00:01,500 --> 00:00:03,000\n世界"))
    }

    func testVTTExportFormat() throws {
        let content = try exportService.content(for: sampleTranscript, format: .vtt)
        XCTAssertTrue(content.hasPrefix("WEBVTT"))
        XCTAssertTrue(content.contains("00:00:00.000 --> 00:00:01.500"))
        XCTAssertTrue(content.contains("こんにちは"))
    }

    func testSRTHandlesSpecialCharacters() throws {
        let transcript = Transcript(
            sourceFileName: "special.wav",
            fullText: "Line with <tags> & quotes \"test\"",
            segments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "Line with <tags> & quotes \"test\"")
            ]
        )
        let content = try exportService.content(for: transcript, format: .srt)
        XCTAssertTrue(content.contains("Line with <tags> & quotes \"test\""))
    }

    func testExportWithEmptySegmentsUsesFullText() throws {
        let transcript = Transcript(
            sourceFileName: "empty-segments.wav",
            fullText: "Only full text",
            segments: []
        )
        let srt = try exportService.content(for: transcript, format: .srt)
        let vtt = try exportService.content(for: transcript, format: .vtt)
        XCTAssertTrue(srt.contains("Only full text"))
        XCTAssertTrue(vtt.contains("Only full text"))
    }

    func testTimestampPrecision() throws {
        let transcript = Transcript(
            sourceFileName: "precision.wav",
            fullText: "tick",
            segments: [
                TranscriptSegment(startTime: 1.234, endTime: 5.678, text: "tick")
            ]
        )
        let srt = try exportService.content(for: transcript, format: .srt)
        XCTAssertTrue(srt.contains("00:00:01,234 --> 00:00:05,678"))
    }
}
