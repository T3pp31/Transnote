import AVFoundation
import Foundation
import WhisperKit

actor WhisperKitTranscriber: Transcriber {
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
        // 同一 WhisperKit インスタンスでの並列 transcribe は禁止する。
        // activeTasks が非空なら新しいジョブを拒否する。
        let alreadyActive = !activeTasks.isEmpty
        guard !alreadyActive else {
            throw AppError.transcriptionFailed(
                NSLocalizedString(
                    "別の文字起こしが実行中のため開始できません。終了を待ってからもう一度お試しください。",
                    comment: "Parallel transcription rejected"
                )
            )
        }

        let task = Task<Transcript, Error> {
            try await self.performTranscription(job: job, progressHandler: progressHandler)
        }

        activeTasks[job.id] = task

        defer {
            activeTasks.removeValue(forKey: job.id)
        }

        return try await task.value
    }

    func cancel(jobID: UUID) async {
        activeTasks[jobID]?.cancel()
    }

    private func performTranscription(
        job: TranscriptionJob,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> Transcript {
        do {
            try Task.checkCancellation()

            // RTF（Real-Time Factor）計測: 処理時間 / 音声長。
            let measurementStart = Date()
            let audioDuration = try? await AVURLAsset(url: job.audioFileURL).load(.duration).seconds

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

            let decodeOptions = makeDecodingOptions(languageID: job.languageID, vadEnabled: job.vadEnabled)

            // チャンク全体の進捗を正規化するため、セグメント検出コールバックと
            // transcribe コールバックのどちらでも同一スケールを使う。
            let duration = (try? await AVURLAsset(url: job.audioFileURL).load(.duration).seconds) ?? 0
            let chunkCount = max(1, Int((duration / max(job.chunkDuration, 1)).rounded(.up)))
            let totalChunkCount = max(1, chunkCount)
            var currentChunkIndex = 0
            let normalizedOverallProgress: () -> Double = {
                min(1.0, (Double(currentChunkIndex) + max(0, whisperKit.progress.fractionCompleted))
                    / Double(totalChunkCount))
            }

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

                let fraction = normalizedOverallProgress()
                progressHandler?(
                    .make(
                        phase: .transcribing,
                        fraction: fraction > 0 ? fraction : 0,
                        modelDisplayName: job.modelDisplayName,
                        partialText: partialText
                    )
                )
                // 途中結果をディスクへチェックポイント保存（クラッシュ・終了時の復旧用）
                self.saveCheckpoint(text: partialText, for: job)
            }
            defer {
                whisperKit.segmentDiscoveryCallback = nil
            }

            // 長時間音声はチャンク単位で処理する（WhisperKit への一度の投入を避ける）。
            let chunks = try await splitAudioIntoChunks(url: job.audioFileURL, chunkDuration: job.chunkDuration)
            defer {
                for chunk in chunks where chunk.url != job.audioFileURL {
                    try? FileManager.default.removeItem(at: chunk.url)
                }
            }
            var allResults: [TranscriptionResult] = []
            var processedSeconds: TimeInterval = 0
            var totalSeconds: TimeInterval = chunks.count > 1
                ? (try? await AVURLAsset(url: job.audioFileURL).load(.duration).seconds) ?? Double(chunks.count)
                : Double(chunks.count)

            for (index, chunk) in chunks.enumerated() {
                currentChunkIndex = index
                try Task.checkCancellation()
                let results = try await whisperKit.transcribe(
                    audioPath: chunk.url.path,
                    decodeOptions: decodeOptions,
                    callback: { progress in
                        let overall = totalSeconds > 0 ? normalizedOverallProgress() : 0
                        progressHandler?(
                            .make(
                                phase: .transcribing,
                                fraction: overall,
                                modelDisplayName: job.modelDisplayName
                            )
                        )
                        // キャンセル時は false を返し、WhisperKit の内部処理を即時停止させる。
                        return !Task.isCancelled
                    }
                )
                let offsetResults = results.map { result in
                    var adjusted = result
                    adjusted.segments = result.segments.map { segment in
                        var adjustedSegment = segment
                        adjustedSegment.start += Float(chunk.startSeconds)
                        adjustedSegment.end += Float(chunk.startSeconds)
                        return adjustedSegment
                    }
                    return adjusted
                }
                allResults.append(contentsOf: offsetResults)
                processedSeconds += (try? await AVURLAsset(url: chunk.url).load(.duration).seconds) ?? 0
            }

            try Task.checkCancellation()

            let merged = TranscriptionUtilities.mergeTranscriptionResults(allResults)
            progressHandler?(
                .make(phase: .finished, fraction: 1.0, modelDisplayName: job.modelDisplayName)
            )

            // RTF をログ・診断情報として記録する。
            let elapsed = Date().timeIntervalSince(measurementStart)
            if let duration = audioDuration, duration > 0 {
                let rtf = elapsed / duration
                AppLogger.info(
                    "Transcription RTF: \(String(format: "%.3f", rtf)) (elapsed \(String(format: "%.1f", elapsed))s / audio \(String(format: "%.1f", duration))s)",
                    logger: AppLogger.transcription
                )
            } else {
                AppLogger.info(
                    "Transcription elapsed: \(String(format: "%.1f", elapsed))s (audio duration unknown)",
                    logger: AppLogger.transcription
                )
            }

            return mapToTranscript(
                merged,
                sourceFileName: job.sourceFileName,
                tokenizer: whisperKit.tokenizer,
                modelID: job.modelID,
                sourceFileFingerprint: AudioFileService.sha256(of: job.audioFileURL)
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

    /// WhisperKit が言語コードを明示指定できる言語（ISO 639-1）。
    /// ここに含まれない ID は自動検出（detectLanguage）にフォールバックする。
    private static let explicitLanguageIDs: Set<String> = [
        "ja", "en", "zh", "ko", "fr", "de", "es", "it", "pt", "ru"
    ]

    /// 途中結果をディスクへチェックポイント保存する。
    /// クラッシュ・アプリ終了時に、このファイルから再開・復旧できる。
    private func saveCheckpoint(text: String, for job: TranscriptionJob) {
        guard !text.isEmpty else { return }
        let directory = AppDirectories.checkpointDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(job.id.uuidString).json")
        let payload: [String: Any] = [
            "jobID": job.id.uuidString,
            "sourceFileName": job.sourceFileName,
            "text": text,
            "updatedAt": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
    }


    /// 長時間音声を指定チャンク長で分割して一時ファイルを返す。
    /// 分割不要（既にチャンク長以下）の場合は元ファイルを返す。
    struct ChunkExportFailure: LocalizedError {
        let outputURL: URL
        let statusText: String

        var errorDescription: String? {
            "チャンクの書き出しに失敗しました: \(outputURL.lastPathComponent) (\(statusText))"
        }
    }

    struct AudioChunk: Sendable {
        let url: URL
        let startSeconds: TimeInterval
    }

    nonisolated func splitAudioIntoChunks(
        url: URL,
        chunkDuration: TimeInterval,
        outputDirectory: URL = AppDirectories.checkpointDirectory,
        makeExportSession: (AVAsset) -> AVAssetExportSession? = {
            AVAssetExportSession(asset: $0, presetName: AVAssetExportPresetPassthrough)
        }
    ) async throws -> [AudioChunk] {
        try Task.checkCancellation()
        guard chunkDuration > 0 else { return [AudioChunk(url: url, startSeconds: 0)] }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration > chunkDuration else {
            return [AudioChunk(url: url, startSeconds: 0)]
        }

        // チャンク境界をまたぐ発話を失わないよう、隣接チャンクに1秒のオーバーラップを持たせる。
        let overlap = min(1.0, max(0.0, chunkDuration / 4))
        let stride = max(0.1, chunkDuration - overlap)
        // 同時実行や前回の残留ファイルとの衝突を避ける。
        let exportID = UUID().uuidString
        var outputChunks: [AudioChunk] = []
        var createdURLs: [URL] = []
        var completed = false
        defer {
            if !completed {
                for outputURL in createdURLs {
                    try? FileManager.default.removeItem(at: outputURL)
                }
            }
        }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var start: TimeInterval = 0
        var index = 0
        while start < duration {
            try Task.checkCancellation()
            let end = min(start + chunkDuration, duration)
            let outputURL = outputDirectory.appendingPathComponent("chunk-\(exportID)-\(index).m4a")
            createdURLs.append(outputURL)

            guard let export = makeExportSession(asset) else {
                throw ChunkExportFailure(outputURL: outputURL, statusText: "export session unavailable")
            }
            export.outputURL = outputURL
            export.outputFileType = .m4a
            export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))

            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    export.exportAsynchronously { continuation.resume() }
                }
            } onCancel: {
                export.cancelExport()
            }
            try Task.checkCancellation()
            guard export.status == .completed else {
                let statusMessage = export.error?.localizedDescription ?? "unknown error"
                throw ChunkExportFailure(outputURL: outputURL, statusText: "\(export.status) \(statusMessage)")
            }
            outputChunks.append(AudioChunk(url: outputURL, startSeconds: start))
            index += 1
            start += stride
        }
        completed = true
        return outputChunks.isEmpty ? [AudioChunk(url: url, startSeconds: 0)] : outputChunks
    }

    private func makeDecodingOptions(languageID: String, vadEnabled: Bool = false) -> DecodingOptions {

        if Self.explicitLanguageIDs.contains(languageID) {

            return DecodingOptions(
                language: languageID,
                usePrefillPrompt: true,
                detectLanguage: false,
                skipSpecialTokens: true,
                chunkingStrategy: vadEnabled ? .vad : nil
            )
        }
        return DecodingOptions(
            language: nil,
            usePrefillPrompt: false,
            detectLanguage: true,
            skipSpecialTokens: true,
            chunkingStrategy: vadEnabled ? .vad : nil
        )
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
        tokenizer: WhisperTokenizer?,
        modelID: String?,
        sourceFileFingerprint: String?
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
            segments: segments,
            modelID: modelID,
            sourceFileFingerprint: sourceFileFingerprint
        )
    }
}
