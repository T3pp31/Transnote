import XCTest
@testable import LocalTranscriber

final class ErrorMapperTests: XCTestCase {
    private struct UnknownTestError: Error, LocalizedError {
        var errorDescription: String? { "Internal secret error details" }
    }

    func testUnknownErrorReturnsGenericMessage() {
        let message = ErrorMapper.userMessage(for: UnknownTestError())

        XCTAssertEqual(message, "予期しないエラーが発生しました。もう一度お試しください。")
        XCTAssertFalse(message.contains("Internal secret error details"))
    }
}
