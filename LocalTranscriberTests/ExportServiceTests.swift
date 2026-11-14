import UniformTypeIdentifiers
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

    func testExportWithEmptySegmentsDoesNotUseZeroDuration() throws {
        let transcript = Transcript(
            sourceFileName: "empty-segments.wav",
            fullText: "Only full text",
            segments: []
        )
        let srt = try exportService.content(for: transcript, format: .srt)
        let vtt = try exportService.content(for: transcript, format: .vtt)
        XCTAssertFalse(srt.contains("00:00:00,000 --> 00:00:00,000"))
        XCTAssertFalse(vtt.contains("00:00:00.000 --> 00:00:00.000"))
    }

    func testExportWithEmptySegmentsUsesMinimalDuration() throws {
        let transcript = Transcript(
            sourceFileName: "empty-segments.wav",
            fullText: "Only full text",
            segments: []
        )
        let srt = try exportService.content(for: transcript, format: .srt)
        let vtt = try exportService.content(for: transcript, format: .vtt)
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:01,000"))
        XCTAssertTrue(vtt.contains("00:00:00.000 --> 00:00:01.000"))
    }
    func testExportRejectsSegmentWithStartAfterEnd() throws {
        let transcript = Transcript(
            sourceFileName: "bad.wav",
            fullText: "bad",
            segments: [TranscriptSegment(startTime: 5, endTime: 2, text: "bad")]
        )
        XCTAssertThrowsError(try exportService.content(for: transcript, format: .srt))
    }

    func testExportRejectsOverlappingSegments() throws {
        let transcript = Transcript(
            sourceFileName: "overlap.wav",
            fullText: "overlap",
            segments: [
                TranscriptSegment(startTime: 0, endTime: 3, text: "a"),
                TranscriptSegment(startTime: 2, endTime: 4, text: "b")
            ]
        )
        XCTAssertThrowsError(try exportService.content(for: transcript, format: .srt))
    }

    func testExportRejectsNegativeStartTime() throws {
        let transcript = Transcript(
            sourceFileName: "negative.wav",
            fullText: "negative",
            segments: [TranscriptSegment(startTime: -1, endTime: 2, text: "bad")]
        )
        XCTAssertThrowsError(try exportService.content(for: transcript, format: .vtt))
    }

    func testExportRejectsHugeFiniteTimestamp() throws {
        let transcript = Transcript(
            sourceFileName: "huge.wav",
            fullText: "huge",
            segments: [
                TranscriptSegment(startTime: 0, endTime: Double(Int.max), text: "huge")
            ]
        )

        XCTAssertThrowsError(try exportService.content(for: transcript, format: .srt))
    }

    func testExportAcceptsValidSegments() throws {
        let transcript = Transcript(
            sourceFileName: "valid.wav",
            fullText: "valid",
            segments: [
                TranscriptSegment(startTime: 0, endTime: 2, text: "a"),
                TranscriptSegment(startTime: 2, endTime: 4, text: "b")
            ]
        )
        XCTAssertNoThrow(try exportService.content(for: transcript, format: .srt))
    }

    // MARK: - schemaVersion (#199)

    func testJSONExportIncludesSchemaVersion() throws {
        let content = try exportService.content(for: sampleTranscript, format: .json)
        let data = try XCTUnwrap(content.data(using: .utf8))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["schemaVersion"] as? Int, Transcript.currentSchemaVersion)
    }

    func testJSONDecodeWithoutSchemaVersionUsesDefault() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "sourceFileName": "test.wav",
          "language": "ja",
          "createdAt": "2026-01-01T00:00:00Z",
          "fullText": "hello",
          "segments": []
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, Transcript.currentSchemaVersion)
    }

    // MARK: - markdown escape (#200)

    func testMarkdownEscapesSpecialCharactersInFileName() throws {
        let transcript = Transcript(
            sourceFileName: "meeting [final] #1.wav",
            fullText: "hello",
            segments: []
        )
        let content = try exportService.content(for: transcript, format: .markdown)
        XCTAssertTrue(content.contains("meeting \\[final\\] \\#1.wav"))
    }

    func testMarkdownEscapesSpecialCharactersInSegmentText() throws {
        let transcript = Transcript(
            sourceFileName: "test.wav",
            fullText: "full text",
            segments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "text *italic* _under_ [link]")
            ]
        )
        let content = try exportService.content(for: transcript, format: .markdown)
        let segments = try XCTUnwrap(content.range(of: "## Segments")).upperBound
        XCTAssertTrue(content[segments...].contains("- [00:00:00.000 --> 00:00:01.000] text \\*italic\\* \\_under\\_ \\[link\\]"))
    }

    func testMarkdownKeepsMultilineSegmentInSingleListItem() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let text = [
                "先頭", "- bullet", "+ bullet", "1. ordered", "> quote",
                "```swift", "code", "```", "~~~", "---", "", "末尾"
            ].joined(separator: newline)
            let transcript = Transcript(
                sourceFileName: "test.wav",
                fullText: "full text",
                segments: [
                    TranscriptSegment(startTime: 0, endTime: 1, text: text),
                    TranscriptSegment(startTime: 1, endTime: 2, text: "次のセグメント")
                ]
            )

            let content = try exportService.content(for: transcript, format: .markdown)

            XCTAssertEqual(content, [
                "# Transcript: test.wav", "", "## Full Text", "", "full text", "", "## Segments", "",
                #"- [00:00:00.000 --> 00:00:01.000] 先頭 - bullet + bullet 1. ordered \> quote \`\`\`swift code \`\`\` ~~~ ---  末尾"#,
                "- [00:00:01.000 --> 00:00:02.000] 次のセグメント"
            ].joined(separator: "\n"), "改行: \(newline.debugDescription)")
        }
    }

    func testMarkdownEscapesCodeAndHTMLWithoutChangingFullText() throws {
        let text = #"`code` ``nested ` code`` <b>text</b> <https://example.com> \` \<tag>"#
        let transcript = Transcript(
            sourceFileName: "test`<raw>.wav",
            language: "ja`<raw>",
            fullText: "`code`\n<b>full text</b>",
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: text)]
        )

        let content = try exportService.content(for: transcript, format: .markdown)

        XCTAssertEqual(content, [
            #"# Transcript: test\`\<raw\>.wav"#, "",
            #"Language: ja\`\<raw\>"#, "",
            "## Full Text", "", "`code`\n<b>full text</b>", "", "## Segments", "",
            #"- [00:00:00.000 --> 00:00:01.000] \`code\` \`\`nested \` code\`\` \<b\>text\</b\> \<https://example.com\> \\\` \\\<tag\>"#
        ].joined(separator: "\n"))
    }

    func testNonMarkdownExportsPreserveMultilineTextAndSpecialCharacters() throws {
        let text = "先頭\r\n- item\n`code`\r<tag>"
        let transcript = Transcript(
            sourceFileName: "test.wav",
            fullText: text,
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: text)]
        )

        XCTAssertEqual(try exportService.content(for: transcript, format: .txt), text)
        XCTAssertEqual(
            try exportService.content(for: transcript, format: .srt),
            "1\n00:00:00,000 --> 00:00:01,000\n\(text)"
        )
        XCTAssertEqual(
            try exportService.content(for: transcript, format: .vtt),
            "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\n\(text)"
        )
        let json = try exportService.content(for: transcript, format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.fullText, text)
        XCTAssertEqual(decoded.segments.first?.text, text)
    }

}

