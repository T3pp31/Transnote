import SwiftUI

struct TranscriptionActions: FocusedValueKey {
    typealias Value = TranscriptionActionsValue
}

struct TranscriptionActionsValue {
    let canStart: Bool
    let startTranscription: () -> Void
    let canCancel: Bool
    let cancelTranscription: () -> Void
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
            .disabled(actions?.canStart != true)

            Button("ファイルを開く…") {
                actions?.openFile()
            }

            Button("文字起こしをキャンセル") {
                actions?.cancelTranscription()
            }
            .disabled(actions?.canCancel != true)
        }
    }
}
