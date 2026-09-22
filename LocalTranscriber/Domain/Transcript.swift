import Foundation

struct Transcript: Codable, Identifiable, Sendable {
    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
    /// 文字起こしに使用したモデル ID（モデル設定の `id`）。
    var modelID: String?

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        language: String? = nil,
        createdAt: Date = Date(),
        fullText: String = "",
        segments: [TranscriptSegment] = [],
        modelID: String? = nil
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.language = language
        self.createdAt = createdAt
        self.fullText = fullText
        self.segments = segments
        self.modelID = modelID
    }
}
