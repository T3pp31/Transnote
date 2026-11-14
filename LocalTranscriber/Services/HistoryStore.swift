import Foundation

/// 文字起こし履歴を Application Support/History に JSON で保存・読み込みする。
struct HistoryStore: Sendable {
    private let historyRoot: URL
    private let fileManager: FileManager
    private let searchDataLoader: @Sendable (URL) throws -> Data
    private let searchCache = SearchCache()
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

    /// - Parameter searchDataLoader: 検索キャッシュの再利用と読み込み失敗を検証するための差し替え。
    init(
        historyRoot: URL = AppDirectories.historyDirectory,
        fileManager: FileManager = .default,
        searchDataLoader: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        readTranscriptData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.historyRoot = historyRoot
        self.fileManager = fileManager
        self.searchDataLoader = searchDataLoader
        self.readTranscriptData = readTranscriptData
    }

    func save(_ transcript: Transcript) throws {
        Self.metadataLock.lock()
        defer { Self.metadataLock.unlock() }

        try fileManager.createDirectory(at: historyRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        let url = historyRoot.appendingPathComponent("\(transcript.id.uuidString).json")
        try data.write(to: url, options: .atomic)
        searchCache.invalidate(url)
        if let version = fileVersion(at: url) {
            saveRecentMetadata(createdAt: transcript.createdAt, fileVersion: version, at: url)
        }
    }

    func recent(limit: Int = 50) -> [Transcript] {
        guard limit > 0 else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: historyRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [(url: URL, createdAt: Date)] = []
        for case let url as URL in enumerator {
            guard let createdAt = recentCreationDate(at: url) else { continue }
            candidates.append((url, createdAt))
        }
        candidates.sort { $0.createdAt > $1.createdAt }

        var items: [Transcript] = []
        for candidate in candidates {
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
