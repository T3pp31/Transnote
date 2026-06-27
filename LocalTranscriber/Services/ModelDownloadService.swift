import Foundation
import WhisperKit

struct ModelDownloadService: Sendable {
    private let modelsRoot: URL
    private let modelAvailability: ModelAvailabilityService

    init(
        modelsRoot: URL = AppDirectories.modelsDirectory,
        modelAvailability: ModelAvailabilityService? = nil
    ) {
        self.modelsRoot = modelsRoot
        self.modelAvailability = modelAvailability ?? ModelAvailabilityService(modelsRoot: modelsRoot)
    }

    /// 指定ディレクトリにモデルが存在すればそのパスを返し、なければダウンロードする。
    func downloadIfNeeded(
        whisperKitModelName: String,
        modelDisplayName: String?,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)? = nil
    ) async throws -> URL {
        if let existingPath = modelAvailability.modelFolder(for: whisperKitModelName) {
            AppLogger.info(
                "Model already available at \(existingPath.lastPathComponent)",
                logger: AppLogger.transcription
            )
            return existingPath
        }

        return try await download(
            whisperKitModelName: whisperKitModelName,
            modelDisplayName: modelDisplayName,
            progressHandler: progressHandler
        )
    }

    private func download(
        whisperKitModelName: String,
        modelDisplayName: String?,
        progressHandler: (@Sendable (TranscriptionProgressUpdate) -> Void)?
    ) async throws -> URL {
        AppDirectories.ensureDirectoriesExist()

        AppLogger.info("Downloading model: \(whisperKitModelName)", logger: AppLogger.transcription)
        progressHandler?(
            .make(phase: .downloadingModel, fraction: 0, modelDisplayName: modelDisplayName)
        )

        let downloadedPath = try await WhisperKit.download(
            variant: whisperKitModelName,
            downloadBase: modelsRoot,
            progressCallback: { progress in
                progressHandler?(
                    .make(
                        phase: .downloadingModel,
                        fraction: progress.fractionCompleted,
                        progress: progress,
                        modelDisplayName: modelDisplayName
                    )
                )
            }
        )

        guard modelAvailability.validateModelFolder(downloadedPath) else {
            throw AppError.transcriptionFailed(
                "モデルのダウンロードは完了しましたが、ファイル構成が不正です: \(downloadedPath.path)"
            )
        }

        AppLogger.info("Downloaded model to \(downloadedPath.lastPathComponent)", logger: AppLogger.transcription)
        return downloadedPath
    }
}
