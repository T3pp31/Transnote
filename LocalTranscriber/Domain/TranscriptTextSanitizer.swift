import Foundation

enum TranscriptTextSanitizer {
    private static let specialTokenPatterns = [
        #"<\|[^>|]*\|>"#,
        #"<｜[^>｜]*｜>"#,
    ]

    static func containsSpecialTokenArtifacts(_ text: String) -> Bool {
        if text.contains("<|") || text.contains("|>") || text.contains("<｜") || text.contains("｜>") {
            return true
        }
        return specialTokenPatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    static func sanitize(_ text: String) -> String {
        var result = text
        for pattern in specialTokenPatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        result = result
            .replacingOccurrences(of: "<\\|", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\|>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<｜", with: "", options: .regularExpression)
            .replacingOccurrences(of: "｜>", with: "", options: .regularExpression)

        return result
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func presentableText(from rawText: String) -> String? {
        let sanitized = sanitize(rawText)
        guard !sanitized.isEmpty, !containsSpecialTokenArtifacts(sanitized) else {
            return nil
        }
        return sanitized
    }
}
