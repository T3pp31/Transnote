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
            Button("コピー") {
                onCopy()
            }
            .disabled(text.isEmpty)
            .keyboardShortcut("c", modifiers: [.command])
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

    var body: some View {
        Button(action: onTap) {
            Text(segment.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("\(segment.text), playable segment")
        .accessibilityValue(isPlaying ? "Playing" : "")
        .accessibilityAddTraits(.isButton)
    }

    private var backgroundColor: Color {
        if isPlaying {
            return Color.accentColor.opacity(0.25)
        }
        if isHovered {
            return Color.secondary.opacity(0.12)
        }
        return Color.clear
    }
}
