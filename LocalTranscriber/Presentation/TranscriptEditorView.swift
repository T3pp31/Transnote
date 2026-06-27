import SwiftUI

struct TranscriptEditorView: View {
    @Binding var text: String
    let isEditable: Bool
    let segments: [TranscriptSegment]?
    let playingSegmentID: UUID?
    @Binding var isEditing: Bool
    let onSegmentTap: (TranscriptSegment) -> Void
    let onCopy: () -> Void

    private var hasPlayableSegments: Bool {
        guard let segments else { return false }
        return !segments.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if isEditable {
                if isEditing {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                } else if hasPlayableSegments, let segments {
                    segmentPlaybackView(segments: segments)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        readOnlyTextView
                        if !text.isEmpty {
                            Text("タイムスタンプ情報がないため、クリック再生は利用できません。編集モードでテキストを修正できます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                readOnlyTextView
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack {
            Text("Transcript")
                .font(.headline)
            Spacer()
            if isEditable, !text.isEmpty {
                Picker("表示", selection: $isEditing) {
                    Text("再生").tag(false)
                    Text("編集").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .accessibilityHint("再生モードと編集モードを切り替えます")
            }
            Button("Copy") {
                onCopy()
            }
            .disabled(text.isEmpty)
            .keyboardShortcut("c", modifiers: [.command])
        }
    }

    private var readOnlyTextView: some View {
        ScrollView {
            Text(text.isEmpty ? "Transcription result will appear here." : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2))
        )
    }

    private func segmentPlaybackView(segments: [TranscriptSegment]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(segments) { segment in
                    SegmentPlaybackRow(
                        segment: segment,
                        isPlaying: playingSegmentID == segment.id,
                        onTap: { onSegmentTap(segment) }
                    )
                }
            }
            .padding(8)
        }
        .frame(minHeight: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2))
        )
    }
}

private struct SegmentPlaybackRow: View {
    let segment: TranscriptSegment
    let isPlaying: Bool
    let onTap: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.caption)
                    .foregroundStyle(isPlaying ? Color.accentColor : .secondary)
                    .frame(width: 14)
                    .symbolEffect(.variableColor, isActive: isPlaying && !reduceMotion)

                Text(segment.formattedStartTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 88, alignment: .leading)

                Text(segment.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            }
            .overlay(alignment: .leading) {
                if isPlaying {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .accessibilityLabel("\(segment.accessibilityStartTimestamp)、\(segment.text)、タップで再生")
        .accessibilityValue(isPlaying ? "再生中" : "")
        .accessibilityAddTraits(.isButton)
    }

    private var backgroundColor: Color {
        if isPlaying {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color.secondary.opacity(0.08)
        }
        return Color.clear
    }
}
