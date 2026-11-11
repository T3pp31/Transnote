import Combine
import XCTest
@testable import LocalTranscriber

@MainActor
final class HistorySearchViewModelTests: XCTestCase {
    func testSearchRunsOffMainThreadAndPublishesResults() async {
        let transcript = Transcript(sourceFileName: "meeting.wav", fullText: "hello")
        let model = HistorySearchViewModel(
            searchHistory: { query in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(query, "meeting")
                return [transcript]
            },
            waitForDebounce: {}
        )
        let publication = model.$items.dropFirst().sink { items in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(items.map(\.id), [transcript.id])
        }
        defer { publication.cancel() }

        await model.search(query: "meeting")

        XCTAssertEqual(model.items.map(\.id), [transcript.id])
    }

    func testCanceledInputDuringDebounceDoesNotSearch() async {
        let firstStarted = expectation(description: "first debounce started")
        let latestStarted = expectation(description: "latest debounce started")
        let searched = expectation(description: "only the latest input is searched")
        searched.assertForOverFulfill = true
        let debounce = ManualHistoryDebounce(started: [firstStarted, latestStarted])
        let transcript = Transcript(sourceFileName: "latest.wav")
        let model = HistorySearchViewModel(
            searchHistory: { query in
                XCTAssertEqual(query, "latest")
                searched.fulfill()
                return [transcript]
            },
            waitForDebounce: { await debounce.wait() }
        )

        let first = Task { await model.search(query: "l") }
        await fulfillment(of: [firstStarted], timeout: 2)
        first.cancel()
        let latest = Task { await model.search(query: "latest") }
        await fulfillment(of: [latestStarted], timeout: 2)
        XCTAssertTrue(model.items.isEmpty)

        // キャンセルを無視する待機でも、古い入力では I/O を開始しない。
        await debounce.releaseAll()
        await first.value
        await latest.value
        await fulfillment(of: [searched], timeout: 2)
        XCTAssertEqual(model.items.map(\.id), [transcript.id])
    }

    func testCancellationErrorDuringDebounceDoesNotSearch() async {
        let model = HistorySearchViewModel(
            searchHistory: { _ in
                XCTFail("Canceled debounce must not start history I/O")
                return []
            },
            waitForDebounce: { throw CancellationError() }
        )

        await model.search(query: "canceled")

        XCTAssertTrue(model.items.isEmpty)
    }

    func testOnlyLatestSearchPublishesRegardlessOfCompletionOrder() async {
        for oldCompletesFirst in [true, false] {
            let oldStarted = expectation(description: "old search started")
            let latestStarted = expectation(description: "latest search started")
            let releaseOld = DispatchSemaphore(value: 0)
            let releaseLatest = DispatchSemaphore(value: 0)
            let oldTranscript = Transcript(sourceFileName: "old.wav")
            let latestTranscript = Transcript(sourceFileName: "latest.wav")
            let model = HistorySearchViewModel(
                searchHistory: { query in
                    XCTAssertFalse(Thread.isMainThread)
                    if query == "old" {
                        oldStarted.fulfill()
                        XCTAssertEqual(releaseOld.wait(timeout: .now() + 5), .success)
                        return [oldTranscript]
                    }
                    latestStarted.fulfill()
                    XCTAssertEqual(releaseLatest.wait(timeout: .now() + 5), .success)
                    return [latestTranscript]
                },
                waitForDebounce: {}
            )
            defer {
                releaseOld.signal()
                releaseLatest.signal()
            }

            let old = Task { await model.search(query: "old") }
            await fulfillment(of: [oldStarted], timeout: 2)
            let latest = Task { await model.search(query: "latest") }
            await fulfillment(of: [latestStarted], timeout: 2)

            // 同期検索が待機中でも MainActor は次の入力を処理できる。
            if oldCompletesFirst {
                releaseOld.signal()
                await old.value
                XCTAssertTrue(model.items.isEmpty)
                releaseLatest.signal()
                await latest.value
            } else {
                releaseLatest.signal()
                await latest.value
                releaseOld.signal()
                await old.value
            }
            XCTAssertEqual(model.items.map(\.id), [latestTranscript.id])
        }
    }

    func testCancellationAfterSearchStartsKeepsExistingResults() async {
        let started = expectation(description: "slow search started")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let initial = Transcript(sourceFileName: "initial.wav")
        let canceled = Transcript(sourceFileName: "canceled.wav")
        let model = HistorySearchViewModel(
            searchHistory: { query in
                XCTAssertFalse(Thread.isMainThread)
                guard query == "slow" else { return [initial] }
                started.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                return [canceled]
            },
            waitForDebounce: {}
        )
        await model.search(query: "")
        let search = Task { await model.search(query: "slow") }
        await fulfillment(of: [started], timeout: 2)

        // シートを閉じた場合と同じく、結果を待つタスクをキャンセルする。
        search.cancel()
        release.signal()
        await search.value

        XCTAssertEqual(model.items.map(\.id), [initial.id])
    }

    func testSearchAndClearPreserveHistoryStoreBehavior() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(historyRoot: root)
        let byName = Transcript(
            sourceFileName: "Meeting.wav",
            createdAt: Date(timeIntervalSince1970: 1_700_000_002),
            fullText: "こんにちは"
        )
        let byText = Transcript(
            sourceFileName: "notes.wav",
            createdAt: Date(timeIntervalSince1970: 1_700_000_001),
            fullText: "Meeting notes"
        )
        let other = Transcript(
            sourceFileName: "other.wav",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fullText: "別の内容"
        )
        for item in [other, byText, byName] {
            try store.save(item)
        }
        try Data("invalid json".utf8).write(to: root.appendingPathComponent("broken.json"))
        let model = HistorySearchViewModel(
            searchHistory: { query in
                XCTAssertFalse(Thread.isMainThread)
                return store.search(query: query)
            },
            waitForDebounce: {}
        )

        await model.search(query: "")
        XCTAssertEqual(model.items.map(\.id), [byName.id, byText.id, other.id])
        await model.search(query: "MEETING")
        XCTAssertEqual(model.items.map(\.id), [byName.id, byText.id])
        await model.search(query: "こんにちは")
        XCTAssertEqual(model.items.map(\.id), [byName.id])
        await model.search(query: "no match")
        XCTAssertTrue(model.items.isEmpty)
        await model.search(query: "")
        XCTAssertEqual(model.items.map(\.id), [byName.id, byText.id, other.id])
    }

    func testEmptyQueryLoadsWithoutDebounce() async {
        let transcript = Transcript(sourceFileName: "recent.wav")
        let model = HistorySearchViewModel(
            searchHistory: { query in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(query, "")
                return [transcript]
            },
            waitForDebounce: { XCTFail("Recent history must load without a debounce delay") }
        )

        await model.search(query: "")

        XCTAssertEqual(model.items.map(\.id), [transcript.id])
    }
}

private actor ManualHistoryDebounce {
    private let started: [XCTestExpectation]
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(started: [XCTestExpectation]) {
        self.started = started
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let index = waiters.count
            waiters.append(continuation)
            if index < started.count {
                started[index].fulfill()
            } else {
                XCTFail("Unexpected debounce request")
            }
        }
    }

    func releaseAll() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
