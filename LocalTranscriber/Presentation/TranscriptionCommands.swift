import SwiftUI

struct TranscriptionActions: FocusedValueKey {
    typealias Value = TranscriptionActionsValue
}

struct TranscriptionActionsValue {
    let canStart: Bool
    let startTranscription: () -> Void
    let canCancel: Bool
    let cancelTranscription: () -> Void
    let cancelMenuTitle: String
    let canCopy: Bool
    let copyTranscript: () -> Void
    let openFile: () -> Void
}

extension FocusedValues {
    var transcriptionActions: TranscriptionActionsValue? {
        get { self[TranscriptionActions.self] }
        set { self[TranscriptionActions.self] = newValue }
    }
}

struct TranscriptionCommands: Commands {
    @FocusedValue(\.transcriptionActions) private var actions: TranscriptionActionsValue?

    var body: some Commands {
        CommandMenu("文字起こし") {
            Button("文字起こしを開始") {
                actions?.startTranscription()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(actions?.canStart != true)

            Button("ファイルを開く…") {
                actions?.openFile()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(actions == nil)

            Button("結果をすべてコピー") {
                actions?.copyTranscript()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(actions?.canCopy != true)

            Button(actions?.cancelMenuTitle ?? NSLocalizedString("キャンセル", comment: "Cancel")) {
                actions?.cancelTranscription()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(actions?.canCancel != true)
        }
    }
}
