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

    var accessibilityStartTimestamp: String {
        Self.formatAccessibilityTimestamp(startTime)
    }

    private static func formatAccessibilityTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d時間%d分%d秒", hours, minutes, seconds)
        }
        if minutes > 0 {
            return String(format: "%d分%d秒", minutes, seconds)
        }
        return String(format: "%d秒", seconds)
    }
}
