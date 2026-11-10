import XCTest
@testable import LocalTranscriber

final class StorageSizeStateTests: XCTestCase {
    func testRefreshReturnsToCalculatingAndPublishesSize() throws {
        var state = StorageSizeState()
        XCTAssertTrue(state.isCalculating)
        XCTAssertFalse(state.isClearing)

        let initial = try XCTUnwrap(state.beginRefresh())
        state.finishRefresh(bytes: 1024, generation: initial)
        XCTAssertEqual(state.sizeText, formattedSize(1024))
        XCTAssertFalse(state.isCalculating)

        let refresh = try XCTUnwrap(state.beginRefresh())
        XCTAssertEqual(state.sizeText, "計算中…")
        XCTAssertTrue(state.isCalculating)
        state.finishRefresh(bytes: 2048, generation: refresh)
        XCTAssertEqual(state.sizeText, formattedSize(2048))
        XCTAssertFalse(state.isCalculating)
    }

    func testOnlyLatestRefreshCanPublishRegardlessOfCompletionOrder() throws {
        for oldCompletesFirst in [true, false] {
            var state = StorageSizeState()
            let old = try XCTUnwrap(state.beginRefresh())
            let latest = try XCTUnwrap(state.beginRefresh())

            if oldCompletesFirst {
                state.finishRefresh(bytes: 1_000_000_000, generation: old)
                XCTAssertEqual(state.sizeText, "計算中…")
                XCTAssertTrue(state.isCalculating)
            }
            state.finishRefresh(bytes: 2048, generation: latest)
            if !oldCompletesFirst {
                state.finishRefresh(bytes: 1_000_000_000, generation: old)
            }

            XCTAssertEqual(state.sizeText, formattedSize(2048))
            XCTAssertFalse(state.isCalculating)
            XCTAssertFalse(state.isClearing)
        }
    }

    func testClearInvalidatesRefreshBeforeAndAfterClearCompletion() throws {
        // 成功時のサイズも失敗時のエラーも、クリア前の再計算で上書きさせない。
        for succeeded in [true, false] {
            for oldCompletesFirst in [true, false] {
                var state = StorageSizeState()
                let old = try XCTUnwrap(state.beginRefresh())
                let clear = state.beginClear()
                XCTAssertTrue(state.isClearing)
                XCTAssertTrue(state.isCalculating)
                XCTAssertEqual(state.sizeText, "計算中…")

                if oldCompletesFirst {
                    state.finishRefresh(bytes: 1_000_000_000, generation: old)
                    XCTAssertTrue(state.isClearing)
                    XCTAssertTrue(state.isCalculating)
                    XCTAssertEqual(state.sizeText, "計算中…")
                }
                state.finishClear(succeeded: succeeded, bytes: 0, generation: clear)
                if !oldCompletesFirst {
                    state.finishRefresh(bytes: 1_000_000_000, generation: old)
                }

                XCTAssertEqual(state.sizeText, succeeded ? formattedSize(0) : "削除できませんでした")
                XCTAssertFalse(state.isClearing)
                XCTAssertFalse(state.isCalculating)
            }
        }
    }

    func testRefreshDuringClearDoesNotSupersedeClearAndCanResumeAfterward() throws {
        for succeeded in [true, false] {
            var state = StorageSizeState()
            let clear = state.beginClear()

            // クリア中の modelsRevision 変更は、削除後の再計算に任せる。
            XCTAssertNil(state.beginRefresh())
            XCTAssertTrue(state.isClearing)
            state.finishClear(succeeded: succeeded, bytes: 0, generation: clear)
            XCTAssertEqual(state.sizeText, succeeded ? formattedSize(0) : "削除できませんでした")
            XCTAssertFalse(state.isClearing)
            XCTAssertFalse(state.isCalculating)

            let refresh = try XCTUnwrap(state.beginRefresh())
            state.finishRefresh(bytes: 4096, generation: refresh)
            XCTAssertEqual(state.sizeText, formattedSize(4096))
            XCTAssertFalse(state.isCalculating)
        }
    }

    func testSuccessfulClearDisplaysMeasuredSizeRatherThanAssumingZero() {
        var state = StorageSizeState()
        let clear = state.beginClear()
        state.finishClear(succeeded: true, bytes: 128, generation: clear)

        XCTAssertEqual(state.sizeText, formattedSize(128))
        XCTAssertFalse(state.isClearing)
        XCTAssertFalse(state.isCalculating)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
