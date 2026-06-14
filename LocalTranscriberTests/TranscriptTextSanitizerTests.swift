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

    func testPresentableTextReturnsCleanText() {
        XCTAssertEqual(
            TranscriptTextSanitizer.presentableText(
                from: "<|startoftranscript|><|ja|><|0.00|>こんにちは<|2.00|>"
            ),
            "こんにちは"
        )
    }
}
