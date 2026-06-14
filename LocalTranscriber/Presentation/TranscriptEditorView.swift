import SwiftUI

struct TranscriptEditorView: View {
    @Binding var text: String
    let isEditable: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    onCopy()
                }
                .disabled(text.isEmpty)
                .keyboardShortcut("c", modifiers: [.command])
            }

            if isEditable {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            } else {
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
        }
        .accessibilityElement(children: .contain)
    }
}
