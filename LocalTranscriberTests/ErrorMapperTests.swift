import XCTest
@testable import LocalTranscriber

final class ErrorMapperTests: XCTestCase {
    private struct UnknownTestError: Error, LocalizedError {
        var errorDescription: String? { "Internal secret error details" }
    }

    private struct DescribedTestError: LocalizedError {
        let errorDescription: String?
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

    func testURLErrorNotConnectedToInternetClassifiedAsNetwork() {
        let message = ErrorMapper.userMessage(for: URLError(.notConnectedToInternet))

        // ネットワーク分類の文言を直接確認する
        XCTAssertEqual(
            message,
            L(
                "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。",
                comment: "Model download network failure"
            )
        )
        XCTAssertEqual(
            message,
            ErrorMapper.userMessage(for: URLError(.networkConnectionLost))
        )
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: URLError(.cancelled)))
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: UnknownTestError()))
    }

    func testURLErrorNetworkConnectionLostClassifiedAsNetwork() {
        let message = ErrorMapper.userMessage(for: URLError(.networkConnectionLost))

        // ネットワーク分類の文言を直接確認する
        XCTAssertEqual(
            message,
            L(
                "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。",
                comment: "Model download network failure"
            )
        )
        XCTAssertEqual(
            message,
            ErrorMapper.userMessage(for: URLError(.notConnectedToInternet))
        )
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: URLError(.cancelled)))
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: UnknownTestError()))
    }

    func testURLErrorCancelledClassifiedAsCancelled() {
        let message = ErrorMapper.userMessage(for: URLError(.cancelled))

        // 両方のキャンセル型が汎用メッセージに退行しても検出できるよう、文言を直接確認する
        XCTAssertEqual(
            message,
            L("処理がキャンセルされました。", comment: "Operation cancelled")
        )
        XCTAssertEqual(message, ErrorMapper.userMessage(for: CancellationError()))
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: URLError(.notConnectedToInternet)))
        XCTAssertNotEqual(message, ErrorMapper.userMessage(for: UnknownTestError()))
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

    func testUnknownErrorPhrasesDoNotDetermineClassification() {
        let descriptions = [
            "Out-of-memory while allocating network connection buffers",
            "Corrupt model metadata: NETWORK ERROR is not a valid layer name",
            "Model file not found in diagnostic text; actual failure is out-of-memory",
            "Models are unavailable is a cached status; actual failure is out-of-memory",
            "Model not found in diagnostic text; actual failure is out-of-memory",
        ]
        let expected = L(
            "予期しないエラーが発生しました。もう一度お試しください。",
            comment: "Unexpected error"
        )

        for description in descriptions {
            let reason = DescribedTestError(errorDescription: description)
            XCTAssertEqual(ErrorMapper.userMessage(for: reason), expected, description)
            XCTAssertEqual(
                AppError.transcriptionFailedWithReason(reason).errorDescription,
                expected,
                description
            )
            XCTAssertEqual(
                AppError.exportFailedWithReason(reason).errorDescription,
                String(
                    format: L("エクスポートに失敗しました: %@", comment: "Export failed"),
                    expected
                ),
                description
            )
        }
    }

    func testNetworkURLCodesAreClassifiedRegardlessOfDescription() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut,
            .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable,
        ]
        let expected = L(
            "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。",
            comment: "Model download network failure"
        )

        for code in codes {
            let error = URLError(code, userInfo: [NSLocalizedDescriptionKey: "Model file not found"])
            XCTAssertEqual(ErrorMapper.userMessage(for: error), expected, "\(code)")
        }
    }

    func testOtherURLCodesAreNotClassifiedByDescription() {
        for description in ["network connection", "network error", "Model file not found"] {
            let error = URLError(
                .cannotDecodeContentData,
                userInfo: [NSLocalizedDescriptionKey: description]
            )
            XCTAssertEqual(
                ErrorMapper.userMessage(for: error),
                L(
                    "予期しないエラーが発生しました。もう一度お試しください。",
                    comment: "Unexpected error"
                ),
                description
            )
        }
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
