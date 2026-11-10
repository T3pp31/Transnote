import Combine
import Foundation

@MainActor
final class HistorySearchViewModel: ObservableObject {
    @Published private(set) var items: [Transcript] = []

    private let searchHistory: @Sendable (String) -> [Transcript]
    private let waitForDebounce: @Sendable () async throws -> Void
    private var generation = 0

    init(
        searchHistory: @escaping @Sendable (String) -> [Transcript] = { query in
            HistoryStore().search(query: query)
        },
        waitForDebounce: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    ) {
        self.searchHistory = searchHistory
        self.waitForDebounce = waitForDebounce
    }

    /// 呼び出し元の .task(id:) が入力変更・シート終了時のキャンセルを管理する。
    func search(query: String) async {
        generation += 1
        let requestGeneration = generation

        // 初回表示と検索欄のクリアは、待たずに最近の履歴を読み込む。
        if !query.isEmpty {
            do {
                try await waitForDebounce()
            } catch {
                return
            }
        }
        guard !Task.isCancelled, requestGeneration == generation else { return }

        // Task {} では MainActor を継承するため、同期 I/O は detached で隔離する。
        let searchHistory = searchHistory
        let results = await Task.detached(priority: .userInitiated) {
            searchHistory(query)
        }.value

        // 同期 I/O の完了順が逆転しても、古い検索や閉じたシートには反映しない。
        guard !Task.isCancelled, requestGeneration == generation else { return }
        items = results
    }
}
