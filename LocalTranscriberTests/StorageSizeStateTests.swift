import XCTest
@testable import LocalTranscriber

@MainActor
final class StorageSizeStateTests: XCTestCase {
    func testRefreshReturnsToCalculatingAndPublishesSize() throws {
        var state = StorageSizeState()
        XCTAssertTrue(state.isCalculating)
        XCTAssertFalse(state.isClearing)

        let initial = try XCTUnwrap(state.beginRefresh())
        state.finishRefresh(bytes: 1024, generation: initial)
        XCTAssertEqual(state.sizeText, formattedSize(1024))
        XCTAssertFalse(state.isCalculating)

        let refresh = try XCTUnwrap(state.beginRefresh())
        XCTAssertEqual(state.sizeText, "計算中…")
        XCTAssertTrue(state.isCalculating)
        state.finishRefresh(bytes: 2048, generation: refresh)
        XCTAssertEqual(state.sizeText, formattedSize(2048))
        XCTAssertFalse(state.isCalculating)
    }

    func testOnlyLatestRefreshCanPublishRegardlessOfCompletionOrder() throws {
        for oldCompletesFirst in [true, false] {
            var state = StorageSizeState()
            let old = try XCTUnwrap(state.beginRefresh())
            let latest = try XCTUnwrap(state.beginRefresh())

            if oldCompletesFirst {
                state.finishRefresh(bytes: 1_000_000_000, generation: old)
                XCTAssertEqual(state.sizeText, "計算中…")
                XCTAssertTrue(state.isCalculating)
            }
            state.finishRefresh(bytes: 2048, generation: latest)
            if !oldCompletesFirst {
                state.finishRefresh(bytes: 1_000_000_000, generation: old)
            }

            XCTAssertEqual(state.sizeText, formattedSize(2048))
            XCTAssertFalse(state.isCalculating)
            XCTAssertFalse(state.isClearing)
        }
    }

    func testClearInvalidatesRefreshBeforeAndAfterClearCompletion() throws {
        // 成功時のサイズも失敗時のエラーも、クリア前の再計算で上書きさせない。
        for succeeded in [true, false] {
            for oldCompletesFirst in [true, false] {
                var state = StorageSizeState()
                let old = try XCTUnwrap(state.beginRefresh())
                let clear = state.beginClear()
                XCTAssertTrue(state.isClearing)
                XCTAssertTrue(state.isCalculating)
                XCTAssertEqual(state.sizeText, "計算中…")

                if oldCompletesFirst {
                    state.finishRefresh(bytes: 1_000_000_000, generation: old)
                    XCTAssertTrue(state.isClearing)
                    XCTAssertTrue(state.isCalculating)
                    XCTAssertEqual(state.sizeText, "計算中…")
                }
                state.finishClear(succeeded: succeeded, bytes: 0, generation: clear, onCleared: nil)
                if !oldCompletesFirst {
                    state.finishRefresh(bytes: 1_000_000_000, generation: old)
                }

                XCTAssertEqual(state.sizeText, succeeded ? formattedSize(0) : "削除できませんでした")
                XCTAssertFalse(state.isClearing)
                XCTAssertFalse(state.isCalculating)
            }
        }
    }

    func testRefreshDuringClearDoesNotSupersedeClearAndCanResumeAfterward() throws {
        for succeeded in [true, false] {
            var state = StorageSizeState()
            let clear = state.beginClear()

            // クリア中の modelsRevision 変更は、削除後の再計算に任せる。
            XCTAssertNil(state.beginRefresh())
            XCTAssertTrue(state.isClearing)
            state.finishClear(succeeded: succeeded, bytes: 0, generation: clear, onCleared: nil)
            XCTAssertEqual(state.sizeText, succeeded ? formattedSize(0) : "削除できませんでした")
            XCTAssertFalse(state.isClearing)
            XCTAssertFalse(state.isCalculating)

            let refresh = try XCTUnwrap(state.beginRefresh())
            state.finishRefresh(bytes: 4096, generation: refresh)
            XCTAssertEqual(state.sizeText, formattedSize(4096))
            XCTAssertFalse(state.isCalculating)
        }
    }

