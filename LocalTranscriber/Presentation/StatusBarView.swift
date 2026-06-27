import SwiftUI

struct StatusBarView: View {
    let uiState: TranscriptionUIState
    let progress: TranscriptionProgressDisplay
    let inlineErrorTitle: String?
    let canCancel: Bool
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            statusContent
            Spacer(minLength: 8)
            if canCancel {
                cancelButton
            }
        }
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var statusContent: some View {
        if let inlineErrorTitle {
            Label(inlineErrorTitle, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else {
            switch uiState {
            case .idle:
                Label("準備完了", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .preparing, .transcribing:
                activeProgressRow
            case .done:
                Label("完了", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var activeProgressRow: some View {
        HStack(spacing: 10) {
            PhaseIconView(phase: progress.phase, reduceMotion: reduceMotion)

            progressBar

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.primaryLabel)
                    .font(.subheadline)
                if let detail = progress.detailLabel {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progress.accessibilityLabel)
        .accessibilityValue(progress.accessibilityValue)
        .accessibilityAddTraits(shouldAnnounceProgress ? .updatesFrequently : [])
    }

    @ViewBuilder
    private var progressBar: some View {
        switch progress.style {
        case .hidden:
            EmptyView()
        case .indeterminate:
            ProgressView()
                .controlSize(.small)
                .frame(width: 120)
        case .determinate:
            ProgressView(value: progress.fraction ?? 0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
        }
    }

    private var cancelButton: some View {
        Button("キャンセル") {
            onCancel()
        }
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("文字起こしをキャンセル")
    }

    private var shouldAnnounceProgress: Bool {
        progress.phase == .downloadingModel || progress.phase == .transcribing
    }
}

struct PhaseIconView: View {
    let phase: TranscriptionProgressPhase
    let reduceMotion: Bool

    var body: some View {
        Image(systemName: symbolName)
            .font(.body)
            .foregroundStyle(foregroundColor)
            .symbolEffect(.variableColor.iterative, isActive: isAnimating && !reduceMotion)
            .frame(width: 20)
    }

    private var symbolName: String {
        switch phase {
        case .downloadingModel:
            return "arrow.down.circle"
        case .loadingModel:
            return "memorychip"
        case .convertingAudio:
            return "waveform.badge.mic"
        case .transcribing:
            return "waveform"
        case .initializing:
            return "gearshape"
        case .finished:
            return "checkmark.circle.fill"
        }
    }

    private var foregroundColor: Color {
        switch phase {
        case .downloadingModel, .transcribing:
            return .accentColor
        case .finished:
            return .green
        default:
            return .secondary
        }
    }

    private var isAnimating: Bool {
        switch phase {
        case .downloadingModel, .loadingModel, .convertingAudio, .transcribing, .initializing:
            return true
        case .finished:
            return false
        }
    }
}
