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
            modelAvailability.variantDirectories(
                named: whisperKitModelName,
                includingHidden: true
            ).map { $0.path }
        )

        // ネットワーク失敗時に指数バックオフで再試行する（最大3回、待機 1s / 2s / 4s）。
        let maxAttempts = 3
        var attempt = 0
        var lastError: Error?
        var downloadedPath: URL?
        while attempt < maxAttempts {
            attempt += 1
            do {
                downloadedPath = try await WhisperKit.download(
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
                break
            } catch {
                lastError = error
                // ネットワーク系エラーのみ再試行する
                guard isRetryableNetworkError(error), attempt < maxAttempts else {
                    throw error
                }
                let delaySeconds = UInt64(pow(2.0, Double(attempt - 1)))
                AppLogger.info("Download attempt \(attempt) failed; retrying in \(delaySeconds)s: \(error)", logger: AppLogger.transcription)
                try await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            }
        }

        guard let path = downloadedPath else {
            throw lastError ?? AppError.transcriptionFailed("モデルのダウンロードに失敗しました。")
        }
        guard modelAvailability.validateModelFolder(path) else {
            throw AppError.transcriptionFailed(
                "モデルのダウンロードは完了しましたが、ファイル構成が不正です: \(path.path)"
            )
        }

        AppLogger.info("Downloaded model to \(path.lastPathComponent)", logger: AppLogger.transcription)
        return path
    }

    /// 再試行すべきネットワーク系エラーかどうかを判定する。
    private func isRetryableNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .dnsLookupFailed, .resourceUnavailable,
                 .cannotFindHost:
                return true
            default:
                return false
            }
        }
        // WhisperKit が投げる汎用エラーのうち、ネットワーク系の文言のみ再試行する
        let description = (error as NSError).localizedDescription.lowercased()
        return description.contains("network")
            || description.contains("connection")
            || description.contains("timeout")
    }

    /// ダウンロード失敗時に、そのダウンロードが新規に生成した variant フォルダ（部分ダウンロード）を削除する。
    /// 削除対象は「事前に存在しなかった」フォルダのみで、既存モデルには影響しない。
    /// テスト容易性のため internal メソッドとして切り出している。
    func cleanUpFailedDownload(
        whisperKitModelName: String,
        directoriesBeforeDownload: Set<String>
    ) {
        for url in modelAvailability.variantDirectories(
            named: whisperKitModelName,
            includingHidden: true
        ) {
            guard !directoriesBeforeDownload.contains(url.path) else { continue }
            AppLogger.info(
                "Removing incomplete model folder after failed download: \(url.lastPathComponent)",
                logger: AppLogger.transcription
            )
            try? fileManager.removeItem(at: url)
        }
    }
}
