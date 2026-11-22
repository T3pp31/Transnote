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
        let completedText = ByteCountFormatter.string(fromByteCount: 64, countStyle: .file)
        let totalText = ByteCountFormatter.string(fromByteCount: 100, countStyle: .file)
        XCTAssertEqual(display.detailLabel, "Base · \(completedText) / \(totalText)")
    }

    func testDownloadingModelByteDetailUsesFileStyleAcrossRepeatedUpdates() {
        let counts: [(completed: Int64, total: Int64)] = [
            (0, 100), (64, 100), (1_500, 3_000),
            (1_500_000, 3_000_000), (3_000_000_000, 5_000_000_000),
        ]
        let contexts: [(model: String?, resume: String?, prefix: String)] = [
            (nil, nil, ""), ("Base", nil, "Base"), (nil, "Resuming", "Resuming"),
            ("Base", "Resuming", "Base · Resuming"),
        ]

        for _ in 0..<3 {
            for (completed, total) in counts {
                for (model, resume, prefix) in contexts {
                    let progress = Progress(totalUnitCount: total)
                    progress.completedUnitCount = completed
                    let fraction = Double(completed) / Double(total)
                    let update = TranscriptionProgressUpdate.make(
                        phase: .downloadingModel,
                        fraction: fraction,
                        progress: progress,
                        modelDisplayName: model,
                        resumeState: resume
                    )

                    let display = TranscriptionProgressDisplay.from(update: update)
                    let completedText = ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)
                    let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                    let bytes = "\(completedText) / \(totalText)"
                    XCTAssertEqual(display.detailLabel, prefix.isEmpty ? bytes : "\(prefix) · \(bytes)")
                    XCTAssertEqual(display.style, .determinate)
                    XCTAssertEqual(display.fraction, fraction)
                }
            }
        }
    }

    func testDownloadingModelByteDetailSupportsConcurrentUpdates() {
        let updates = (0..<64).map { index in
            TranscriptionProgressUpdate(
                phase: .downloadingModel,
                fraction: Double(index) / 64,
                completedUnitCount: Int64(index) * 100_000,
                totalUnitCount: 6_400_000,
                modelDisplayName: "Model \(index)",
                partialText: nil,
                resumeState: nil
            )
        }
        // 期待値は共有フォーマッタを使わず、並行処理の開始前に生成する。
        let expectedDetails = updates.indices.map { index in
            let completedText = ByteCountFormatter.string(fromByteCount: Int64(index) * 100_000, countStyle: .file)
            let totalText = ByteCountFormatter.string(fromByteCount: 6_400_000, countStyle: .file)
            return "Model \(index) · \(completedText) / \(totalText)"
        }

        DispatchQueue.concurrentPerform(iterations: updates.count) { index in
            let display = TranscriptionProgressDisplay.from(update: updates[index])
            XCTAssertEqual(display.detailLabel, expectedDetails[index])
        }
    }

    func testDownloadingModelFallsBackToPercentWhenByteCountsAreUnavailable() {
        let counts: [(completed: Int64?, total: Int64?)] = [
            (nil, nil), (64, nil), (nil, 100), (64, 0), (64, -100),
        ]

        for (completed, total) in counts {
            let update = TranscriptionProgressUpdate(
                phase: .downloadingModel,
                fraction: 0.45,
                completedUnitCount: completed,
                totalUnitCount: total,
                modelDisplayName: "Base",
                partialText: nil,
                resumeState: "Resuming"
            )

            let display = TranscriptionProgressDisplay.from(update: update)
            XCTAssertEqual(display.detailLabel, "Base · Resuming · 45%")
            XCTAssertEqual(display.style, .determinate)
            XCTAssertEqual(display.fraction, 0.45)
        }
    }

    func testLoadingModelUsesIndeterminateStyle() {
        let guidance = L("初回のモデル読み込みは時間がかかることがあります", comment: "Loading model indeterminate progress guidance")
        for modelName in ["Small", "Base"] {
            // Given: モデル読み込み中
            let update = TranscriptionProgressUpdate.make(
                phase: .loadingModel,
                fraction: 0,
                modelDisplayName: modelName
            )

            // When
            let display = TranscriptionProgressDisplay.from(update: update)

            // Then
            XCTAssertEqual(display.style, .indeterminate, modelName)
            XCTAssertNil(display.fraction, modelName)
            XCTAssertTrue(display.detailLabel?.contains(modelName) == true, modelName)
            XCTAssertTrue(display.detailLabel?.contains(guidance) == true, modelName)
        }
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

    func testTranscribingWithPartialTextIncludesPartialGuidance() {
        let update = TranscriptionProgressUpdate.make(
            phase: .transcribing,
            fraction: 0.5,
            partialText: "Hello"
        )

        let display = TranscriptionProgressDisplay.from(update: update)

        XCTAssertTrue(
            display.detailLabel?.contains(
                L("途中結果を表示中", comment: "Partial transcription guidance")
            ) == true
        )
        XCTAssertTrue(display.detailLabel?.contains("50%") == true)
    }

    func testPartialGuidanceUsesPresentableTextRatherThanRawNonemptyText() {
        let cases: [(raw: String?, presentable: String?)] = [
            (nil, nil),
            ("", nil),
            (" \t\n ", nil),
            ("<|startoftranscript|><|endoftext|>", nil),
            ("<｜nocaptions｜>", nil),
            ("<| |> <｜ ｜>", nil),
            ("<|ja|> こんにちは 🌏 <｜endoftext｜>", "こんにちは 🌏"),
        ]
        let guidance = L("途中結果を表示中", comment: "Partial transcription guidance")

        for (raw, presentable) in cases {
            for fraction in [0.0, 0.5] {
                let display = TranscriptionProgressDisplay.from(
                    update: .make(
                        phase: .transcribing,
                        fraction: fraction,
                        partialText: raw
                    ))
                let percent = Int(fraction * 100)
                let expectedDetail: String?
                if presentable != nil {
                    expectedDetail = percent > 0 ? "\(guidance) · \(percent)%" : guidance
                } else {
                    expectedDetail = percent > 0 ? "\(percent)%" : nil
                }

                XCTAssertEqual(display.presentablePartialText, presentable, "raw: \(String(describing: raw))")
                XCTAssertEqual(display.detailLabel, expectedDetail, "raw: \(String(describing: raw))")
            }
        }
    }

    func testPartialTextRemainsAvailableOutsideTranscribingPhase() {
        let display = TranscriptionProgressDisplay.from(
            update: .make(
                phase: .convertingAudio,
                fraction: 0,
                partialText: "<|ja|>こんにちは"
            ))

        XCTAssertEqual(display.presentablePartialText, "こんにちは")
        XCTAssertNil(TranscriptionProgressDisplay.idle().presentablePartialText)
        XCTAssertNil(TranscriptionProgressDisplay.done().presentablePartialText)
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

        for fraction in [Double.nan, Double.infinity, -Double.infinity] {
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
        for fraction in [Double.nan, -Double.infinity, -0.2, 0] {
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

    func testProgressDetailKeysExistInEnglishLocalization() {
        let appBundle = Bundle(for: MainWindowViewModel.self)
        guard let englishPath = appBundle.path(forResource: "en", ofType: "lproj")
        else {
            XCTFail("en.lproj を読み込めないこと")
            return
        }
        guard let englishBundle = Bundle(path: englishPath) else {
            XCTFail("en.lproj を読み込めないこと")
            return
        }

        // 英語値を明示し、別キーの訳のコピペや未翻訳の値を検出する。
        let expected: [(key: String, english: String)] = [
            ("初回のモデル読み込みは時間がかかることがあります", "The first model load may take some time"),
            ("音声を読み込んでいます（モデルの前処理）", "Loading audio (model preprocessing)"),
            ("文字起こしの準備をしています。", "Preparing transcription."),
            ("途中結果を表示中", "Showing partial results"),
            (
                "複数ファイルのドロップには対応していません。1つの音声ファイルをドロップしてください。",
                "Dropping multiple files is not supported. Drop a single audio file."
            ),
            ("対応している音声ファイルを読み込めませんでした。", "Could not load a supported audio file."),
        ]
        for (key, english) in expected {
            let value = NSLocalizedString(key, bundle: englishBundle, comment: "")
            XCTAssertEqual(value, english, "\(key) に正しい英語訳が登録されていること")
        }
    }

    func testTranscribingAccessibilityLabelDoesNotUsePercentOrGuidanceAsModelName() {
        let percentOnly = TranscriptionProgressDisplay.from(
            update: .make(phase: .transcribing, fraction: 0.32)
        )
        XCTAssertEqual(
            percentOnly.accessibilityLabel,
            TranscriptionProgressPhase.transcribing.localizedDisplayName,
            "進捗率のみの詳細をモデル名として連結しないこと"
        )

        let partialGuidance = TranscriptionProgressDisplay.from(
            update: .make(phase: .transcribing, fraction: 0.5, partialText: "hello")
        )
        XCTAssertEqual(
            partialGuidance.accessibilityLabel,
            TranscriptionProgressPhase.transcribing.localizedDisplayName,
            "案内文をモデル名として連結しないこと"
        )
    }

    func testTranscribingAccessibilityLabelIncludesModelNameWhenProvided() {
        let display = TranscriptionProgressDisplay.from(
            update: .make(phase: .transcribing, fraction: 0.32, modelDisplayName: "Base")
        )
        let expectedLabel = String(
            format: NSLocalizedString("%@、%@", comment: "Progress label and model name"),
            TranscriptionProgressPhase.transcribing.localizedDisplayName,
            "Base"
        )

        XCTAssertEqual(display.accessibilityLabel, expectedLabel)
    }
}
