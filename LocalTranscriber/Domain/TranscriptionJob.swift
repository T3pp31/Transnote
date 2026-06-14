import Foundation

struct TranscriptionJob: Identifiable, Sendable {
    let id: UUID
    let audioFileURL: URL
    let sourceFileName: String
    let modelID: String
    let whisperKitModelName: String
    let modelDisplayName: String
    let languageID: String

    init(
        id: UUID = UUID(),
        audioFileURL: URL,
        sourceFileName: String,
        modelID: String,
        whisperKitModelName: String,
        modelDisplayName: String,
        languageID: String
    ) {
        self.id = id
        self.audioFileURL = audioFileURL
        self.sourceFileName = sourceFileName
        self.modelID = modelID
        self.whisperKitModelName = whisperKitModelName
        self.modelDisplayName = modelDisplayName
        self.languageID = languageID
    }
}
