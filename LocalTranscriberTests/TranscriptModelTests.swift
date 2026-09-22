import XCTest
@testable import LocalTranscriber

final class TranscriptModelTests: XCTestCase {
    func testTranscriptCodableRoundTrip() throws {
        let original = Transcript(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            sourceFileName: "sample.wav",
            language: "en",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fullText: "Hello world",
            segments: [
                TranscriptSegment(
                    id: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!,
                    startTime: 0.0,
                    endTime: 1.2,
                    text: "Hello"
                ),
                TranscriptSegment(
                    id: UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-123456789012")!,
                    startTime: 1.2,
                    endTime: 2.4,
                    text: "world"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.sourceFileName, original.sourceFileName)
        XCTAssertEqual(decoded.language, original.language)
        XCTAssertEqual(decoded.fullText, original.fullText)
        XCTAssertEqual(decoded.segments.count, original.segments.count)
        XCTAssertEqual(decoded.segments[0].text, "Hello")
        XCTAssertEqual(decoded.segments[1].endTime, 2.4)
    }

    func testTranscriptSegmentIdentifiable() {
        let segment = TranscriptSegment(startTime: 0, endTime: 1, text: "test")
        XCTAssertNotNil(segment.id)
    }

    func testExportFormatFileExtensions() {
        XCTAssertEqual(ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ExportFormat.srt.fileExtension, "srt")
        XCTAssertEqual(ExportFormat.vtt.fileExtension, "vtt")
    }
    // MARK: - History store (#213)

    func testHistoryStoreSaveAndRecent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(historyRoot: root)

        let transcript = Transcript(
            sourceFileName: "meeting.wav",
            language: "ja",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fullText: "こんにちは",
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "こんにちは")]
        )

        try store.save(transcript)
        let recent = store.recent()

        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.sourceFileName, "meeting.wav")
        XCTAssertEqual(recent.first?.fullText, "こんにちは")
    }

    func testHistoryStoreDelete() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(historyRoot: root)

        let transcript = Transcript(sourceFileName: "a.wav", fullText: "hello")
        try store.save(transcript)
        store.delete(transcript)

        XCTAssertTrue(store.recent().isEmpty)
    }
}
