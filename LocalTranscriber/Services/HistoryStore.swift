import Foundation

/// 文字起こし履歴を Application Support/History に JSON で保存・読み込みする。
struct HistoryStore: Sendable {
    private let historyRoot: URL
    private let fileManager: FileManager
    private let searchDataLoader: @Sendable (URL) throws -> Data
    private let searchCache = SearchCache()

    /// - Parameter searchDataLoader: 検索キャッシュの再利用と読み込み失敗を検証するための差し替え。
    init(
        historyRoot: URL = AppDirectories.historyDirectory,
        fileManager: FileManager = .default,
        searchDataLoader: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.historyRoot = historyRoot
        self.fileManager = fileManager
        self.searchDataLoader = searchDataLoader
    }

    func save(_ transcript: Transcript) throws {
        try fileManager.createDirectory(at: historyRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try data.write(to: url, options: .atomic)
        searchCache.invalidate(url)
    }

    func recent(limit: Int = 50) -> [Transcript] {
        return loadAllTranscripts(limit: limit)
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    private func loadAllTranscripts(limit: Int) -> [Transcript] {
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
        guard limit > 0 else { return [] }
        let normalized = query.lowercased()
        guard !normalized.isEmpty else { return recent(limit: limit) }

        // detached の検索同士や保存・削除後の無効化が競合しても、キャッシュを壊さない。
        searchCache.lock.lock()
        defer { searchCache.lock.unlock() }
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: historyRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            searchCache.entries.removeAll()
            return []
        }

        struct Candidate {
            let url: URL
            let modificationDate: Date
            let fileSize: Int
        }
        var candidates: [Candidate] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let modificationDate = values.contentModificationDate,
                  let fileSize = values.fileSize else { continue }
            candidates.append(Candidate(url: url, modificationDate: modificationDate, fileSize: fileSize))
        }
        candidates.sort { $0.modificationDate > $1.modificationDate }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var visited: Set<String> = []
        // 更新日時と createdAt は一致しないため、全候補を検索してから作成日時順で件数を絞る。
        var matches: [Transcript] = []
        for candidate in candidates {
            let url = candidate.url
            let key = SearchCache.key(for: url)
            visited.insert(key)
            let entry: SearchCache.Entry
            if let cached = searchCache.entries[key],
               cached.modificationDate == candidate.modificationDate, cached.fileSize == candidate.fileSize {
                entry = cached
            } else {
                // 読み込み失敗は次回再試行する。破損 JSON は変更されるまでデコードし直さない。
                guard let data = try? searchDataLoader(url) else {
                    searchCache.entries.removeValue(forKey: key)
                    continue
                }
                entry = SearchCache.Entry(
                    modificationDate: candidate.modificationDate,
                    fileSize: candidate.fileSize,
                    transcript: try? decoder.decode(Transcript.self, from: data)
                )
                searchCache.entries[key] = entry
            }

            guard let transcript = entry.transcript,
                  entry.normalizedText.contains(normalized) || entry.normalizedFileName.contains(normalized) else { continue }
            matches.append(transcript)
        }
        // 外部から削除・移動されたファイルの本文を保持し続けない。
        searchCache.entries = searchCache.entries.filter { visited.contains($0.key) }

        return matches
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    /// entries は必ず lock の内側で参照・更新する。HistoryStore のコピー間でも共有する。
    private final class SearchCache: @unchecked Sendable {
        let lock = NSLock()
        var entries: [String: Entry] = [:]

        // enumerator が返す URL と save/delete で組み立てる URL は、同じファイルでも
        // 基準 URL が異なり得る。登録・参照・無効化には同じ絶対パスを使う。
        static func key(for url: URL) -> String {
            url.standardizedFileURL.path
        }

        struct Entry {
            let modificationDate: Date
            let fileSize: Int
            let transcript: Transcript?
            let normalizedText: String
            let normalizedFileName: String

            init(modificationDate: Date, fileSize: Int, transcript: Transcript?) {
                self.modificationDate = modificationDate
                self.fileSize = fileSize
                self.transcript = transcript
                normalizedText = transcript?.fullText.lowercased() ?? ""
                normalizedFileName = transcript?.sourceFileName.lowercased() ?? ""
            }
        }

        func invalidate(_ url: URL) {
            lock.lock()
            defer { lock.unlock() }
            entries.removeValue(forKey: Self.key(for: url))
        }
    }

    func delete(_ transcript: Transcript) {
        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try? fileManager.removeItem(at: url)
        searchCache.invalidate(url)
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
