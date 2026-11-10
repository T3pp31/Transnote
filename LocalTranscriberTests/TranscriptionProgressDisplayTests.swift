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
        XCTAssertEqual(display.primaryLabel, TranscriptionProgressPhase.downloadingModel.localizedDisplayName)
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
        XCTAssertTrue(display.detailLabel?.contains("Small") == true)
        XCTAssertTrue(display.detailLabel?.contains("時間がかかる") == true)
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

    func testLoadingModelIncludesGuidanceDetail() {
        let update = TranscriptionProgressUpdate.make(
            phase: .loadingModel,
            fraction: 0,
            modelDisplayName: "Base"
        )

        let display = TranscriptionProgressDisplay.from(update: update)

        XCTAssertEqual(display.style, .indeterminate)
        XCTAssertTrue(display.detailLabel?.contains("Base") == true)
        XCTAssertTrue(display.detailLabel?.contains("時間がかかる") == true)
    }

    func testTranscribingWithPartialTextIncludesPartialGuidance() {
        let update = TranscriptionProgressUpdate.make(
            phase: .transcribing,
            fraction: 0.5,
            partialText: "Hello"
        )

        let display = TranscriptionProgressDisplay.from(update: update)

        XCTAssertTrue(display.detailLabel?.contains("途中結果") == true)
        XCTAssertTrue(display.detailLabel?.contains("50%") == true)
    }

    func testProgressLabelsClampOutOfRangeFraction() {
        let update = TranscriptionProgressUpdate.make(
            phase: .downloadingModel,
            fraction: 1.2
        )
        let display = TranscriptionProgressDisplay.from(update: update)

        XCTAssertEqual(display.fraction, 1.0)
        XCTAssertEqual(display.detailLabel, "100%")
    }

    func testDownloadingModelNormalizesNonFiniteFractions() {
        let expectedValue = String(
            format: NSLocalizedString("%dパーセント完了", comment: "Accessible progress percentage"),
            0
        )

        for fraction in [Double.nan, .infinity, -.infinity] {
            let update = TranscriptionProgressUpdate.make(
                phase: .downloadingModel,
                fraction: fraction,
                modelDisplayName: "Base"
            )
            let display = TranscriptionProgressDisplay.from(update: update)

            XCTAssertEqual(display.style, .determinate, "fraction: \(fraction)")
            XCTAssertEqual(display.fraction, 0, "fraction: \(fraction)")
            XCTAssertEqual(display.detailLabel, "Base · 0%", "fraction: \(fraction)")
            XCTAssertEqual(display.accessibilityValue, expectedValue, "fraction: \(fraction)")
        }
    }

    func testTranscribingNormalizesPositiveInfiniteFraction() {
        let update = TranscriptionProgressUpdate.make(
            phase: .transcribing,
            fraction: .infinity
        )
        let display = TranscriptionProgressDisplay.from(update: update)
        let expectedValue = String(
            format: NSLocalizedString("%dパーセント完了", comment: "Accessible progress percentage"),
            0
        )

        XCTAssertEqual(display.style, .determinate)
        XCTAssertEqual(display.fraction, 0)
        XCTAssertNil(display.detailLabel)
        XCTAssertEqual(display.accessibilityValue, expectedValue)
    }

    func testTranscribingWithoutPositiveProgressRemainsIndeterminate() {
        for fraction in [Double.nan, -.infinity, -0.2, 0] {
            let update = TranscriptionProgressUpdate.make(
                phase: .transcribing,
                fraction: fraction
            )
            let display = TranscriptionProgressDisplay.from(update: update)

            XCTAssertEqual(display.style, .indeterminate, "fraction: \(fraction)")
            XCTAssertNil(display.fraction, "fraction: \(fraction)")
            XCTAssertNil(display.detailLabel, "fraction: \(fraction)")
            XCTAssertEqual(
                display.accessibilityValue,
                NSLocalizedString("進行中", comment: "Accessible indeterminate progress value"),
                "fraction: \(fraction)"
            )
        }
    }

    func testTranscribingClampsFiniteFractionAboveOne() {
        let update = TranscriptionProgressUpdate.make(
            phase: .transcribing,
            fraction: 1.2
        )
        let display = TranscriptionProgressDisplay.from(update: update)
        let expectedValue = String(
            format: NSLocalizedString("%dパーセント完了", comment: "Accessible progress percentage"),
            100
        )

        XCTAssertEqual(display.style, .determinate)
        XCTAssertEqual(display.fraction, 1)
        XCTAssertEqual(display.detailLabel, "100%")
        XCTAssertEqual(display.accessibilityValue, expectedValue)
    }

    func testIdleDisplayUsesWaitingLabel() {
        let display = TranscriptionProgressDisplay.idle()

        XCTAssertEqual(
            display.primaryLabel,
            NSLocalizedString("待機中", comment: "Idle state label")
        )
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
        let expectedLabel = String(
            format: NSLocalizedString("%@、%@", comment: "Progress label and model name"),
            TranscriptionProgressPhase.downloadingModel.localizedDisplayName,
            "Base"
        )
        let expectedValue = String(
            format: NSLocalizedString("%dパーセント完了", comment: "Accessible progress percentage"),
            45
        )
        XCTAssertEqual(display.accessibilityLabel, expectedLabel)
        XCTAssertEqual(display.accessibilityValue, expectedValue)
    }
}
