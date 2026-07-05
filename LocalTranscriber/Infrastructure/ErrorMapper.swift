import Foundation

enum AppError: LocalizedError, Equatable {
    case unsupportedFileExtension(String)
    case fileNotFound
    case fileAccessDenied
    case transcriptionCancelled
    case transcriptionFailed(String)
    case exportFailed(String)
    case invalidConfiguration
    case bookmarkResolutionFailed
    case modelNotDownloaded(String)
    case fileTooLarge

    var errorDescription: String? {
        ErrorMapper.userMessage(for: self)
    }
}

enum ErrorMapper {
    static func userMessage(for error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .unsupportedFileExtension(let ext):
                return String(
                    format: NSLocalizedString(
                        "未対応のファイル形式です: %@。wav / mp3 / m4a / flac に対応しています。",
                        comment: "Unsupported audio file extension"
                    ),
                    ext
                )
            case .fileNotFound:
                return NSLocalizedString("選択したファイルが見つかりません。", comment: "File not found")
            case .fileAccessDenied:
                return NSLocalizedString(
                    "ファイルへのアクセスが拒否されました。もう一度ファイルを選択してください。",
                    comment: "File access denied"
                )
            case .transcriptionCancelled:
                return NSLocalizedString("文字起こしをキャンセルしました。", comment: "Transcription cancelled")
            case .transcriptionFailed(let message):
                return message
            case .exportFailed(let message):
                return String(
                    format: NSLocalizedString("エクスポートに失敗しました: %@", comment: "Export failed"),
                    message
                )
            case .invalidConfiguration:
                return NSLocalizedString("アプリ設定が不正です。", comment: "Invalid configuration")
            case .bookmarkResolutionFailed:
                return NSLocalizedString(
                    "保存済みファイルへのアクセスを復元できませんでした。",
                    comment: "Bookmark resolution failed"
                )
            case .modelNotDownloaded(let modelName):
                return String(
                    format: NSLocalizedString(
                        "モデル「%@」がダウンロードされていません。ツールバーの「ダウンロード」ボタンからダウンロードしてください。",
                        comment: "Model not downloaded"
                    ),
                    modelName
                )
            case .fileTooLarge:
                return NSLocalizedString(
                    "ファイルサイズが上限（500MB）を超えています。より小さいファイルを選択してください。",
                    comment: "Audio file exceeds size limit"
                )
            }
        }

        if error is CancellationError {
            return NSLocalizedString("処理がキャンセルされました。", comment: "Operation cancelled")
        }

        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("Model file not found")
            || description.localizedCaseInsensitiveContains("Models are unavailable")
            || description.localizedCaseInsensitiveContains("Model not found") {
            return NSLocalizedString(
                "モデルの読み込みに失敗しました。モデル管理から再ダウンロードしてください。",
                comment: "Model loading failed"
            )
        }

        if description.localizedCaseInsensitiveContains("network")
            || description.localizedCaseInsensitiveContains("Internet")
            || description.localizedCaseInsensitiveContains("offline") {
            return NSLocalizedString(
                "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。",
                comment: "Model download network failure"
            )
        }

        AppLogger.error("Unknown error: \(error)")
        return NSLocalizedString(
            "予期しないエラーが発生しました。もう一度お試しください。",
            comment: "Unexpected error"
        )
    }
}
