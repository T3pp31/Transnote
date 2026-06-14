import Foundation

protocol Transcriber: Sendable {
    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript

    func cancel(jobID: UUID)
}
