import Combine
import Foundation

@MainActor
final class HistorySearchViewModel: ObservableObject {
    @Published private(set) var items: [Transcript] = []

    private let searchHistory: @Sendable (String) -> [Transcript]
    private let waitForDebounce: @Sendable () async throws -> Void
    private var generation = 0
    /// 検索語の変更時に古い走査を打ち切るため、進行中の detached タスクを保持する。
    private var searchTask: Task<[Transcript], Never>?

    init(
        historyStore: HistoryStore = HistoryStore(),
        searchHistory: (@Sendable (String) -> [Transcript])? = nil,
        waitForDebounce: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(nanoseconds: AppConfig.shared.historySearchDebounceNanoseconds)
        }
    ) {
        // 同じストアを保持し、検索語が変わってもデコード・正規化キャッシュを再利用する。
        self.searchHistory = searchHistory ?? { query in historyStore.search(query: query) }
        self.waitForDebounce = waitForDebounce
    }

    /// 呼び出し元の .task(id:) が入力変更・シート終了時のキャンセルを管理する。
    func search(query: String) async {
        generation += 1
        let requestGeneration = generation
        // 前の検索が完了していなくても、新しい検索語では不要な走査を続けない。
        searchTask?.cancel()

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
        let task = Task.detached(priority: .userInitiated) { () -> [Transcript] in
            // 実行前にキャンセルされた走査は開始しない。実行中の走査は同期処理のため中断できない。
            guard !Task.isCancelled else { return [] }
            return searchHistory(query)
        }
        searchTask = task
        let results = await task.value
        if requestGeneration == generation {
            searchTask = nil
        }

        // 同期 I/O の完了順が逆転しても、古い検索や閉じたシートには反映しない。
        guard !Task.isCancelled, requestGeneration == generation else { return }
        items = results
    }
}