    func testSuccessfulClearDisplaysMeasuredSizeRatherThanAssumingZero() {
        var state = StorageSizeState()
        let clear = state.beginClear()
        state.finishClear(succeeded: true, bytes: 128, generation: clear, onCleared: nil)

        XCTAssertEqual(state.sizeText, formattedSize(128))
        XCTAssertFalse(state.isClearing)
        XCTAssertFalse(state.isCalculating)
    }

    func testSuccessfulClearNotifiesParentAndRefreshesModelAvailability() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "StorageSizeStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let model = try XCTUnwrap(settings.models.first)
        settings.selectedModelID = model.id

        let folder = root.appendingPathComponent(model.whisperKitModelName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            try Data("model".utf8).write(to: folder.appendingPathComponent("\(name).mlmodelc"))
        }
        // 初回判定でディレクトリ索引をキャッシュした状態から削除する。
        let availability = ModelAvailabilityService(modelsRoot: root)
        let viewModel = MainWindowViewModel(settings: settings, modelAvailability: availability)
        viewModel.selectedFile = AudioFileInfo(
            url: root.appendingPathComponent("sample.wav"),
            fileName: "sample.wav",
            fileExtension: "wav",
            fileSizeBytes: 64,
            formattedFileSize: "64 bytes"
        )
        XCTAssertTrue(viewModel.isModelDownloaded(model))
        XCTAssertTrue(viewModel.canStartTranscription)
        XCTAssertFalse(viewModel.canDownloadSelectedModel)
        let previousRevision = viewModel.downloadedModelIDs.count
        XCTAssertEqual(previousRevision, 1)

        var state = StorageSizeState()
        let clear = state.beginClear()
        let succeeded = AppDirectories.clearDirectory(root)
        XCTAssertTrue(succeeded)
        var notificationCount = 0
        state.finishClear(
            succeeded: succeeded,
            bytes: AppDirectories.directorySize(of: root),
            generation: clear,
            onCleared: {
                XCTAssertTrue(Thread.isMainThread)
                notificationCount += 1
                viewModel.refreshModelAvailability()
            }
        )

        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(state.sizeText, formattedSize(0))
        XCTAssertFalse(state.isClearing)
        XCTAssertFalse(state.isCalculating)
        XCTAssertFalse(viewModel.isModelDownloaded(model))
        XCTAssertNil(viewModel.modelDiskUsageText(model))
        XCTAssertTrue(viewModel.shouldShowModelDownloadButton)
        XCTAssertTrue(viewModel.canDownloadSelectedModel)
        XCTAssertFalse(viewModel.canStartTranscription)
        // MainWindowView が modelsRevision に渡す値も更新される。
        XCTAssertEqual(viewModel.downloadedModelIDs.count, 0)
        XCTAssertNotEqual(viewModel.downloadedModelIDs.count, previousRevision)
    }

    func testFailedClearDoesNotNotifyParent() {
        var state = StorageSizeState()
        let clear = state.beginClear()
        var notificationCount = 0
        state.finishClear(
            succeeded: false,
            bytes: 0,
            generation: clear,
            onCleared: { notificationCount += 1 }
        )

        XCTAssertEqual(notificationCount, 0)
        XCTAssertEqual(state.sizeText, "削除できませんでした")
        XCTAssertFalse(state.isClearing)
        XCTAssertFalse(state.isCalculating)
    }

    func testSupersededClearDoesNotNotifyParentOrOverwriteLatestState() {
        for succeeded in [true, false] {
            var state = StorageSizeState()
            let old = state.beginClear()
            let latest = state.beginClear()
            var notificationCount = 0
            state.finishClear(
                succeeded: succeeded,
                bytes: 1024,
                generation: old,
                onCleared: { notificationCount += 1 }
            )
            XCTAssertEqual(notificationCount, 0)
            XCTAssertTrue(state.isClearing)
            XCTAssertTrue(state.isCalculating)

            state.finishClear(
                succeeded: true,
                bytes: 128,
                generation: latest,
                onCleared: { notificationCount += 1 }
            )
            state.finishClear(
                succeeded: succeeded,
                bytes: 1024,
                generation: old,
                onCleared: { notificationCount += 1 }
            )
            XCTAssertEqual(notificationCount, 1)
            XCTAssertEqual(state.sizeText, formattedSize(128))
            XCTAssertFalse(state.isClearing)
            XCTAssertFalse(state.isCalculating)
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
