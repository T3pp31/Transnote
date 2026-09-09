import Foundation

enum AppError: LocalizedError, Equatable {
    case unsupportedFileExtension(String)
    case fileNotFound
    case fileAccessDenied
    case transcriptionCancelled
    case transcriptionFailed(String)
    case transcriptionFailedWithReason(Error)
    case exportFailed(String)
    case exportFailedWithReason(Error)
    case invalidConfiguration
    case bookmarkResolutionFailed
    case modelNotDownloaded(String)
    case fileTooLarge

    var errorDescription: String? {
        ErrorMapper.userMessage(for: self)
    }

    // Error は Equatable に適合しないため、手動で同値比較を実装する。
    // 元エラー保持ケース（*WithReason）は NSError にブリッジして同値比較する。
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.unsupportedFileExtension(let l), .unsupportedFileExtension(let r)):
            return l == r
        case (.fileNotFound, .fileNotFound), (.fileAccessDenied, .fileAccessDenied),
             (.transcriptionCancelled, .transcriptionCancelled):
            return true
        case (.transcriptionFailed(let l), .transcriptionFailed(let r)):
            return l == r
        case (.transcriptionFailedWithReason(let l), .transcriptionFailedWithReason(let r)):
            return (l as NSError).isEqual(r as NSError)
        case (.exportFailed(let l), .exportFailed(let r)):
            return l == r
        case (.exportFailedWithReason(let l), .exportFailedWithReason(let r)):
            return (l as NSError).isEqual(r as NSError)
        case (.invalidConfiguration, .invalidConfiguration),
             (.bookmarkResolutionFailed, .bookmarkResolutionFailed),
             (.fileTooLarge, .fileTooLarge):
            return true
        case (.modelNotDownloaded(let l), .modelNotDownloaded(let r)):
            return l == r
        default:
            return false
        }
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
            case .transcriptionFailedWithReason(let error):
                return ErrorMapper.userMessage(for: error)
            case .exportFailed(let message):
                return String(
                    format: NSLocalizedString("エクスポートに失敗しました: %@", comment: "Export failed"),
                    message
                )
            case .exportFailedWithReason(let error):
                return String(
                    format: NSLocalizedString("エクスポートに失敗しました: %@", comment: "Export failed"),
                    ErrorMapper.userMessage(for: error)
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
                        "モデル「%@」がダウンロードされていません。ツールバーの「モデルをダウンロード」ボタンからダウンロードしてください。",
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

        // URLError は型ベースで分類する（部分文字列一致による誤分類を防ぐ）
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return NSLocalizedString("処理がキャンセルされました。", comment: "Operation cancelled")
            }
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .timedOut, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .resourceUnavailable:
                return NSLocalizedString(
                    "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。",
                    comment: "Model download network failure"
                )
            default:
                break
            }
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

        // WhisperKit 由来のエラーは型不明のことが多いため、
        // 部分文字列一致による誤分類を避けるべく、
        // より具体的・長いフレーズに限定して判定する
        let lowercasedDescription = description.lowercased()
        if lowercasedDescription.contains("network connection")
            || lowercasedDescription.contains("network error") {
            return NSLocalizedString(
                "モデルのダウンロードに失敗しました。ネットワーク接続を確認してください。",
                comment: "Model download network failure"
            )
        }

        return NSLocalizedString(
            "予期しないエラーが発生しました。もう一度お試しください。",
            comment: "Unexpected error"
        )
    }
}
