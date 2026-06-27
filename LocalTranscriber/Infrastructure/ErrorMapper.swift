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

    var errorDescription: String? {
        ErrorMapper.userMessage(for: self)
    }
}

enum ErrorMapper {
    static func userMessage(for error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .unsupportedFileExtension(let ext):
                return "未対応のファイル形式です: \(ext)。wav / mp3 / m4a / flac に対応しています。"
            case .fileNotFound:
                return "選択したファイルが見つかりません。"
            case .fileAccessDenied:
                return "ファイルへのアクセスが拒否されました。もう一度ファイルを選択してください。"
            case .transcriptionCancelled:
                return "文字起こしをキャンセルしました。"
            case .transcriptionFailed(let message):
                return message
            case .exportFailed(let message):
                return "エクスポートに失敗しました: \(message)"
            case .invalidConfiguration:
                return "アプリ設定が不正です。"
            case .bookmarkResolutionFailed:
                return "保存済みファイルへのアクセスを復元できませんでした。"
            case .modelNotDownloaded(let modelName):
                return "モデル「\(modelName)」がダウンロードされていません。ツールバーの「Download」ボタンからダウンロードしてください。"
            }
        }

        if error is CancellationError {
            return "処理がキャンセルされました。"
        }

        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("Model file not found")
            || description.localizedCaseInsensitiveContains("Models are unavailable")
            || description.localizedCaseInsensitiveContains("Model not found") {
            return "モデルの読み込みに失敗しました。モデル管理から再ダウンロードしてください。"
        }

        if description.localizedCaseInsensitiveContains("network")
            || description.localizedCaseInsensitiveContains("Internet")
            || description.localizedCaseInsensitiveContains("offline") {
            return "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。"
        }

        AppLogger.error("Unknown error: \(error)")
        return "予期しないエラーが発生しました。もう一度お試しください。"
    }
}
