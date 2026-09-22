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
