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
            Button("Copy") {
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
        .accessibilityLabel("\(segment.accessibilityStartTimestamp)、\(segment.text)、タップで再生")
        .accessibilityValue(isPlaying ? "再生中" : "")
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
