import Foundation

enum TranscriptPartialTextBuilder {
    static func joinedPresentableText(from segmentTexts: [String]) -> String {
        segmentTexts
            .compactMap(TranscriptTextSanitizer.presentableText(from:))
            .joined(separator: " ")
    }

    /// 新規ウィンドウのテキストを累積テキストにインクリメンタルに結合して返す。
    ///
    /// `joinedPresentableText` はウィンドウ内で `presentableText`（サニタイズ済み・特殊トークン残骸なし）
    /// のみを選択するため、各ウィンドウは「クリーンなテキスト」として扱える。ウィンドウ間は常に単一の
    /// 空白で結合されるため、累積テキスト全体を再サニタイズする O(N^2 x 正規表現) コストが不要になる。
    /// 従来実装との挙動同一は差分テスト（TranscriptPartialTextBuilderTests）が保証する。
    static func appendPresentableWindowText(
        from segmentTexts: [String],
        to accumulated: inout String
    ) -> String? {
        let windowText = joinedPresentableText(from: segmentTexts)
        guard !windowText.isEmpty else { return nil }

        accumulated = accumulated.isEmpty ? windowText : accumulated + " " + windowText
        return accumulated
    }
}
