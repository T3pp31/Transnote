import XCTest
@testable import LocalTranscriber

final class TranscriptTextSanitizerTests: XCTestCase {
    func testRemovesWhisperSpecialTokens() {
        let input = "<|startoftranscript|><|ja|><|transcribe|><|0.00|>こんにちは<|2.00|>"
        XCTAssertEqual(TranscriptTextSanitizer.sanitize(input), "こんにちは")
    }

    func testRemovesTagsFromRealWorldSample() {
        let input = "<|startoftranscript|><|nocaptions|><|endoftext|> <|startoftranscript|><|ja|><|transcribe|><|0.00|>そういう事をしてあっていました。<|2.00|>"
        XCTAssertEqual(TranscriptTextSanitizer.sanitize(input), "そういう事をしてあっていました。")
    }

    func testRemovesNoCaptionsAndEndOfTextTokens() {
        let input = "<|startoftranscript|><|nocaptions|><|endoftext|>"
        XCTAssertEqual(TranscriptTextSanitizer.sanitize(input), "")
    }

    func testCollapsesWhitespace() {
        let input = "  こんにちは   世界  "
        XCTAssertEqual(TranscriptTextSanitizer.sanitize(input), "こんにちは 世界")
    }

    func testContainsSpecialTokenArtifactsDetectsTags() {
        XCTAssertTrue(
            TranscriptTextSanitizer.containsSpecialTokenArtifacts("<|startoftranscript|>こんにちは")
        )
    }

    func testContainsSpecialTokenArtifactsReturnsFalseForCleanText() {
        XCTAssertFalse(TranscriptTextSanitizer.containsSpecialTokenArtifacts("こんにちは世界"))
    }

    func testPresentableTextReturnsNilForTagOnlyInput() {
        XCTAssertNil(
            TranscriptTextSanitizer.presentableText(
                from: "<|startoftranscript|><|nocaptions|><|endoftext|>"
            )
        )
    }

    func testSanitizationPreservesUnicodeAndExistingWhitespaceRules() {
        let cases: [(raw: String, expected: String)] = [
            ("<｜ja｜>こんにちは<｜2.00｜>", "こんにちは"),
            ("🌏<|ja|>  こんにちは<｜endoftext｜>👩🏽‍💻", "🌏 こんにちは👩🏽‍💻"),
            ("<|ja|>e\u{301}<|2.00|>🌏", "e\u{301}🌏"),
            (" \tこんにちは  世界\n次\tの行 \n", "こんにちは 世界\n次\tの行"),
            ("<|broken", "broken"),
            ("broken|>", "broken"),
            ("<｜broken", "broken"),
            ("broken｜>", "broken"),
            ("<|a|b|>", "a|b"),
            ("<| |> <｜ ｜>", ""),
            ("<|ja|>$1 \\ text", "$1 \\ text"),
        ]

        for (raw, expected) in cases {
            XCTAssertEqual(TranscriptTextSanitizer.sanitize(raw), expected, "raw: \(raw)")
            XCTAssertEqual(
                TranscriptTextSanitizer.presentableText(from: raw),
                expected.isEmpty ? nil : expected,
                "raw: \(raw)"
            )
        }
    }

    func testArtifactDetectionHandlesFullWidthAndIncompleteTokens() {
        let artifacts = [
            "<|ja|>", "<｜ja｜>", "<||>", "<｜｜>",
            "<|broken", "broken|>", "<｜broken", "broken｜>",
            "<|", "|>", "<｜", "｜>",
            "<|ja｜>", "<｜ja|>", "<|a|b|>", "<|ja\n|>",
            "<|\u{301}ja|>\u{301}", "<｜\u{301}ja｜>\u{301}",
        ]
        for artifact in artifacts {
            for text in [artifact, "🌏e\u{301}\(artifact)こんにちは👩🏽‍💻"] {
                XCTAssertTrue(TranscriptTextSanitizer.containsSpecialTokenArtifacts(text), text)
            }
        }
        for text in ["", "🌏こんにちは👩🏽‍💻", "a | b", "<html>", "｜", "< | >", "< ｜ >"] {
            XCTAssertFalse(TranscriptTextSanitizer.containsSpecialTokenArtifacts(text), text)
        }
    }

    func testPresentableTextRejectsArtifactsCreatedByRemoval() {
        let cases: [(raw: String, sanitized: String)] = [
            ("<<||", "<|"),
            ("||>>", "|>"),
            ("<<｜｜", "<｜"),
            ("｜｜>>", "｜>"),
            ("<<||ja||>>", "<|ja|>"),
            ("<<｜｜ja｜｜>>", "<｜ja｜>"),
            ("こんにちは<<｜|🌏", "こんにちは<|🌏"),
        ]

        for (raw, sanitized) in cases {
            XCTAssertEqual(TranscriptTextSanitizer.sanitize(raw), sanitized, "raw: \(raw)")
            XCTAssertTrue(TranscriptTextSanitizer.containsSpecialTokenArtifacts(sanitized), "raw: \(raw)")
            XCTAssertNil(TranscriptTextSanitizer.presentableText(from: raw), "raw: \(raw)")
        }
    }

    func testPresentableTextReturnsCleanText() {
        XCTAssertEqual(
            TranscriptTextSanitizer.presentableText(
                from: "<|startoftranscript|><|ja|><|0.00|>こんにちは<|2.00|>"
            ),
            "こんにちは"
        )
    }
}
