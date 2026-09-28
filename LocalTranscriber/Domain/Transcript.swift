import Foundation

struct Transcript: Codable, Identifiable, Sendable {
    /// JSON エクスポートのスキーマバージョン。
    /// 将来のフィールド追加時はインクリメントする。
    static let currentSchemaVersion = 1

    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
    /// 文字起こしに使用したモデル ID（モデル設定の `id`）。
    var modelID: String?
    let schemaVersion: Int

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        language: String? = nil,
        createdAt: Date = Date(),
        fullText: String = "",
        segments: [TranscriptSegment] = [],
        modelID: String? = nil,
        schemaVersion: Int = Transcript.currentSchemaVersion
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.language = language
        self.createdAt = createdAt
        self.fullText = fullText
        self.segments = segments
        self.modelID = modelID
        self.schemaVersion = schemaVersion
    }

    // 既存 JSON（schemaVersion なし）も読み込めるよう decodeIfPresent を使う。
    private enum CodingKeys: String, CodingKey {
        case id, sourceFileName, language, createdAt, fullText, segments, modelID, schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fullText = try container.decode(String.self, forKey: .fullText)
        segments = try container.decode([TranscriptSegment].self, forKey: .segments)
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
    }
}
