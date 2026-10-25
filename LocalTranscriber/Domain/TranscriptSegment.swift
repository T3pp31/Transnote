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

    var formattedStartTime: String {
        Self.formatDisplayTimestamp(startTime, separator: ".")
    }

    var accessibilityStartTimestamp: String {
        Self.formatAccessibilityTimestamp(startTime)
    }

    private static func clampedNonnegativeTime(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite else { return 0 }
        let maximumTime = Double(Int.max / 1_000_000)
        return min(max(0, time), maximumTime)
    }

    private static func formatDisplayTimestamp(_ time: TimeInterval, separator: String) -> String {
        let clampedTime = Self.clampedNonnegativeTime(time)
        let totalMilliseconds = Int(clampedTime * 1000)
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d\(separator)%03d", hours, minutes, seconds, milliseconds)
    }

    private static func formatAccessibilityTimestamp(_ time: TimeInterval) -> String {
        let clampedTime = Self.clampedNonnegativeTime(time)
        let totalSeconds = Int(clampedTime.rounded(.down))
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
