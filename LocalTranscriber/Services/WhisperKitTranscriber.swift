import Foundation
import WhisperKit

final class WhisperKitTranscriber: Transcriber, @unchecked Sendable {
    private let lock = NSLock()
    private var activeTasks: [UUID: Task<Transcript, Error>] = [:]
    private var whisperKit: WhisperKit?
    private var currentModelName: String?
    private let modelAvailability: ModelAvailabilityService

    init(modelAvailability: ModelAvailabilityService = ModelAvailabilityService()) {
        self.modelAvailability = modelAvailability
    }

    func transcribe(
        _ job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)? = nil
    ) async throws -> Transcript {
        let task = Task<Transcript, Error> {
            try await self.performTranscription(job: job, progressHandler: progressHandler)
        }

        lock.lock()
        activeTasks[job.id] = task
        lock.unlock()

        defer {
            lock.lock()
            activeTasks.removeValue(forKey: job.id)
            lock.unlock()
        }

        return try await task.value
    }

    func cancel(jobID: UUID) {
        lock.lock()
        let task = activeTasks[jobID]
        lock.unlock()
        task?.cancel()
    }

    private func performTranscription(
        job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        do {
            try Task.checkCancellation()

            progressHandler?(
                .make(phase: .initializing, fraction: 0, modelDisplayName: job.modelDisplayName)
            )

            let whisperKit = try await prepareWhisperKit(
                modelName: job.whisperKitModelName,
                modelDisplayName: job.modelDisplayName,
                progressHandler: progressHandler
            )

            try Task.checkCancellation()

            guard FileManager.default.isReadableFile(atPath: job.audioFileURL.path) else {
                throw AppError.fileAccessDenied
            }

            let decodeOptions = makeDecodingOptions(languageID: job.languageID)

            progressHandler?(
                .make(phase: .convertingAudio, fraction: 0, modelDisplayName: job.modelDisplayName)
            )

            let results = try await whisperKit.transcribe(
                audioPath: job.audioFileURL.path,
                decodeOptions: decodeOptions,
                callback: { progress in
                    let fraction = whisperKit.progress.fractionCompleted
                    let resolvedFraction = fraction > 0
                        ? fraction
                        : min(1.0, max(0.0, Double(progress.windowId + 1) / 10.0))
                    progressHandler?(
                        .make(
                            phase: .transcribing,
                            fraction: resolvedFraction,
                            modelDisplayName: job.modelDisplayName
                        )
                    )
                    return true
                }
            )

            try Task.checkCancellation()

            let merged = TranscriptionUtilities.mergeTranscriptionResults(results)
            progressHandler?(
                .make(phase: .finished, fraction: 1.0, modelDisplayName: job.modelDisplayName)
            )

            return mapToTranscript(merged, sourceFileName: job.sourceFileName)
        } catch is CancellationError {
            throw AppError.transcriptionCancelled
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.transcriptionFailed(ErrorMapper.userMessage(for: error))
        }
    }

    private func prepareWhisperKit(
        modelName: String,
        modelDisplayName: String?,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> WhisperKit {
        if let whisperKit, currentModelName == modelName {
            return whisperKit
        }

        AppDirectories.ensureDirectoriesExist()

        let modelPath = try resolveModelPath(
            modelName: modelName,
            modelDisplayName: modelDisplayName
        )

        guard modelAvailability.validateModelFolder(modelPath) else {
            throw AppError.transcriptionFailed(
                "モデルファイルが不正です。ツールバーの「Download」ボタンから再ダウンロードしてください。"
            )
        }

        progressHandler?(
            .make(phase: .loadingModel, fraction: 0, modelDisplayName: modelDisplayName)
        )

        do {
            let instance = try await loadWhisperKit(modelName: modelName, modelPath: modelPath)
            self.whisperKit = instance
            self.currentModelName = modelName
            return instance
        } catch {
            AppLogger.error(
                "Model load failed at \(modelPath.path): \(error.localizedDescription)",
                logger: AppLogger.transcription
            )
            throw AppError.transcriptionFailed(
                "モデルの読み込みに失敗しました。ツールバーの「Download」ボタンから再ダウンロードしてください。"
            )
        }
    }

    private func resolveModelPath(
        modelName: String,
        modelDisplayName: String?
    ) throws -> URL {
        if let existingPath = modelAvailability.modelFolder(for: modelName) {
            AppLogger.info("Using cached model at \(existingPath.path)", logger: AppLogger.transcription)
            return existingPath
        }

        let displayName = modelDisplayName ?? modelName
        throw AppError.modelNotDownloaded(displayName)
    }

    private func loadWhisperKit(modelName: String, modelPath: URL) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelPath.path,
            verbose: false,
            logLevel: .error,
            load: true,
            download: false
        )

        return try await WhisperKit(config)
    }

    private func makeDecodingOptions(languageID: String) -> DecodingOptions {
        switch languageID {
        case "ja", "en":
            return DecodingOptions(
                language: languageID,
                usePrefillPrompt: true,
                detectLanguage: false
            )
        default:
            return DecodingOptions(
                language: nil,
                usePrefillPrompt: false,
                detectLanguage: true
            )
        }
    }

    private func mapToTranscript(_ result: TranscriptionResult, sourceFileName: String) -> Transcript {
        let segments = result.segments.map { segment in
            TranscriptSegment(
                startTime: TimeInterval(segment.start),
                endTime: TimeInterval(segment.end),
                text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let fullText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        return Transcript(
            sourceFileName: sourceFileName,
            language: result.language.isEmpty ? nil : result.language,
            fullText: fullText,
            segments: segments
        )
    }
}
