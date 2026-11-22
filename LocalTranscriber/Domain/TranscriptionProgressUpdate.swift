import Foundation

struct TranscriptionProgressUpdate: Sendable, Equatable {
    let phase: TranscriptionProgressPhase
    let fraction: Double
    let completedUnitCount: Int64?
    let totalUnitCount: Int64?
    let modelDisplayName: String?
    let partialText: String?
    let resumeState: String?
    /// `partialText` がすでに `TranscriptPartialTextBuilder` 等でサニタイズ済みなら true。
    /// 累積部分テキストの毎更新 O(N^2) 正規表現再走査を避けるために使用する。
    let isPartialTextSanitized: Bool

    init(
        phase: TranscriptionProgressPhase,
        fraction: Double,
        completedUnitCount: Int64?,
        totalUnitCount: Int64?,
        modelDisplayName: String?,
        partialText: String?,
        resumeState: String?,
        isPartialTextSanitized: Bool = false
    ) {
        self.phase = phase
        self.fraction = fraction
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.modelDisplayName = modelDisplayName
        self.partialText = partialText
        self.resumeState = resumeState
        self.isPartialTextSanitized = isPartialTextSanitized
    }

    static func make(
        phase: TranscriptionProgressPhase,
        fraction: Double,
        progress: Progress? = nil,
        modelDisplayName: String? = nil,
        partialText: String? = nil,
        resumeState: String? = nil,
        isPartialTextSanitized: Bool = false
    ) -> TranscriptionProgressUpdate {
        let completed = progress.map { $0.completedUnitCount }
        let total = progress.map { $0.totalUnitCount }
        let hasByteProgress = (total ?? 0) > 0

        return TranscriptionProgressUpdate(
            phase: phase,
            fraction: fraction,
            completedUnitCount: hasByteProgress ? completed : nil,
            totalUnitCount: hasByteProgress ? total : nil,
            modelDisplayName: modelDisplayName,
            partialText: partialText,
            resumeState: resumeState,
            isPartialTextSanitized: isPartialTextSanitized
        )
    }
}
