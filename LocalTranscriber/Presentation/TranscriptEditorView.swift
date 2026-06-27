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

    private let cornerRadius: CGFloat = 14
    private let cardPadding: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)

            Divider()
                .overlay(Color.primary.opacity(0.08))
                .padding(.bottom, 12)

            editorContent
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardSurface)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var editorContent: some View {
        Group {
            if isEditable {
                if isEditing {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cardSurface: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private var header: some View {
        HStack {
            Text("文字起こし結果")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("文字起こし")
            Spacer()
            if isEditable, !text.isEmpty {
                Picker("表示", selection: $isEditing) {
                    Text("再生").tag(false)
                    Text("編集").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .accessibilityLabel("表示モード")
                .accessibilityHint("再生モードと編集モードを切り替えます")
            }
            Button("コピー") {
                onCopy()
            }
            .disabled(text.isEmpty)
            .keyboardShortcut("c", modifiers: [.command])
            .accessibilityLabel("文字起こしをコピー")
            .accessibilityHint("クリップボードに文字起こし結果をコピーします")
        }
    }

    private var readOnlyTextView: some View {
        ScrollView {
            Text(text.isEmpty ? "文字起こし結果がここに表示されます" : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
