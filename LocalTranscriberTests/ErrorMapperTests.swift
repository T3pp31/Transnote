import XCTest
@testable import LocalTranscriber

final class ErrorMapperTests: XCTestCase {
    private struct UnknownTestError: Error, LocalizedError {
        var errorDescription: String? { "Internal secret error details" }
    }

    func testUnknownErrorReturnsGenericMessage() {
        let message = ErrorMapper.userMessage(for: UnknownTestError())

        XCTAssertEqual(
            message,
            NSLocalizedString(
                "予期しないエラーが発生しました。もう一度お試しください。",
                comment: "Unexpected error"
            )
        )
        XCTAssertFalse(message.contains("Internal secret error details"))
    }

    func testModelNotDownloadedErrorMentionsToolbarButtonLabel() {
        let message = ErrorMapper.userMessage(for: AppError.modelNotDownloaded("Base"))

        XCTAssertTrue(message.contains(NSLocalizedString("モデルをダウンロード", comment: "Download model button")))
        XCTAssertFalse(message.contains("「ダウンロード」ボタン"))
    }
}
