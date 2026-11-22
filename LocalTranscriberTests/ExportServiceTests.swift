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
        // computed property のため、比較対象は同じインスタンスを保持する。
        let transcript = sampleTranscript
        let content = try exportService.content(for: transcript, format: .json)
        let data = content.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: data)
        XCTAssertEqual(decoded.id, transcript.id)
        XCTAssertEqual(decoded.sourceFileName, transcript.sourceFileName)
        XCTAssertEqual(decoded.language, transcript.language)
        XCTAssertEqual(decoded.fullText, transcript.fullText)
        XCTAssertEqual(decoded.segments.count, transcript.segments.count)
        for (decodedSegment, expected) in zip(decoded.segments, transcript.segments) {
            XCTAssertEqual(decodedSegment.id, expected.id)
            XCTAssertEqual(decodedSegment.startTime, expected.startTime)
            XCTAssertEqual(decodedSegment.endTime, expected.endTime)
            XCTAssertEqual(decodedSegment.text, expected.text)
        }
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
                #"- [00:00:00.000 --> 00:00:01.000] 先頭 - bullet + bullet 1. ordered &gt; quote \`\`\`swift code \`\`\` \~\~\~ ---  末尾"#,
                "- [00:00:01.000 --> 00:00:02.000] 次のセグメント"
            ].joined(separator: "\n"), "改行: \(newline.debugDescription)")
        }
    }

    func testMarkdownEscapesNewlinesTildeAndPipeInFileNameLanguageAndSegments() throws {
        for newline in ["\n", "\r\n", "\r"] {
            let transcript = Transcript(
                sourceFileName: "meeting~~draft~~|1\(newline)## Injected.wav",
                language: "ja~~v1~~|alt\(newline)- item",
                fullText: "body",
                segments: [
                    TranscriptSegment(startTime: 0, endTime: 1, text: "~~strike~~ | col")
                ]
            )

            let content = try exportService.content(for: transcript, format: .markdown)

            XCTAssertEqual(content, [
                ##"# Transcript: meeting\~\~draft\~\~\|1 \#\# Injected.wav"##, "",
                #"Language: ja\~\~v1\~\~\|alt - item"#, "",
                "## Full Text", "", "body", "", "## Segments", "",
                #"- [00:00:00.000 --> 00:00:01.000] \~\~strike\~\~ \| col"#
            ].joined(separator: "\n"), "改行: \(newline.debugDescription)")
        }
    }

    func testMarkdownEscapesCodeAndHTMLWhilePreservingFullTextMarkdown() throws {
        let text = #"`code` ``nested ` code`` <b>text</b> <https://example.com> \` \<tag>"#
        let transcript = Transcript(
            sourceFileName: "test`<raw>.wav",
            language: "ja`<raw>",
            fullText: "`code`\n<b>full text</b>",
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: text)]
        )

        let content = try exportService.content(for: transcript, format: .markdown)

        XCTAssertEqual(content, [
            #"# Transcript: test\`&lt;raw&gt;.wav"#, "",
            #"Language: ja\`&lt;raw&gt;"#, "",
            "## Full Text", "", "`code`\n&lt;b&gt;full text&lt;/b&gt;", "", "## Segments", "",
            #"- [00:00:00.000 --> 00:00:01.000] \`code\` \`\`nested \` code\`\` &lt;b&gt;text&lt;/b&gt; &lt;https://example.com&gt; \\\` \\&lt;tag&gt;"#
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
            "1\n00:00:00,000 --> 00:00:01,000\n先頭\n- item\n`code`\n<tag>"
        )
        XCTAssertEqual(
            try exportService.content(for: transcript, format: .vtt),
            "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\n先頭\n- item\n`code`\n&lt;tag&gt;"
        )
        let json = try exportService.content(for: transcript, format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.fullText, text)
        XCTAssertEqual(decoded.segments.first?.text, text)
    }

    // MARK: - Markdown HTML escape (#788)

    func testMarkdownEscapesHTMLInAllVariableFields() throws {
        let cases = [
            (
                input: #"<script>alert("x" & 'y')</script>"#,
                escaped: "&lt;script&gt;alert(&quot;x&quot; &amp; &#39;y&#39;)&lt;/script&gt;"
            ),
            (
                input: #"<img src=x onerror="alert('x')">"#,
                escaped: "&lt;img src=x onerror=&quot;alert(&#39;x&#39;)&quot;&gt;"
            )
        ]
        for testCase in cases {
            let transcript = Transcript(
                sourceFileName: testCase.input,
                language: testCase.input,
                fullText: testCase.input,
                segments: [TranscriptSegment(startTime: 0, endTime: 1, text: testCase.input)]
            )
            let content = try exportService.content(for: transcript, format: .markdown)
            let expected = """
            # Transcript: \(testCase.escaped)

            Language: \(testCase.escaped)

            ## Full Text

            \(testCase.escaped)

            ## Segments

            - [00:00:00.000 --> 00:00:01.000] \(testCase.escaped)
            """
            XCTAssertEqual(content, expected, testCase.input)
        }
    }

    func testMarkdownPreservesFullTextFormattingAndLiteralEntities() throws {
        let transcript = Transcript(
            sourceFileName: "test.wav",
            fullText: "# 見出し\n\n*強調* _下線_ [link](https://example.invalid) `code`\n&lt;tag&gt; &amp; &#39;",
            segments: []
        )
        let content = try exportService.content(for: transcript, format: .markdown)
        let expected = """
        # Transcript: test.wav

        ## Full Text

        # 見出し

        *強調* _下線_ [link](https://example.invalid) `code`
        &amp;lt;tag&amp;gt; &amp;amp; &amp;#39;

        ## Segments

        """
        XCTAssertEqual(content, expected)
    }

    func testMarkdownPreservesLiteralHTMLCharactersInsideCode() throws {
        let codeSamples = [
            #"日本語 `if a < b && s == "x" { print('y') }`"#,
            #"``nested ` <tag> & "quoted"``"#,
            "`first\n<tag> & \"quoted\"`",
            "```swift\nprint(\"hello\")\nif a < b && c > d {}\n```",
            "~~~\n<tag> & \"quoted\"\n~~~",
            "    print(\"hello\")\n    <tag> & 'quoted'\n",
            "\tprint(\"hello\")\n\t<tag> & 'quoted'\n",
            "> ```swift\n> if a < b && s == \"x\" {}\n> ```",
            "- item\n\n  ```swift\n  print(\"hello\")\n  ```"
        ]
        for newline in ["\n", "\r\n", "\r"] {
            for sample in codeSamples {
                let code = sample.replacingOccurrences(of: "\n", with: newline)
                let fullText = code + newline + newline + "<b>raw</b>"
                let transcript = Transcript(sourceFileName: "test.wav", fullText: fullText)
                let content = try exportService.content(for: transcript, format: .markdown)
                let expected = code + newline + newline + "&lt;b&gt;raw&lt;/b&gt;"
                XCTAssertTrue(content.contains("## Full Text\n\n" + expected + "\n\n## Segments"), fullText.debugDescription)
            }
        }
    }

    func testMarkdownDoesNotTreatBackticksInsideRawHTMLAsCode() throws {
        for text in [
            #"<img title="`code`" src=x onerror="alert('x')">"#,
            "<script>\n`if a < b && s == \"x\"`\n</script>"
        ] {
            let transcript = Transcript(sourceFileName: "test.wav", fullText: text)
            let content = try exportService.content(for: transcript, format: .markdown)
            XCTAssertFalse(content.contains("<img"))
            XCTAssertFalse(content.contains("<script>"))
            XCTAssertFalse(content.contains("</script>"))
        }
    }

    func testHTMLEscapingIsLimitedToMarkdownExport() throws {
        let text = #"日本語 <script>alert("x" & 'y')</script>"#
        let transcript = Transcript(
            sourceFileName: text,
            language: text,
            fullText: text,
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: text)]
        )
        XCTAssertEqual(try exportService.content(for: transcript, format: .txt), text)
        XCTAssertTrue(try exportService.content(for: transcript, format: .srt).hasSuffix(text))
        // VTT は WebVTT のタグ・実体記号 (&, <, >) のみエスケープし、引用符は Markdown HTML のように変換しない。
        XCTAssertTrue(
            try exportService.content(for: transcript, format: .vtt)
                .hasSuffix(#"日本語 &lt;script&gt;alert("x" &amp; 'y')&lt;/script&gt;"#)
        )
        let json = try exportService.content(for: transcript, format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: XCTUnwrap(json.data(using: .utf8)))
        XCTAssertEqual(decoded.sourceFileName, text)
        XCTAssertEqual(decoded.language, text)
        XCTAssertEqual(decoded.fullText, text)
        XCTAssertEqual(decoded.segments.first?.text, text)
    }

    // MARK: - SRT/VTT cue injection hardening (#842)

    func testSRTAndVTTPreventBlankLineAndTimestampCueInjection() throws {
        let payloads = [
            "正規テキスト\n\n2\n00:00:05,000 --> 00:00:09,000\n偽装キュー",
            "正規テキスト\r\n\r\n00:00:05.000 --> 00:00:09.000\r\n偽装キュー",
            "正規テキスト\r\r   \r00:00:05.000 --> 00:00:09.000\r偽装キュー",
            "正規テキスト\n   \t  \nNOTE injected comment\n\n00:00:05.000 --> 00:00:09.000",
        ]

        for payload in payloads {
            let transcript = Transcript(
                sourceFileName: "cue.wav",
                fullText: payload,
                segments: [TranscriptSegment(startTime: 0, endTime: 2, text: payload)]
            )

            let srt = try exportService.content(for: transcript, format: .srt)
            let srtBlocks = srt.components(separatedBy: "\n\n")
            XCTAssertEqual(srtBlocks.count, 1, "SRT は 1 セグメント 1 キューを保証すること: \(payload.debugDescription)")
            let srtTextLines = srtBlocks[0].components(separatedBy: "\n").dropFirst(2)
            for line in srtTextLines {
                XCTAssertFalse(line.contains("-->"), "SRT 本文行に --> を含めてはならない: \(line)")
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            let vtt = try exportService.content(for: transcript, format: .vtt)
            let vttBlocks = vtt.components(separatedBy: "\n\n")
            XCTAssertEqual(vttBlocks.count, 2, "VTT は WEBVTT ヘッダ + 1 キューのみであること: \(payload.debugDescription)")
            XCTAssertEqual(vttBlocks[0], "WEBVTT")
            let vttTextLines = vttBlocks[1].components(separatedBy: "\n").dropFirst(1)
            for line in vttTextLines {
                XCTAssertFalse(line.contains("-->"), "VTT 本文行に --> を含めてはならない: \(line)")
                XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    func testSRTAndVTTStripControlCharactersAndSanitizeFallbackSegment() throws {
        let crafted = "hello\u{0000}\u{0007}\u{001B}\u{007F}\n\n00:01:00.000 --> 00:02:00.000\n<v Speaker><00:00:01.000>spoof"
        let transcript = Transcript(
            sourceFileName: "fallback.wav",
            fullText: crafted,
            segments: []
        )

        let srt = try exportService.content(for: transcript, format: .srt)
        XCTAssertEqual(srt.components(separatedBy: "\n\n").count, 1)
        XCTAssertFalse(srt.contains("\u{0000}"))
        XCTAssertFalse(srt.contains("\u{0007}"))
        XCTAssertFalse(srt.contains("\u{001B}"))
        XCTAssertFalse(srt.contains("\u{007F}"))
        XCTAssertTrue(srt.contains("00:01:00.000 -- > 00:02:00.000"))

        let vtt = try exportService.content(for: transcript, format: .vtt)
        XCTAssertEqual(vtt.components(separatedBy: "\n\n").count, 2)
        XCTAssertFalse(vtt.contains("\u{0000}"))
        XCTAssertTrue(vtt.contains("00:01:00.000 --&gt; 00:02:00.000"))
        XCTAssertTrue(vtt.contains("&lt;v Speaker&gt;&lt;00:00:01.000&gt;spoof"))
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
