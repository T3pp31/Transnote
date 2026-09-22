import Foundation

/// 文字起こし履歴を Application Support/History に JSON で保存・読み込みする。
struct HistoryStore: Sendable {
    private let historyRoot: URL
    private let fileManager: FileManager

    init(
        historyRoot: URL = AppDirectories.historyDirectory,
        fileManager: FileManager = .default
    ) {
        self.historyRoot = historyRoot
        self.fileManager = fileManager
    }

    func save(_ transcript: Transcript) throws {
        try fileManager.createDirectory(at: historyRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try data.write(to: url, options: .atomic)
    }

    func recent(limit: Int = 50) -> [Transcript] {
        guard fileManager.fileExists(atPath: historyRoot.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: historyRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [Transcript] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let data = try? Data(contentsOf: url),
                  let transcript = try? decoder.decode(Transcript.self, from: data) else {
                continue
            }
            items.append(transcript)
        }

        return items
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    /// 全文・ファイル名を対象に履歴を検索する。
    func search(query: String, limit: Int = 50) -> [Transcript] {
        let normalized = query.lowercased()
        guard !normalized.isEmpty else { return recent(limit: limit) }
        return recent(limit: 500)
            .filter { item in
                item.fullText.lowercased().contains(normalized)
                    || item.sourceFileName.lowercased().contains(normalized)
            }
            .prefix(limit)
            .map { item in item }
    }

    func delete(_ transcript: Transcript) {
        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }
}
