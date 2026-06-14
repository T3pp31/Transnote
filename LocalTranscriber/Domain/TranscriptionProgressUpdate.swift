import Foundation

struct TranscriptionProgressUpdate: Sendable, Equatable {
    let phase: TranscriptionProgressPhase
    let fraction: Double
    let completedUnitCount: Int64?
    let totalUnitCount: Int64?
    let modelDisplayName: String?

    static func make(
        phase: TranscriptionProgressPhase,
        fraction: Double,
        progress: Progress? = nil,
        modelDisplayName: String? = nil
    ) -> TranscriptionProgressUpdate {
        let completed = progress.map { $0.completedUnitCount }
        let total = progress.map { $0.totalUnitCount }
        let hasByteProgress = (total ?? 0) > 0

        return TranscriptionProgressUpdate(
            phase: phase,
            fraction: fraction,
            completedUnitCount: hasByteProgress ? completed : nil,
            totalUnitCount: hasByteProgress ? total : nil,
            modelDisplayName: modelDisplayName
        )
    }
}
