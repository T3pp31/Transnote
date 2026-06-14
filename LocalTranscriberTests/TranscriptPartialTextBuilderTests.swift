import XCTest
@testable import LocalTranscriber

final class TranscriptPartialTextBuilderTests: XCTestCase {
    func testJoinedPresentableTextRemovesSpecialTokens() {
        let text = TranscriptPartialTextBuilder.joinedPresentableText(from: [
            "<|startoftranscript|><|ja|><|transcribe|><|0.00|>こんにちは<|2.00|>",
            "<|startoftranscript|><|nocaptions|><|endoftext|>",
        ])

        XCTAssertEqual(text, "こんにちは")
    }

    func testAppendPresentableWindowTextAccumulatesAcrossCalls() {
        var accumulated: [String] = []

        let first = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: ["こんにちは"],
            to: &accumulated
        )
        let second = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: ["世界"],
            to: &accumulated
        )

        XCTAssertEqual(first, "こんにちは")
        XCTAssertEqual(second, "こんにちは 世界")
    }

    func testAppendPresentableWindowTextIgnoresTagOnlySegments() {
        var accumulated: [String] = []

        let result = TranscriptPartialTextBuilder.appendPresentableWindowText(
            from: ["<|startoftranscript|><|nocaptions|><|endoftext|>"],
            to: &accumulated
        )

        XCTAssertNil(result)
        XCTAssertTrue(accumulated.isEmpty)
    }
}
