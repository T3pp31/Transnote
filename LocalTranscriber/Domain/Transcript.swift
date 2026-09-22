import Foundation

struct Transcript: Codable, Identifiable, Sendable {
    let id: UUID
    let sourceFileName: String
    let language: String?
    let createdAt: Date
    var fullText: String
    var segments: [TranscriptSegment]
    /// 元音声ファイルの識別用フィンガープリント（SHA256）。
    var sourceFileFingerprint: String?

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        language: String? = nil,
        createdAt: Date = Date(),
        fullText: String = "",
        segments: [TranscriptSegment] = [],
        sourceFileFingerprint: String? = nil
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.language = language
        self.createdAt = createdAt
        self.fullText = fullText
        self.segments = segments
        self.sourceFileFingerprint = sourceFileFingerprint
    }
}
