import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case txt
    case markdown
    case json
    case srt
    case vtt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .txt: return "TXT"
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .srt: return "SRT"
        case .vtt: return "VTT"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        default: return rawValue
        }
    }
}

enum TranscriptionUIState: Equatable, Sendable {
    case idle
    case preparing
    case transcribing
    case done
    case error(String)
}

enum TranscriptionProgressPhase: String, Sendable {
    case initializing = "準備中…"
    case loadingModel = "モデルを読み込み中…"
    case downloadingModel = "モデルをダウンロード中…"
    case convertingAudio = "音声を変換中…"
    case transcribing = "文字起こし中…"
    case finished = "完了"
}
