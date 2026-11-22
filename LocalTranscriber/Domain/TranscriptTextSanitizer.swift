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
        // 完全な特殊トークンも必ずこれらの区切りを含むため、正規表現での再走査は不要。
        // 結合文字が隣接しても正規表現と同じ区切りを検出できるよう、リテラル検索する。
        text.range(of: "<|", options: .literal) != nil
            || text.range(of: "|>", options: .literal) != nil
            || text.range(of: "<｜", options: .literal) != nil
            || text.range(of: "｜>", options: .literal) != nil
    }

    static func sanitize(_ text: String) -> String {
        var result = text
        // すべての除去パターンは区切りトークンを含むため、含まない clean テキストでは正規表現を実行しない。
        if containsSpecialTokenArtifacts(result) {
            for expression in removalExpressions {
                result = expression.stringByReplacingMatches(
                    in: result,
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: ""
                )
            }
        }

        if result.range(of: "  ", options: .literal) != nil {
            result = repeatedSpacesExpression.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: " "
            )
        }

        guard let first = result.unicodeScalars.first, let last = result.unicodeScalars.last else {
            return result
        }
        if CharacterSet.whitespacesAndNewlines.contains(first)
            || CharacterSet.whitespacesAndNewlines.contains(last) {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func presentableText(from rawText: String) -> String? {
        let sanitized = sanitize(rawText)
        // 除去によって区切りが新たに隣接する場合（例: <<|| → <|）があるため、残骸の確認は必要。
        guard !sanitized.isEmpty, !containsSpecialTokenArtifacts(sanitized) else {
            return nil
        }
        return sanitized
    }
}
