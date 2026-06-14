import Foundation

struct ExportService {
    func content(for transcript: Transcript, format: ExportFormat) throws -> String {
        switch format {
        case .txt:
            return exportTXT(transcript)
        case .markdown:
            return exportMarkdown(transcript)
        case .json:
            return try exportJSON(transcript)
        case .srt:
            return exportSRT(transcript)
        case .vtt:
            return exportVTT(transcript)
        }
    }

    func write(transcript: Transcript, format: ExportFormat, to url: URL) throws {
        let text = try content(for: transcript, format: format)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.exportFailed(ErrorMapper.userMessage(for: error))
        }
    }

    private func exportTXT(_ transcript: Transcript) -> String {
        transcript.fullText
    }

    private func exportMarkdown(_ transcript: Transcript) -> String {
        var lines: [String] = []
        lines.append("# Transcript: \(transcript.sourceFileName)")
        lines.append("")
        if let language = transcript.language {
            lines.append("Language: \(language)")
            lines.append("")
        }
        lines.append("## Full Text")
        lines.append("")
        lines.append(transcript.fullText)
        lines.append("")
        lines.append("## Segments")
        lines.append("")

        for segment in transcript.segments {
            let start = formatTimestamp(segment.startTime, separator: ".")
            let end = formatTimestamp(segment.endTime, separator: ".")
            lines.append("- [\(start) --> \(end)] \(segment.text)")
        }

        return lines.joined(separator: "\n")
    }

    private func exportJSON(_ transcript: Transcript) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AppError.exportFailed("Failed to encode JSON as UTF-8.")
        }
        return string
    }

    private func exportSRT(_ transcript: Transcript) -> String {
        var blocks: [String] = []
        let segments = transcript.segments.isEmpty
            ? [TranscriptSegment(startTime: 0, endTime: 0, text: transcript.fullText)]
            : transcript.segments

        for (index, segment) in segments.enumerated() {
            let start = formatTimestamp(segment.startTime, separator: ",")
            let end = formatTimestamp(segment.endTime, separator: ",")
            blocks.append("\(index + 1)")
            blocks.append("\(start) --> \(end)")
            blocks.append(segment.text)
            blocks.append("")
        }

        return blocks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func exportVTT(_ transcript: Transcript) -> String {
        var lines = ["WEBVTT", ""]
        let segments = transcript.segments.isEmpty
            ? [TranscriptSegment(startTime: 0, endTime: 0, text: transcript.fullText)]
            : transcript.segments

        for segment in segments {
            let start = formatTimestamp(segment.startTime, separator: ".")
            let end = formatTimestamp(segment.endTime, separator: ".")
            lines.append("\(start) --> \(end)")
            lines.append(segment.text)
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatTimestamp(_ time: TimeInterval, separator: String) -> String {
        let totalMilliseconds = max(0, Int(time * 1000))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d\(separator)%03d", hours, minutes, seconds, milliseconds)
    }
}
