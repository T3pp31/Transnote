import Foundation

struct TranscriptSegment: Codable, Identifiable, Sendable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}
