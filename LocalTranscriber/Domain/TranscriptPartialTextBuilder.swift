import Foundation

enum TranscriptPartialTextBuilder {
    static func joinedPresentableText(from segmentTexts: [String]) -> String {
        segmentTexts
            .compactMap(TranscriptTextSanitizer.presentableText(from:))
            .joined(separator: " ")
    }

    static func appendPresentableWindowText(
        from segmentTexts: [String],
        to accumulated: inout [String]
    ) -> String? {
        let windowText = joinedPresentableText(from: segmentTexts)
        guard !windowText.isEmpty else { return nil }

        accumulated.append(windowText)
        let partialText = accumulated.joined(separator: " ")
        return TranscriptTextSanitizer.presentableText(from: partialText)
    }
}
