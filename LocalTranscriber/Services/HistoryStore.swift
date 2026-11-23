import Foundation

/// 文字起こし履歴を Application Support/History に JSON で保存・読み込みする。
struct HistoryStore: Sendable {
    static let defaultMaxSearchCacheEntries = 200
    static let defaultMaxSearchCacheBytes = 16 * 1024 * 1024

    private let historyRoot: URL
    private let temporaryRoot: URL
    private let fileManager: FileManager
    private let searchDataLoader: @Sendable (URL) throws -> Data
    private let searchCache: SearchCache
    private let readTranscriptData: @Sendable (URL) throws -> Data

    // 別インスタンスの検索と保存でも、本文とメタデータの対応が崩れないようにする。
    private static let metadataLock = NSLock()

    private struct FileVersion: Codable, Equatable {
        let modificationTime: TimeInterval
        let size: UInt64
        let fileNumber: UInt64
    }

    private struct RecentMetadata: Codable {
        let createdAt: Date
        let fileVersion: FileVersion
    }

    /// 検索スキャン用の軽量デコード型。巨大な segments 配列をデコード・保持せずに一致判定する。
    private struct SearchDocument: Decodable {
        let sourceFileName: String
        let createdAt: Date
        let fullText: String
        let schemaVersion: Int

        private enum CodingKeys: String, CodingKey {
            case sourceFileName, createdAt, fullText, schemaVersion
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            fullText = try container.decode(String.self, forKey: .fullText)
            let rawVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Transcript.currentSchemaVersion
            guard rawVersion >= 1, rawVersion <= Transcript.currentSchemaVersion else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: container.codingPath, debugDescription: "Unsupported schemaVersion: \(rawVersion)")
                )
            }
            schemaVersion = rawVersion
        }
    }

    /// - Parameter searchDataLoader: 検索キャッシュの再利用と読み込み失敗を検証するための差し替え。
    init(
        historyRoot: URL = AppDirectories.historyDirectory,
        temporaryRoot: URL = AppDirectories.tempTranscriptsDirectory,
        fileManager: FileManager = .default,
        searchDataLoader: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        readTranscriptData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        maxSearchCacheEntries: Int = HistoryStore.defaultMaxSearchCacheEntries,
        maxSearchCacheBytes: Int = HistoryStore.defaultMaxSearchCacheBytes
    ) {
        self.historyRoot = historyRoot
        self.temporaryRoot = temporaryRoot
        self.fileManager = fileManager
        self.searchDataLoader = searchDataLoader
        self.readTranscriptData = readTranscriptData
        self.searchCache = SearchCache(
            maxEntries: maxSearchCacheEntries,
            maxBytes: maxSearchCacheBytes
        )
    }

    var searchCacheEntryCountForTesting: Int {
        searchCache.entryCount
    }

    var searchCacheBytesForTesting: Int {
        searchCache.currentBytes
    }

    func save(_ transcript: Transcript) throws {
        let data = try encode(transcript)
        try write(data, for: transcript)
    }

    /// 履歴と復旧用の両方へ同じエンコード結果を書き出す。
    /// 同一 Transcript を2回エンコードするコストを避けるため。
    func saveWithTemporary(_ transcript: Transcript) throws {
        let data = try encode(transcript)
        // 履歴と復旧用は別ディレクトリのため、片方の失敗でもう片方の試行を妨げない。
        var historyError: Error?
        do {
            try write(data, for: transcript)
        } catch {
            historyError = error
        }
        try writeTemporary(data)
        if let historyError { throw historyError }
    }

    private func encode(_ transcript: Transcript) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(transcript)
    }

    private func write(_ data: Data, for transcript: Transcript) throws {
        Self.metadataLock.lock()
        defer { Self.metadataLock.unlock() }

        try fileManager.createDirectory(at: historyRoot, withIntermediateDirectories: true)
        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try data.write(to: url, options: .atomic)
        searchCache.invalidate(url)
        if let version = fileVersion(at: url) {
            saveRecentMetadata(createdAt: transcript.createdAt, fileVersion: version, at: url)
        }
    }

    private func writeTemporary(_ data: Data) throws {
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let url = temporaryRoot.appendingPathComponent("recovery.json")
        try data.write(to: url, options: .atomic)
    }

    func recent(
        limit: Int = 50,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) -> [Transcript] {
        guard limit > 0, !isCancelled() else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: historyRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [(url: URL, createdAt: Date)] = []
        for case let url as URL in enumerator {
            guard !isCancelled() else { return [] }
            guard let createdAt = recentCreationDate(at: url) else { continue }
            candidates.append((url, createdAt))
        }
        candidates.sort { $0.createdAt > $1.createdAt }

        var items: [Transcript] = []
        for candidate in candidates {
            guard !isCancelled() else { return [] }
            guard let transcript = loadTranscript(at: candidate.url) else { continue }
            items.append(transcript)
            if items.count == limit { break }
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadTranscript(at url: URL) -> Transcript? {
        guard let data = try? readTranscriptData(url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Transcript.self, from: data)
    }

    private func fileVersion(at url: URL) -> FileVersion? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let date = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber,
              let number = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return FileVersion(
            modificationTime: date.timeIntervalSince1970, size: size.uint64Value, fileNumber: number.uint64Value
        )
    }

    private func recentMetadataURL(for url: URL) -> URL {
        // 本文と同じ場所の隠しファイルにし、履歴の再帰列挙・全文検索から除外する。
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).recent-v1.json")
    }

    private func saveRecentMetadata(createdAt: Date, fileVersion: FileVersion, at url: URL) {
        let encoder = JSONEncoder()
        // 本文と同じ日時精度にする。ファイル更新日時は小数秒を失わない数値で保存する。
        encoder.dateEncodingStrategy = .iso8601
        let metadata = RecentMetadata(createdAt: createdAt, fileVersion: fileVersion)
        guard let data = try? encoder.encode(metadata) else { return }
        // キャッシュの保存失敗は履歴本文の保存・読み込みを失敗させない。
        try? data.write(to: recentMetadataURL(for: url), options: .atomic)
    }

    private func recentCreationDate(at url: URL) -> Date? {
        Self.metadataLock.lock()
        defer { Self.metadataLock.unlock() }

        guard let version = fileVersion(at: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: recentMetadataURL(for: url)),
           let metadata = try? decoder.decode(RecentMetadata.self, from: data),
           metadata.fileVersion == version {
            return metadata.createdAt
        }

        // 旧履歴・外部変更・キャッシュ破損時だけ本文を読み、次回以降のために再構築する。
        guard let transcript = loadTranscript(at: url) else { return nil }
        if fileVersion(at: url) == version {
            saveRecentMetadata(createdAt: transcript.createdAt, fileVersion: version, at: url)
        }
        return transcript.createdAt
    }

    /// 全文・ファイル名を対象に履歴を検索する。
    /// 検索スキャンでは segments を含まない軽量メタデータのみをデコードし、
    /// 上限付き LRU キャッシュで常駐メモリを抑えつつ、上位 limit 件のみ完全な Transcript を読み込む。
    func search(
        query: String,
        limit: Int = 50,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) -> [Transcript] {
        guard limit > 0, !isCancelled() else { return [] }
        let normalized = query.lowercased()
        guard !normalized.isEmpty else { return recent(limit: limit, isCancelled: isCancelled) }

        let matchedCandidates: [(url: URL, createdAt: Date)] = {
            // detached の検索同士や保存・削除後の無効化が競合しても、キャッシュを壊さない。
            searchCache.lock.lock()
            defer { searchCache.lock.unlock() }
            // ロック待機中に新しい検索へ切り替わった場合は、走査を行わず即座に打ち切る。
            guard !isCancelled() else { return [] }
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            guard let enumerator = fileManager.enumerator(
                at: historyRoot,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                searchCache.removeAllLocked()
                return []
            }

            struct Candidate {
                let url: URL
                let modificationDate: Date
                let fileSize: Int
            }
            var candidates: [Candidate] = []
            for case let url as URL in enumerator {
                guard !isCancelled() else { return [] }
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
            // 更新日時と createdAt は一致しないため、全候補を軽量検索してから作成日時順で件数を絞る。
            var matches: [(url: URL, createdAt: Date)] = []
            for candidate in candidates {
                // 途中キャンセル時は未訪問エントリを誤って prune しないよう、そのまま終了する。
                guard !isCancelled() else { return [] }
                let url = candidate.url
                let key = SearchCache.key(for: url)
                visited.insert(key)
                let entry: SearchCache.Entry
                if let cached = searchCache.lookupLocked(
                    key: key,
                    modificationDate: candidate.modificationDate,
                    fileSize: candidate.fileSize
                ) {
                    entry = cached
                } else {
                    // 読み込み失敗は次回再試行する。破損 JSON は変更されるまでデコードし直さない。
                    guard let data = try? searchDataLoader(url) else {
                        searchCache.removeLocked(forKey: key)
                        continue
                    }
                    let document = try? decoder.decode(SearchDocument.self, from: data)
                    entry = SearchCache.Entry(
                        modificationDate: candidate.modificationDate,
                        fileSize: candidate.fileSize,
                        createdAt: document?.createdAt,
                        normalizedText: document?.fullText.lowercased() ?? "",
                        normalizedFileName: document?.sourceFileName.lowercased() ?? ""
                    )
                    searchCache.storeLocked(entry, forKey: key)
                }

                guard let createdAt = entry.createdAt,
                      entry.normalizedText.contains(normalized) || entry.normalizedFileName.contains(normalized) else {
                    continue
                }
                matches.append((url: url, createdAt: createdAt))
            }
            // 外部から削除・移動されたファイルのキャッシュエントリを保持し続けない。
            searchCache.pruneMissingLocked(keeping: visited)

            return matches.sorted { $0.createdAt > $1.createdAt }
        }()

        // 実際に返す上位 limit 件だけ完全な Transcript（segments 含む）を読み込む。
        var results: [Transcript] = []
        results.reserveCapacity(min(limit, matchedCandidates.count))
        for match in matchedCandidates {
            guard !isCancelled() else { return [] }
            guard let transcript = loadTranscript(at: match.url) else { continue }
            results.append(transcript)
            if results.count == limit { break }
        }
        return results
    }

    /// entries は必ず lock の内側で参照・更新する。HistoryStore のコピー間でも共有する。
    /// 件数・バイト数の両方で上限を設け、超過時は最も古く参照されたエントリ（LRU）から破棄する。
    private final class SearchCache: @unchecked Sendable {
        let lock = NSLock()
        private let maxEntries: Int
        private let maxBytes: Int
        private var entries: [String: Entry] = [:]
        private var accessTicks: [String: UInt64] = [:]
        private var nextTick: UInt64 = 0
        private var totalBytes = 0

        init(maxEntries: Int, maxBytes: Int) {
            self.maxEntries = max(0, maxEntries)
            self.maxBytes = max(0, maxBytes)
        }

        var entryCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return entries.count
        }

        var currentBytes: Int {
            lock.lock()
            defer { lock.unlock() }
            return totalBytes
        }

        // enumerator が返す URL と save/delete で組み立てる URL は、同じファイルでも
        // 基準 URL が異なり得る。登録・参照・無効化には同じ絶対パスを使う。
        static func key(for url: URL) -> String {
            url.standardizedFileURL.path
        }

        struct Entry {
            let modificationDate: Date
            let fileSize: Int
            let createdAt: Date?
            let normalizedText: String
            let normalizedFileName: String
            let estimatedBytes: Int

            init(
                modificationDate: Date,
                fileSize: Int,
                createdAt: Date?,
                normalizedText: String,
                normalizedFileName: String
            ) {
                self.modificationDate = modificationDate
                self.fileSize = fileSize
                self.createdAt = createdAt
                self.normalizedText = normalizedText
                self.normalizedFileName = normalizedFileName
                self.estimatedBytes = normalizedText.utf8.count + normalizedFileName.utf8.count + 64
            }
        }

        func lookupLocked(key: String, modificationDate: Date, fileSize: Int) -> Entry? {
            guard let cached = entries[key],
                  cached.modificationDate == modificationDate,
                  cached.fileSize == fileSize else {
                return nil
            }
            nextTick += 1
            accessTicks[key] = nextTick
            return cached
        }

        func storeLocked(_ entry: Entry, forKey key: String) {
            removeLocked(forKey: key)
            guard maxEntries > 0, entry.estimatedBytes <= maxBytes else {
                return
            }
            entries[key] = entry
            totalBytes += entry.estimatedBytes
            nextTick += 1
            accessTicks[key] = nextTick
            evictIfNeededLocked()
        }

        func removeLocked(forKey key: String) {
            if let removed = entries.removeValue(forKey: key) {
                totalBytes = max(0, totalBytes - removed.estimatedBytes)
            }
            accessTicks.removeValue(forKey: key)
        }

        func removeAllLocked() {
            entries.removeAll()
            accessTicks.removeAll()
            totalBytes = 0
        }

        func pruneMissingLocked(keeping visited: Set<String>) {
            for key in Array(entries.keys) where !visited.contains(key) {
                removeLocked(forKey: key)
            }
        }

        private func evictIfNeededLocked() {
            while entries.count > maxEntries || totalBytes > maxBytes {
                guard let lruKey = accessTicks.min(by: { $0.value < $1.value })?.key else {
                    break
                }
                removeLocked(forKey: lruKey)
            }
        }

        func invalidate(_ url: URL) {
            lock.lock()
            defer { lock.unlock() }
            removeLocked(forKey: Self.key(for: url))
        }
    }

    func delete(_ transcript: Transcript) {
        Self.metadataLock.lock()
        defer { Self.metadataLock.unlock() }

        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try? fileManager.removeItem(at: url)
        searchCache.invalidate(url)
        try? fileManager.removeItem(at: recentMetadataURL(for: url))
    }

    // MARK: - Crash recovery (temporary transcripts)

    /// クラッシュ復旧用に一時的な Transcript を保存する。
    func saveTemporary(_ transcript: Transcript) throws {
        try writeTemporary(encode(transcript))
    }

    /// クラッシュ復旧用の一時 Transcript を読み込む。なければ nil。
    func loadTemporary() -> Transcript? {
        let url = temporaryRoot.appendingPathComponent("recovery.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Transcript.self, from: data)
    }

    /// クラッシュ復旧用の一時 Transcript を削除する。
    func clearTemporary() {
        let url = temporaryRoot.appendingPathComponent("recovery.json")
        try? fileManager.removeItem(at: url)
    }
}
