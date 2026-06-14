import Foundation

struct TranscriptionProgressDisplay: Equatable {
    enum ProgressStyle: Equatable {
        case hidden
        case indeterminate
        case determinate
    }

    let phase: TranscriptionProgressPhase
    let style: ProgressStyle
    let fraction: Double?
    let primaryLabel: String
    let detailLabel: String?

    var accessibilityLabel: String {
        if let modelName = detailLabel?.components(separatedBy: " · ").first, !modelName.isEmpty {
            return "\(primaryLabel)、\(modelName)"
        }
        return primaryLabel
    }

    var accessibilityValue: String {
        switch style {
        case .determinate:
            let percent = Int((fraction ?? 0) * 100)
            return "\(percent)パーセント完了"
        case .indeterminate:
            return "進行中"
        case .hidden:
            return ""
        }
    }

    static func from(update: TranscriptionProgressUpdate) -> TranscriptionProgressDisplay {
        let primaryLabel = update.phase.rawValue
        let detailLabel = makeDetailLabel(for: update)

        let style: ProgressStyle
        let fraction: Double?

        switch update.phase {
        case .downloadingModel, .transcribing:
            style = .determinate
            fraction = min(1.0, max(0.0, update.fraction))
        case .loadingModel, .convertingAudio, .initializing:
            style = .indeterminate
            fraction = nil
        case .finished:
            style = .hidden
            fraction = 1.0
        }

        return TranscriptionProgressDisplay(
            phase: update.phase,
            style: style,
            fraction: fraction,
            primaryLabel: primaryLabel,
            detailLabel: detailLabel
        )
    }

    static func idle() -> TranscriptionProgressDisplay {
        TranscriptionProgressDisplay(
            phase: .finished,
            style: .hidden,
            fraction: nil,
            primaryLabel: "準備完了",
            detailLabel: nil
        )
    }

    static func done() -> TranscriptionProgressDisplay {
        TranscriptionProgressDisplay(
            phase: .finished,
            style: .hidden,
            fraction: 1.0,
            primaryLabel: "完了",
            detailLabel: nil
        )
    }

    private static func makeDetailLabel(for update: TranscriptionProgressUpdate) -> String? {
        switch update.phase {
        case .downloadingModel:
            if let modelName = update.modelDisplayName {
                if let completed = update.completedUnitCount,
                   let total = update.totalUnitCount,
                   total > 0 {
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .file
                    let completedText = formatter.string(fromByteCount: completed)
                    let totalText = formatter.string(fromByteCount: total)
                    return "\(modelName) · \(completedText) / \(totalText)"
                }
                let percent = Int(update.fraction * 100)
                return "\(modelName) · \(percent)%"
            }
            let percent = Int(update.fraction * 100)
            return "\(percent)%"

        case .loadingModel:
            return update.modelDisplayName

        case .transcribing:
            let percent = Int(update.fraction * 100)
            return percent > 0 ? "\(percent)%" : nil

        case .initializing, .convertingAudio, .finished:
            return update.modelDisplayName
        }
    }
}
