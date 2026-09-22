import Foundation

struct TranscriptionJob: Identifiable, Sendable {
    let id: UUID
    let audioFileURL: URL
    let sourceFileName: String
    let modelID: String
    let whisperKitModelName: String
    let modelDisplayName: String
    let languageID: String
    let vadEnabled: Bool

    init(
        id: UUID = UUID(),
        audioFileURL: URL,
        sourceFileName: String,
        modelID: String,
        whisperKitModelName: String,
        modelDisplayName: String,
        languageID: String,
        vadEnabled: Bool = false
    ) {
        self.id = id
        self.audioFileURL = audioFileURL
        self.sourceFileName = sourceFileName
        self.modelID = modelID
        self.whisperKitModelName = whisperKitModelName
        self.modelDisplayName = modelDisplayName
        self.languageID = languageID
        self.vadEnabled = vadEnabled
    }
}
