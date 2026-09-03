import SwiftUI

struct TranscriptEditorView: View {
    @Binding var text: String
    let isEditable: Bool
    let isBusy: Bool
    let segments: [TranscriptSegment]?
    let playingSegmentID: UUID?
    @Binding var isEditing: Bool
    let onSegmentTap: (TranscriptSegment) -> Void
    let onCopy: () -> Void
    var needsModelDownload: Bool = false

    @FocusState private var isEditorFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var hasPlayableSegments: Bool {
        guard let segments else { return false }
        return !segments.isEmpty
    }

    private var isShowingEmptyPlaceholder: Bool {
        text.isEmpty && !isBusy && !isEditable
    }

    private let cornerRadius: CGFloat = DesignTokens.Corner.card
    private let cardPadding: CGFloat = DesignTokens.Card.padding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, DesignTokens.Spacing.controlSpacing)

            Divider()
                .overlay(DesignTokens.Colors.border(colorScheme))
                .padding(.bottom, DesignTokens.Spacing.controlSpacing)

            editorContent
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardSurface)
        .opacity(isShowingEmptyPlaceholder ? 0.72 : 1)
        .accessibilityElement(children: .contain)
        .onChange(of: isEditing) { isEditing in
            if isEditing {
                isEditorFocused = true
            }
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        Group {
            if isEditable {
                if isEditing {
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(DesignTokens.Spacing.compactSpacing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
                        )
                        .focused($isEditorFocused)
                } else if hasPlayableSegments, let segments {
                    segmentPlaybackView(segments: segments)
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.compactSpacing) {
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
                    .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
            }
    }

    private var header: some View {
        HStack {
            Text("文字起こし結果")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("文字起こし")
            if isBusy, !text.isEmpty {
                Text(
                    NSLocalizedString("途中結果", comment: "Partial transcription result badge")
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.16))
                )
                .foregroundStyle(.orange)
                .accessibilityLabel(
                    NSLocalizedString("途中結果", comment: "Partial transcription result badge")
                )
            }
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
            if isEditing {
                copyButton
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("文字起こし結果全体をコピー（⌘⇧C）")
            } else {
                copyButton
                    .keyboardShortcut("c", modifiers: [.command])
                    .help("文字起こし結果をコピー（⌘C）")
            }
        }
    }

    private var copyButton: some View {
        Button("コピー") {
            onCopy()
        }
        .disabled(text.isEmpty)
        .accessibilityLabel("文字起こしをコピー")
        .accessibilityHint("クリップボードに文字起こし結果全体をコピーします")
    }

    private var readOnlyTextView: some View {
        ScrollView {
            Text(text.isEmpty ? emptyStateMessage : text)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.compactSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
        )
    }

    private var emptyStateMessage: String {
        if isBusy {
            return NSLocalizedString("処理が完了するまでお待ちください", comment: "Wait for processing empty state")
        }
        if needsModelDownload {
            return NSLocalizedString(
                "初回はモデルのダウンロードが必要です。音声ファイルを選択・ドロップ後、「文字起こしを開始」してください。",
                comment: "Empty state prompting model download"
            )
        }
        return NSLocalizedString("音声ファイルをドロップまたは選択して、文字起こしを開始してください", comment: "Empty state prompting file selection")
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
            .padding(DesignTokens.Spacing.compactSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.inner, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border(colorScheme), lineWidth: 1)
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
                    .frame(width: DesignTokens.Icon.compact)
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
                RoundedRectangle(cornerRadius: DesignTokens.Corner.segment)
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
            return Color.accentColor.opacity(0.18)
        }
        if isHovered {
            return Color.secondary.opacity(0.08)
        }
        return Color.clear
    }
}
