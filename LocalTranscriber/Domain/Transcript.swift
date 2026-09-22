import Foundation

struct Transcript: Codable, Identifiable, Sendable {
    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
    /// 最後に編集された日時（未編集なら nil）。
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        language: String? = nil,
        createdAt: Date = Date(),
        fullText: String = "",
        segments: [TranscriptSegment] = [],
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.language = language
        self.createdAt = createdAt
        self.fullText = fullText
        self.segments = segments
        self.updatedAt = updatedAt
    }
}
