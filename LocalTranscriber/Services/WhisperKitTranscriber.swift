import AVFoundation
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

            var completedText: String = ""
            whisperKit.segmentDiscoveryCallback = { segments in
                guard let partialText = TranscriptPartialTextBuilder.appendPresentableWindowText(
                    from: segments.map(\.text),
                    to: &completedText
                ) else {
                    return
                }

                let fraction = whisperKit.progress.fractionCompleted
                progressHandler?(
                    .make(
                        phase: .transcribing,
                        fraction: fraction > 0 ? fraction : 0,
                        modelDisplayName: job.modelDisplayName,
                        partialText: partialText
                    )
                )
            }
            defer {
                whisperKit.segmentDiscoveryCallback = nil
            }

            // 長時間音声はチャンク単位で処理する（WhisperKit への一度の投入を避ける）。
            let chunks = await splitAudioIntoChunks(url: job.audioFileURL, chunkDuration: job.chunkDuration)
            var allResults: [TranscriptionResult] = []
            var processedSeconds: TimeInterval = 0
            var totalSeconds: TimeInterval = chunks.count > 1
                ? (try? await AVURLAsset(url: job.audioFileURL).load(.duration).seconds) ?? Double(chunks.count)
                : Double(chunks.count)

            for (index, chunkURL) in chunks.enumerated() {
                try Task.checkCancellation()
                let results = try await whisperKit.transcribe(
                    audioPath: chunkURL.path,
                    decodeOptions: decodeOptions,
                    callback: { progress in
                        let localFraction = whisperKit.progress.fractionCompleted
                        computed: do {
                            let overall = totalSeconds > 0
                                ? min(1.0, (Double(index) + max(0, localFraction)) / Double(chunks.count))
                                : 0
                            progressHandler?(
                                .make(
                                    phase: .transcribing,
                                    fraction: overall,
                                    modelDisplayName: job.modelDisplayName
                                )
                            )
                        }
                        return true
                    }
                )
                allResults.append(contentsOf: results)
                processedSeconds += (try? await AVURLAsset(url: chunkURL).load(.duration).seconds) ?? 0
            }

            try Task.checkCancellation()

            let merged = TranscriptionUtilities.mergeTranscriptionResults(allResults)
            progressHandler?(
                .make(phase: .finished, fraction: 1.0, modelDisplayName: job.modelDisplayName)
            )

            return mapToTranscript(
                merged,
                sourceFileName: job.sourceFileName,
                tokenizer: whisperKit.tokenizer
            )
        } catch is CancellationError {
            throw AppError.transcriptionCancelled
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.transcriptionFailedWithReason(error)
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
                NSLocalizedString(
                    "モデルファイルが不正です。ツールバーの「モデルをダウンロード」ボタンから再ダウンロードしてください。",
                    comment: "Invalid model files guidance"
                )
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
                "Model load failed at \(modelPath.lastPathComponent): \(error.localizedDescription)",
                logger: AppLogger.transcription
            )
            throw AppError.transcriptionFailed(
                NSLocalizedString(
                    "モデルの読み込みに失敗しました。ツールバーの「モデルをダウンロード」ボタンから再ダウンロードしてください。",
                    comment: "Model load failed guidance"
                )
            )
        }
    }

    private func resolveModelPath(
        modelName: String,
        modelDisplayName: String?
    ) throws -> URL {
        if let existingPath = modelAvailability.modelFolder(for: modelName) {
            AppLogger.info("Using cached model at \(existingPath.lastPathComponent)", logger: AppLogger.transcription)
            return existingPath
        }

        let displayName = modelDisplayName ?? modelName
        throw AppError.modelNotDownloaded(displayName)
    }

    private func loadWhisperKit(modelName: String, modelPath: URL) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            model: modelName,
            downloadBase: AppDirectories.modelsDirectory,
            modelFolder: modelPath.path,
            verbose: false,
            logLevel: .error,
            load: true,
            download: false
        )

        return try await WhisperKit(config)
    }

    /// 長時間音声を指定チャンク長で分割して一時ファイルを返す。
    /// 分割不要（既にチャンク長以下）の場合は元ファイルを返す。
    private func splitAudioIntoChunks(url: URL, chunkDuration: TimeInterval) async -> [URL] {
        guard chunkDuration > 0 else { return [url] }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > chunkDuration else {
            return [url]
        }

        let chunkCount = Int(ceil(duration / chunkDuration))
        var outputURLs: [URL] = []
        for index in 0..<chunkCount {
            let start = Double(index) * chunkDuration
            let end = min(start + chunkDuration, duration)
            let outputURL = AppDirectories.checkpointDirectory
                .appendingPathComponent("chunk-\(index).m4a")
            try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: outputURL)

            let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
            export?.outputURL = outputURL
            export?.outputFileType = .m4a
            export?.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))

            let semaphore = DispatchSemaphore(value: 0)
            export?.exportAsynchronously { semaphore.signal() }
            semaphore.wait()
            if export?.status == .completed {
                outputURLs.append(outputURL)
            }
        }
        return outputURLs.isEmpty ? [url] : outputURLs
    }

    private func makeDecodingOptions(languageID: String) -> DecodingOptions {
        switch languageID {
        case "ja", "en":
            return DecodingOptions(
                language: languageID,
                usePrefillPrompt: true,
                detectLanguage: false,
                skipSpecialTokens: true
            )
        default:
            return DecodingOptions(
                language: nil,
                usePrefillPrompt: false,
                detectLanguage: true,
                skipSpecialTokens: true
            )
        }
    }

    private static func decodeWordTokens(_ tokens: [Int], using tokenizer: WhisperTokenizer) -> String {
        let wordTokens = tokens.filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        guard !wordTokens.isEmpty else { return "" }
        return TranscriptTextSanitizer.sanitize(tokenizer.decode(tokens: wordTokens))
    }

    private static func mapWhisperKitSegment(
        _ segment: TranscriptionSegment,
        tokenizer: WhisperTokenizer
    ) -> TranscriptSegment {
        let text = TranscriptTextSanitizer.presentableText(from: segment.text)
            ?? decodeWordTokens(segment.tokens, using: tokenizer)
        return TranscriptSegment(
            startTime: TimeInterval(segment.start),
            endTime: TimeInterval(segment.end),
            text: text
        )
    }

    private static func mapWhisperKitSegment(_ segment: TranscriptionSegment) -> TranscriptSegment {
        TranscriptSegment(
            startTime: TimeInterval(segment.start),
            endTime: TimeInterval(segment.end),
            text: TranscriptTextSanitizer.presentableText(from: segment.text) ?? ""
        )
    }

    private func mapToTranscript(
        _ result: TranscriptionResult,
        sourceFileName: String,
        tokenizer: WhisperTokenizer?
    ) -> Transcript {
        let segments: [TranscriptSegment]
        if let tokenizer {
            segments = result.segments.map { Self.mapWhisperKitSegment($0, tokenizer: tokenizer) }
        } else {
            segments = result.segments.map(Self.mapWhisperKitSegment)
        }

        let fullText = TranscriptTextSanitizer.presentableText(from: result.text)
            ?? TranscriptTextSanitizer.sanitize(result.text)

        return Transcript(
            sourceFileName: sourceFileName,
            language: result.language.isEmpty ? nil : result.language,
            fullText: fullText,
            segments: segments
        )
    }
}
