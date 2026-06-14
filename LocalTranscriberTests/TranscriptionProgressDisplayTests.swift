import XCTest
@testable import LocalTranscriber

final class TranscriptionProgressDisplayTests: XCTestCase {
    func testDownloadingModelShowsPercentDetail() {
        // Given: ダウンロード中 45%
        let update = TranscriptionProgressUpdate.make(
            phase: .downloadingModel,
            fraction: 0.45,
            modelDisplayName: "Base"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertEqual(display.style, .determinate)
        XCTAssertEqual(display.fraction, 0.45)
        XCTAssertEqual(display.primaryLabel, "モデルをダウンロード中…")
        XCTAssertEqual(display.detailLabel, "Base · 45%")
    }

    func testDownloadingModelShowsByteDetailWhenAvailable() {
        // Given: バイト進捗付き Progress
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 64

        let update = TranscriptionProgressUpdate.make(
            phase: .downloadingModel,
            fraction: 0.64,
            progress: progress,
            modelDisplayName: "Base"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertTrue(display.detailLabel?.contains("Base · ") == true)
        XCTAssertTrue(display.detailLabel?.contains("/") == true)
    }

    func testLoadingModelUsesIndeterminateStyle() {
        // Given: モデル読み込み中
        let update = TranscriptionProgressUpdate.make(
            phase: .loadingModel,
            fraction: 0,
            modelDisplayName: "Small"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertEqual(display.style, .indeterminate)
        XCTAssertNil(display.fraction)
        XCTAssertEqual(display.detailLabel, "Small")
    }

    func testTranscribingUsesDeterminateStyle() {
        // Given: 文字起こし 32%
        let update = TranscriptionProgressUpdate.make(
            phase: .transcribing,
            fraction: 0.32,
            modelDisplayName: "Base"
        )

        // When
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertEqual(display.style, .determinate)
        XCTAssertEqual(display.detailLabel, "32%")
    }

    func testAccessibilityLabelsForDownloadProgress() {
        // Given
        let update = TranscriptionProgressUpdate.make(
            phase: .downloadingModel,
            fraction: 0.45,
            modelDisplayName: "Base"
        )
        let display = TranscriptionProgressDisplay.from(update: update)

        // Then
        XCTAssertEqual(display.accessibilityLabel, "モデルをダウンロード中…、Base")
        XCTAssertEqual(display.accessibilityValue, "45パーセント完了")
    }
}