@MainActor
final class MainWindowViewModelExportTests: XCTestCase {
    private var tempRoot: URL!
    private var originalExportBookmark: Data?
    private let originalTranscript = Transcript(
        sourceFileName: "meeting.wav",
        fullText: "元の文字起こし",
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    private let editedText = "編集した文字起こし"

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let key = SecurityScopedFileAccess.lastExportDirectoryKey
        originalExportBookmark = UserDefaults.standard.data(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDownWithError() throws {
        let key = SecurityScopedFileAccess.lastExportDirectoryKey
        if let originalExportBookmark {
            UserDefaults.standard.set(originalExportBookmark, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testCancelledExportPreservesUnsavedChanges() throws {
        let viewModel = makeViewModel(exportURL: nil)
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.exportTranscript(format: .txt)

        assertUnsavedStateUnchanged(viewModel)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.toast)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: tempRoot.path).isEmpty)
    }

    func testFailedWritePreservesUnsavedChangesAndRetryCommitsLatestEdits() throws {
        // 存在しない親ディレクトリで、権限や空き容量に依存せず実際の write を失敗させる。
        let destination = tempRoot.appendingPathComponent("missing/result.txt")
        let viewModel = makeViewModel(exportURL: destination)
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        viewModel.exportTranscript(format: .txt)

        assertUnsavedStateUnchanged(viewModel)
        XCTAssertNotNil(viewModel.inlineErrorMessage)
        XCTAssertTrue(viewModel.canRetryError)
        XCTAssertNil(viewModel.toast)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let latestText = "失敗後にさらに編集した文字起こし"
        viewModel.transcriptText = latestText
        viewModel.retryLastAction()

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), latestText)
        XCTAssertEqual(viewModel.currentTranscript?.fullText, latestText)
        XCTAssertNotEqual(viewModel.currentTranscript?.updatedAt, originalTranscript.updatedAt)
        XCTAssertEqual(viewModel.baselineTranscriptText, latestText)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.toast)
    }

    func testSuccessfulExportCommitsTheWrittenTranscript() throws {
        let destination = tempRoot.appendingPathComponent("result.json")
        let viewModel = makeViewModel(exportURL: destination)

        viewModel.exportTranscript(format: .json)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(Transcript.self, from: Data(contentsOf: destination))
        let committed = try XCTUnwrap(viewModel.currentTranscript)
        XCTAssertEqual(exported.id, originalTranscript.id)
        XCTAssertEqual(exported.fullText, editedText)
        XCTAssertEqual(committed.fullText, exported.fullText)
        let exportedDate = try XCTUnwrap(exported.updatedAt)
        let committedDate = try XCTUnwrap(committed.updatedAt)
        XCTAssertNotEqual(committedDate, originalTranscript.updatedAt)
        // JSON の ISO 8601 日時は秒未満を含まない。
        XCTAssertEqual(exportedDate.timeIntervalSince1970, committedDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(viewModel.baselineTranscriptText, exported.fullText)
        XCTAssertEqual(viewModel.transcriptText, editedText)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.toast)
    }

    private func makeViewModel(exportURL: URL?) -> MainWindowViewModel {
        let viewModel = MainWindowViewModel(
            fileAccess: SecurityScopedFileAccess(),
            savePanelPresenter: StubSavePanelPresenter(url: exportURL)
        )
        viewModel.currentTranscript = originalTranscript
        viewModel.baselineTranscriptText = originalTranscript.fullText
        viewModel.transcriptText = editedText
        return viewModel
    }

    private func assertUnsavedStateUnchanged(
        _ viewModel: MainWindowViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(viewModel.currentTranscript?.id, originalTranscript.id, file: file, line: line)
        XCTAssertEqual(viewModel.currentTranscript?.fullText, originalTranscript.fullText, file: file, line: line)
        XCTAssertEqual(viewModel.currentTranscript?.updatedAt, originalTranscript.updatedAt, file: file, line: line)
        XCTAssertEqual(viewModel.baselineTranscriptText, originalTranscript.fullText, file: file, line: line)
        XCTAssertEqual(viewModel.transcriptText, editedText, file: file, line: line)
        XCTAssertTrue(viewModel.hasUnsavedChanges, file: file, line: line)
    }
}

private struct StubSavePanelPresenter: SavePanelPresenting {
    let url: URL?

    func presentSavePanel(defaultFileName: String, allowedContentTypes: [UTType], initialDirectoryURL: URL?) -> URL? {
        url
    }
}
