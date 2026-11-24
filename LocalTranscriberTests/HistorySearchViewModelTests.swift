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
        let reads = HistorySearchReadRecorder()
        let store = HistoryStore(
            historyRoot: root,
            searchDataLoader: { url in
                XCTAssertFalse(Thread.isMainThread)
                return try reads.load(url)
            }
        )
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
        let model = HistorySearchViewModel(historyStore: store, waitForDebounce: {})

        await model.search(query: "")
        XCTAssertEqual(model.items.map(\.id), [byName.id, byText.id, other.id])
        await model.search(query: "MEETING")
        XCTAssertEqual(model.items.map(\.id), [byName.id, byText.id])
        XCTAssertEqual(reads.total, 4)
        await model.search(query: "こんにちは")
        XCTAssertEqual(model.items.map(\.id), [byName.id])
        await model.search(query: "no match")
        XCTAssertTrue(model.items.isEmpty)
        await model.search(query: "")
        XCTAssertEqual(model.items.map(\.id), [byName.id, byText.id, other.id])
        await model.search(query: "meeting")
        XCTAssertEqual(model.items.map(\.id), [byName.id, byText.id])
        XCTAssertEqual(reads.total, 4, "The default search closure must retain its store across queries and clears")
    }

    func testNewQueryCancelsPendingSearchTask() async {
        let oldStarted = expectation(description: "old search started")
        let oldRelease = DispatchSemaphore(value: 0)
        let latestStarted = expectation(description: "latest search started")
        let latestTranscript = Transcript(sourceFileName: "latest.wav")
        let oldCancellation = CancellationRecorder()
        let model = HistorySearchViewModel(
            searchHistory: { query in
                if query == "old" {
                    oldStarted.fulfill()
                    let released = oldRelease.wait(timeout: .now() + 5)
                    XCTAssertEqual(released, .success, "古い走査は新しい検索の開始後に解放されること")
                    oldCancellation.record(Task.isCancelled)
                    return [Transcript(sourceFileName: "old.wav")]
                }
                latestStarted.fulfill()
                return [latestTranscript]
            },
            waitForDebounce: {}
        )

        let old = Task { await model.search(query: "old") }
        await fulfillment(of: [oldStarted], timeout: 2)

        // 実行中の走査は中断できないが、完了後に結果を反映しないこと。
        let latest = Task { await model.search(query: "latest") }
        await fulfillment(of: [latestStarted], timeout: 2)
        await latest.value

        oldRelease.signal()
        await old.value

        XCTAssertEqual(model.items.map(\.id), [latestTranscript.id], "古い検索の結果を反映しないこと")
        XCTAssertEqual(oldCancellation.value, true, "新しい検索語で古い走査タスクがキャンセルされること")
    }

    func testCompletedOlderSearchDoesNotClearNewerSearchTaskOwnership() async {
        let firstStarted = expectation(description: "first search started")
        let secondStarted = expectation(description: "second search started")
        let thirdStarted = expectation(description: "third search started")
        let firstRelease = DispatchSemaphore(value: 0)
        let secondRelease = DispatchSemaphore(value: 0)
        defer {
            firstRelease.signal()
            secondRelease.signal()
        }
        let secondCancellation = CancellationRecorder()
        let thirdTranscript = Transcript(sourceFileName: "third.wav")
        let model = HistorySearchViewModel(
            searchHistory: { query in
                switch query {
                case "first":
                    firstStarted.fulfill()
                    XCTAssertEqual(firstRelease.wait(timeout: .now() + 5), .success)
                    return [Transcript(sourceFileName: "first.wav")]
                case "second":
                    secondStarted.fulfill()
                    XCTAssertEqual(secondRelease.wait(timeout: .now() + 5), .success)
                    secondCancellation.record(Task.isCancelled)
                    return [Transcript(sourceFileName: "second.wav")]
                default:
                    thirdStarted.fulfill()
                    return [thirdTranscript]
                }
            },
            waitForDebounce: {}
        )

        let first = Task { await model.search(query: "first") }
        await fulfillment(of: [firstStarted], timeout: 2)

        let second = Task { await model.search(query: "second") }
        await fulfillment(of: [secondStarted], timeout: 2)

        // first が second 実行中に完了しても、second のタスク所有権を消してはならない。
        firstRelease.signal()
        await first.value

        let third = Task { await model.search(query: "third") }
        await fulfillment(of: [thirdStarted], timeout: 2)
        await third.value

        secondRelease.signal()
        await second.value

        XCTAssertEqual(secondCancellation.value, true, "古い検索の完了後も後続タスクをキャンセルできること")
        XCTAssertEqual(model.items.map(\.id), [thirdTranscript.id])
    }

    func testCanceledQueryDuringDebounceDoesNotStartSearch() async {
        let started = expectation(description: "debounce started")
        let release = DispatchSemaphore(value: 0)
        let searched = CancellationRecorder()
        let model = HistorySearchViewModel(
            searchHistory: { _ in
                searched.record(false)
                return []
            },
            waitForDebounce: {
                started.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
            }
        )

        let search = Task { await model.search(query: "canceled") }
        await fulfillment(of: [started], timeout: 2)
        search.cancel()
        release.signal()
        await search.value

        XCTAssertNil(searched.value, "デバウンス中にキャンセルされた検索は走査を開始しないこと")
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

    func testHistoryStoreSaveInvalidatesSearchCacheWhenFileMetadataMatches() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recoveryURL = AppDirectories.tempTranscriptsDirectory.appendingPathComponent("recovery.json")
        let originalRecoveryData = try? Data(contentsOf: recoveryURL)
        defer {
            if let originalRecoveryData {
                try? originalRecoveryData.write(to: recoveryURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: recoveryURL)
            }
        }

        let reads = HistorySearchReadRecorder()
        let store = HistoryStore(
            historyRoot: root,
            searchDataLoader: { url in try reads.load(url) }
        )

        var transcript = Transcript(
            sourceFileName: "notes.wav",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fullText: "alpha"
        )
        let fileURL = root.appendingPathComponent("\(transcript.id.uuidString).json")
        let fixedModificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        try store.save(transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path
        )
        let initialAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let initialSize = try XCTUnwrap(initialAttributes[.size] as? NSNumber)
        let initialMtime = try XCTUnwrap(initialAttributes[.modificationDate] as? Date)

        // 初回検索でキャッシュに載せる。
        XCTAssertEqual(store.search(query: "alpha").map(\.id), [transcript.id])
        XCTAssertEqual(reads.total, 1)

        // 同一 ID を同バイト数の別本文で上書きし、更新日時もキャッシュ時と同じ値に揃える。
        transcript.fullText = "bravo"
        try store.save(transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: initialMtime],
            ofItemAtPath: fileURL.path
        )
        let savedAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(savedAttributes[.size] as? NSNumber, initialSize, "同サイズ上書きの前提を満たすこと")
        XCTAssertEqual(savedAttributes[.modificationDate] as? Date, initialMtime, "更新日時一致の前提を満たすこと")

        // メタデータが一致しても save() の明示的 invalidate により再読み込みされ、新本文のみヒットすること。
        XCTAssertTrue(store.search(query: "alpha").isEmpty)
        XCTAssertEqual(store.search(query: "bravo").map(\.id), [transcript.id])
        XCTAssertEqual(reads.total, 2, "save 後の再検索で searchDataLoader が再呼び出しされること")

        // saveWithTemporary 経路でも同様にキャッシュが無効化されること。
        transcript.fullText = "delta"
        try store.saveWithTemporary(transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: initialMtime],
            ofItemAtPath: fileURL.path
        )
        let tempSavedAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(tempSavedAttributes[.size] as? NSNumber, initialSize)
        XCTAssertEqual(tempSavedAttributes[.modificationDate] as? Date, initialMtime)

        XCTAssertTrue(store.search(query: "bravo").isEmpty)
        XCTAssertEqual(store.search(query: "delta").map(\.id), [transcript.id])
        XCTAssertEqual(reads.total, 3, "saveWithTemporary 後の再検索でも searchDataLoader が再呼び出しされること")
    }

    func testViewModelSearchReflectsOverwrittenTranscriptWithUnchangedMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let reads = HistorySearchReadRecorder()
        let store = HistoryStore(
            historyRoot: root,
            searchDataLoader: { url in try reads.load(url) }
        )
        let model = HistorySearchViewModel(historyStore: store, waitForDebounce: {})

        var transcript = Transcript(
            sourceFileName: "meeting.wav",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fullText: "alpha"
        )
        let fileURL = root.appendingPathComponent("\(transcript.id.uuidString).json")
        let fixedModificationDate = Date(timeIntervalSince1970: 1_700_000_000)

        try store.save(transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path
        )
        let initialSize = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
        )

        await model.search(query: "alpha")
        XCTAssertEqual(model.items.map(\.id), [transcript.id])
        XCTAssertEqual(reads.total, 1)

        transcript.fullText = "bravo"
        try store.save(transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedModificationDate],
            ofItemAtPath: fileURL.path
        )
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber,
            initialSize
        )

        await model.search(query: "alpha")
        XCTAssertTrue(model.items.isEmpty)
        await model.search(query: "bravo")
        XCTAssertEqual(model.items.map(\.id), [transcript.id])
        XCTAssertEqual(reads.total, 2)
    }

    func testHistorySheetEmptyStateMessageDistinguishesEmptyQueryAndNoSearchMatches() {
        XCTAssertEqual(
            HistorySheetEmptyState.message(for: ""),
            L("履歴はまだありません。", comment: "No transcription history yet")
        )
        XCTAssertEqual(
            HistorySheetEmptyState.message(for: "nonexistent"),
            L("該当する履歴がありません。", comment: "No matching history search results")
        )
        XCTAssertEqual(
            HistorySheetEmptyState.message(for: " "),
            L("該当する履歴がありません。", comment: "No matching history search results")
        )
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

private final class CancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: Bool?

    var value: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ isCancelled: Bool) {
        lock.lock()
        recorded = isCancelled
        lock.unlock()
    }
}
