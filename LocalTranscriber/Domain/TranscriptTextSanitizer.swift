import Foundation

enum TranscriptTextSanitizer {
    // 固定パターンは一度だけコンパイルし、進捗更新ごとに再生成しない。
    private static let specialTokenExpressions = [
        #"<\|[^>|]*\|>"#,
        #"<｜[^>｜]*｜>"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let removalExpressions = specialTokenExpressions + [
        #"<\|"#,
        #"\|>"#,
        "<｜",
        "｜>",
    ].map { try! NSRegularExpression(pattern: $0) }

    private static let repeatedSpacesExpression = try! NSRegularExpression(pattern: " +")

    static func containsSpecialTokenArtifacts(_ text: String) -> Bool {
        if text.contains("<|") || text.contains("|>") || text.contains("<｜") || text.contains("｜>") {
            return true
        }
        return specialTokenExpressions.contains { expression in
            expression.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil
        }
    }

    static func sanitize(_ text: String) -> String {
        var result = text
        for expression in removalExpressions {
            result = expression.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: ""
            )
        }

        return repeatedSpacesExpression.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: result.utf16.count),
            withTemplate: " "
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func presentableText(from rawText: String) -> String? {
        let sanitized = sanitize(rawText)
        guard !sanitized.isEmpty, !containsSpecialTokenArtifacts(sanitized) else {
            return nil
        }
        return sanitized
    }
}
