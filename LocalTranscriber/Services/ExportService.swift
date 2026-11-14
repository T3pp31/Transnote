import Foundation

struct ExportService {
    func content(for transcript: Transcript, format: ExportFormat) throws -> String {
        try validateSegments(transcript.segments)
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
            throw AppError.exportFailedWithReason(error)
        }
    }

    /// 字幕 segment の開始・終了順、重なり、範囲を検証する。
    /// - 負の値・NaN・start > end は不正
    /// - 前の segment の end が次の start より大きい（重なり）は不正
    /// 不正があった場合、エクスポートを中断してユーザーへ通知する。
    private func validateSegments(_ segments: [TranscriptSegment]) throws {
        var previousEnd: TimeInterval?
        for segment in segments {
            guard segment.startTime.isFinite,
                  segment.endTime.isFinite,
                  segment.startTime >= 0,
                  segment.endTime >= 0 else {
                throw AppError.exportFailed("字幕の時間情報が不正です（負の値または非数値）。")
            }
            guard segment.endTime > segment.startTime else {
                throw AppError.exportFailed("字幕の開始時刻が終了時刻より後になっています。")
            }
            let maximumSeconds = Double(Int.max / 1_000_000)
            guard segment.startTime <= maximumSeconds,
                  segment.endTime <= maximumSeconds else {
                throw AppError.exportFailed("字幕の時間情報が不正です（範囲外の値）。")
            }
            if let previousEnd, segment.startTime < previousEnd {
                throw AppError.exportFailed("字幕セグメントが重なっています。")
            }
            previousEnd = segment.endTime
        }
    }

    private func exportTXT(_ transcript: Transcript) -> String {
        transcript.fullText
    }

    private func exportMarkdown(_ transcript: Transcript) -> String {
        var lines: [String] = []
        lines.append("# Transcript: \(escapeMarkdown(transcript.sourceFileName))")
        lines.append("")
        if let language = transcript.language {
            lines.append("Language: \(escapeMarkdown(language))")
            lines.append("")
        }
        lines.append("## Full Text")
        lines.append("")
        // 全文の Markdown 書式は維持し、生 HTML のみテキストとして扱う。
        lines.append(escapeMarkdownHTML(transcript.fullText))
        lines.append("")
        lines.append("## Segments")
        lines.append("")

        for segment in transcript.segments {
            let start = formatTimestamp(segment.startTime, separator: ".")
            let end = formatTimestamp(segment.endTime, separator: ".")
            // 続き行が別のリスト・引用・コードブロックを開始しないよう、本文を 1 行に収める。
            let text = segment.text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            lines.append("- [\(start) --> \(end)] \(escapeMarkdown(text))")
        }

        return lines.joined(separator: "\n")
    }

    /// Markdown の見出し・リスト・リンクを壊さないよう、
    /// ファイル名・言語・セグメントテキストに含まれる特殊文字と生 HTML をエスケープする。
    private func escapeMarkdown(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "`", with: "\\`")
        // 生成する文字参照の # を Markdown エスケープしないよう、HTML は最後に処理する。
        return escapeHTML(escaped)
    }

    /// コード内では HTML 実体参照も文字どおり表示されるため、元のソースを保持する。
    private func escapeMarkdownHTML(_ text: String) -> String {
        // Foundation はコード内の改行を LF として位置を報告する。解析用だけ正規化し、
        // 出力には元の改行とコードを使用する。
        let source = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let parsed = try? AttributedString(
            markdown: source, options: .init(appliesSourcePositionAttributes: true)
        ) else { return escapeHTML(text) }

        var removedCarriageReturns = IndexSet()
        var offset = 0
        var previousWasCR = false
        for byte in text.utf8 {
            if byte == 10 && previousWasCR {
                removedCarriageReturns.insert(offset - 1)
            } else {
                offset += 1
            }
            previousWasCR = byte == 13
        }
        func originalIndex(_ index: String.Index) -> String.Index {
            let offset = source.utf8.distance(from: source.startIndex, to: index)
            let originalOffset = offset + removedCarriageReturns.count(in: 0..<offset)
            return text.utf8.index(text.startIndex, offsetBy: originalOffset)
        }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let codeRanges = parsed.runs.compactMap { run -> Range<String.Index>? in
            let isCodeBlock = run.presentationIntent?.components.contains {
                if case .codeBlock = $0.kind { return true }
                return false
            } == true
            guard isCodeBlock || run.inlinePresentationIntent?.contains(.code) == true,
                  let position = run.markdownSourcePosition else { return nil }
            guard let range = markdownSourceRange(position, in: source, lines: lines) else { return nil }
            // 引用・リスト内のフェンスでは、開始行のコンテナ記号も保持する。
            let start = isCodeBlock ? lines[position.startLine - 1].startIndex : range.lowerBound
            return originalIndex(start)..<originalIndex(range.upperBound)
        }.sorted { $0.lowerBound < $1.lowerBound }

        var result = ""
        var cursor = text.startIndex
        for range in codeRanges where range.lowerBound >= cursor {
            result += escapeHTML(String(text[cursor..<range.lowerBound]))
            result += text[range]
            cursor = range.upperBound
        }
        result += escapeHTML(String(text[cursor...]))
        return result
    }

    private func markdownSourceRange(
        _ position: AttributedString.MarkdownSourcePosition, in text: String, lines: [Substring]
    ) -> Range<String.Index>? {
        if let range = Range(position, in: text) { return range }
        // インデント付きブロックは末尾の空行を column 0 として報告する場合がある。
        guard position.endColumn == 0,
              position.startLine > 0, position.startLine <= lines.count,
              position.endLine > 0, position.endLine <= lines.count,
              position.startColumn > 0 else { return nil }
        let line = lines[position.startLine - 1]
        guard let offset = line.utf8.index(
            line.utf8.startIndex, offsetBy: position.startColumn - 1, limitedBy: line.utf8.endIndex
        ), let start = String.Index(offset, within: text) else { return nil }
        let end = lines[position.endLine - 1].startIndex
        return start <= end ? start..<end : nil
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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
            ? [fallbackSegment(for: transcript)]
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
            ? [fallbackSegment(for: transcript)]
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

    /// segment が無い場合の字幕用フォールバック。
    /// 00:00:00 -> 00:00:00 の無効な区間ではなく、テキスト全体を
    /// 0 秒からざっくり 1 秒の区間として表示する（実時間が不明なため）。
    private func fallbackSegment(for transcript: Transcript) -> TranscriptSegment {
        TranscriptSegment(startTime: 0, endTime: 1, text: transcript.fullText)
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
