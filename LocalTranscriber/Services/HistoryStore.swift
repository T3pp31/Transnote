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
        return loadAllTranscripts()
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func loadAllTranscripts() -> [Transcript] {
        guard fileManager.fileExists(atPath: historyRoot.path) else { return [] }
        guard limit > 0 else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: historyRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        struct Candidate {
            let url: URL
            let modificationDate: Date
        }

        var candidates: [Candidate] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
                continue
            }
            candidates.append(Candidate(url: url, modificationDate: modificationDate))
        }

        candidates.sort { $0.modificationDate > $1.modificationDate }

        var items: [Transcript] = []
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate.url),
                  let transcript = try? decoder.decode(Transcript.self, from: data) else {
                continue
            }
            items.append(transcript)

            // 修正日時が古い候補は createdAt も古いことが多いため、
            // 必要件数を満たした時点で以降の重いデコードを止める。
            if items.count >= limit,
               let oldest = items.map({ $0.createdAt }).min(),
               candidate.modificationDate < oldest {
                break
            }
        }

        return items
    }

    /// 全文・ファイル名を対象に履歴を検索する。
    func search(query: String, limit: Int = 50) -> [Transcript] {
        let normalized = query.lowercased()
        guard !normalized.isEmpty else { return recent(limit: limit) }
        guard fileManager.fileExists(atPath: historyRoot.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: historyRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        struct Candidate {
            let url: URL
            let modificationDate: Date
        }

        var candidates: [Candidate] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
                continue
            }
            candidates.append(Candidate(url: url, modificationDate: modificationDate))
        }

        candidates.sort { $0.modificationDate > $1.modificationDate }

        var matches: [Transcript] = []
        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate.url),
                  let transcript = try? decoder.decode(Transcript.self, from: data) else {
                continue
            }

            let isMatch = transcript.fullText.lowercased().contains(normalized)
                || transcript.sourceFileName.lowercased().contains(normalized)
            guard isMatch else { continue }
            matches.append(transcript)
            if matches.count >= limit {
                break
            }
        }

        return matches
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func delete(_ transcript: Transcript) {
        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }

    // MARK: - Crash recovery (temporary transcripts)

    /// クラッシュ復旧用に一時的な Transcript を保存する。
    func saveTemporary(_ transcript: Transcript) throws {
        try fileManager.createDirectory(at: AppDirectories.tempTranscriptsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        let url = AppDirectories.tempTranscriptsDirectory.appendingPathComponent("recovery.json")
        try data.write(to: url, options: .atomic)
    }

    /// クラッシュ復旧用の一時 Transcript を読み込む。なければ nil。
    func loadTemporary() -> Transcript? {
        let url = AppDirectories.tempTranscriptsDirectory.appendingPathComponent("recovery.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Transcript.self, from: data)
    }

    /// クラッシュ復旧用の一時 Transcript を削除する。
    func clearTemporary() {
        let url = AppDirectories.tempTranscriptsDirectory.appendingPathComponent("recovery.json")
        try? fileManager.removeItem(at: url)
    }
}
