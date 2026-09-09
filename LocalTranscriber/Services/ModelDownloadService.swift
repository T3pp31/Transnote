import Foundation
import WhisperKit

struct ModelDownloadService: Sendable {
    private let modelsRoot: URL
    private let modelAvailability: ModelAvailabilityService
    private let fileManager: FileManager

    init(
        modelsRoot: URL = AppDirectories.modelsDirectory,
        modelAvailability: ModelAvailabilityService? = nil,
        fileManager: FileManager = .default
    ) {
        self.modelsRoot = modelsRoot
        self.modelAvailability = modelAvailability ?? ModelAvailabilityService(modelsRoot: modelsRoot)
        self.fileManager = fileManager
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

        // WhisperKit.download は throw すると保存先 (modelsRoot) に途中生成されたフォルダが残る。
        // 「ダウンロード前に存在したフォルダ」を控えておき、失敗時は「今回新規に生成されたフォルダ」だけを
        // 削除する（既存モデルを誤って消さないためのセーフガード）。
        let directoriesBeforeDownload = Set(
            modelAvailability.variantDirectories(named: whisperKitModelName).map { $0.path }
        )

        do {
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
        } catch {
            cleanUpFailedDownload(
                whisperKitModelName: whisperKitModelName,
                directoriesBeforeDownload: directoriesBeforeDownload
            )
            throw error
        }
    }

    /// ダウンロード失敗時に、そのダウンロードが新規に生成した variant フォルダ（部分ダウンロード）を削除する。
    /// 削除対象は「事前に存在しなかった」フォルダのみで、既存モデルには影響しない。
    /// テスト容易性のため internal メソッドとして切り出している。
    func cleanUpFailedDownload(
        whisperKitModelName: String,
        directoriesBeforeDownload: Set<String>
    ) {
        for url in modelAvailability.variantDirectories(named: whisperKitModelName) {
            guard !directoriesBeforeDownload.contains(url.path) else { continue }
            AppLogger.info(
                "Removing incomplete model folder after failed download: \(url.lastPathComponent)",
                logger: AppLogger.transcription
            )
            try? fileManager.removeItem(at: url)
        }
    }
}
