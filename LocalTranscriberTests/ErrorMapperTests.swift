import XCTest
@testable import LocalTranscriber

final class ErrorMapperTests: XCTestCase {
    private struct UnknownTestError: Error, LocalizedError {
        var errorDescription: String? { "Internal secret error details" }
    }

    // "network" という文字列を含むが、実際はネットワークエラーではないエラー
    private struct NetworkKeywordButNotNetworkError: Error, LocalizedError {
        var errorDescription: String? { "Out-of-memory: network buffers exhausted" }
    }

    func testUnknownErrorReturnsGenericMessage() {
        let message = ErrorMapper.userMessage(for: UnknownTestError())

        XCTAssertEqual(
            message,
            L(
                "予期しないエラーが発生しました。もう一度お試しください。",
                comment: "Unexpected error"
            )
        )
        XCTAssertFalse(message.contains("Internal secret error details"))
    }

    func testModelNotDownloadedErrorMentionsToolbarButtonLabel() {
        let message = ErrorMapper.userMessage(for: AppError.modelNotDownloaded("Base"))

        XCTAssertTrue(message.contains(L("モデルをダウンロード", comment: "Download model button")))
        XCTAssertFalse(message.contains("「ダウンロード」ボタン"))
    }

    func testTranscriptionFailedWithReasonErrorDescriptionUsesUserMessage() {
        let reason = URLError(.notConnectedToInternet)
        let error = AppError.transcriptionFailedWithReason(reason)

        let expected = ErrorMapper.userMessage(for: reason)
        XCTAssertEqual(error.errorDescription, expected)
        // ネットワークエラーに分類されること（ロケール非依存の検証）
        XCTAssertNotEqual(
            error.errorDescription,
            ErrorMapper.userMessage(for: UnknownTestError())
        )
    }

    func testExportFailedWithReasonErrorDescriptionUsesUserMessage() {
        let reason = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "You don’t have permission"]
        )
        let error = AppError.exportFailedWithReason(reason)

        // exportFailedWithReason は「エクスポートに失敗しました: 」を前置して
        // userMessage を埋め込む
        XCTAssertEqual(
            error.errorDescription,
            String(
                format: NSLocalizedString("エクスポートに失敗しました: %@", comment: "Export failed"),
                ErrorMapper.userMessage(for: reason)
            )
        )
    }

    func testTranscriptionFailedWithReasonIsEquatable() {
        let a = AppError.transcriptionFailedWithReason(URLError(.notConnectedToInternet))
        let b = AppError.transcriptionFailedWithReason(URLError(.notConnectedToInternet))
        let c = AppError.transcriptionFailedWithReason(URLError(.timedOut))
        let d = AppError.transcriptionFailed("fixed message")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func testURLErrorNotConnectedToInternetClassifiedAsNetwork() {
        let message = ErrorMapper.userMessage(for: URLError(.notConnectedToInternet))

        // ネットワークエラーに分類されること（ロケール非依存の検証）
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: UnknownTestError()))
    }

    func testURLErrorNetworkConnectionLostClassifiedAsNetwork() {
        let message = ErrorMapper.userMessage(for: URLError(.networkConnectionLost))

        // 個別のメッセージを参照せず、ネットワーク分類の文言が返ることのみ検証する
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: UnknownTestError()))
    }

    func testURLErrorCancelledClassifiedAsCancelled() {
        let message = ErrorMapper.userMessage(for: URLError(.cancelled))

        XCTAssertEqual(message, ErrorMapper.userMessage(for: CancellationError()))
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: URLError(.notConnectedToInternet)))
    }

    func testErrorContainingNetworkKeywordIsNotClassifiedAsNetwork() {
        let message = ErrorMapper.userMessage(for: NetworkKeywordButNotNetworkError())

        XCTAssertEqual(
            message,
            L(
                "予期しないエラーが発生しました。もう一度お試しください。",
                comment: "Unexpected error"
            )
        )
    }

    func testOfflineKeywordIsNoLongerClassifiedAsNetwork() {
        struct OfflineError: Error, LocalizedError {
            var errorDescription: String? { "Something went offline in the cache layer" }
        }

        let message = ErrorMapper.userMessage(for: OfflineError())

        XCTAssertEqual(
            message,
            L(
                "予期しないエラーが発生しました。もう一度お試しください。",
                comment: "Unexpected error"
            )
        )
    }
}
