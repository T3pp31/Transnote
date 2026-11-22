import XCTest
@testable import LocalTranscriber

@MainActor
final class AudioPlayerServiceTests: XCTestCase {
    private var service: AudioPlayerService!
    private var tempAudioURL: URL!

    override func setUp() async throws {
        service = AudioPlayerService()
        tempAudioURL = try Self.makeSilentWAV(duration: 3.0)
    }

    override func tearDown() async throws {
        service.stop()
        service = nil
        if let tempAudioURL {
            try? FileManager.default.removeItem(at: tempAudioURL)
        }
        tempAudioURL = nil
    }

    func testLoadSetsLoadedURL() {
        service.load(url: tempAudioURL)
        XCTAssertEqual(service.loadedURL, tempAudioURL)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    func testPlaySegmentSetsTimeObserver() async throws {
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.2)

        let observerAttached = await waitUntil(timeout: 2.0) {
            self.service.hasActiveTimeObserver
        }
        XCTAssertTrue(observerAttached)
    }

    func testStopClearsPlaybackState() async throws {
        var finished = false
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.2) {
            finished = true
        }

        let started = await waitUntil(timeout: 2.0) {
            self.service.hasActiveTimeObserver
        }
        XCTAssertTrue(started, "stop 前に再生が開始されていること")

        service.stop()

        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
        XCTAssertNil(service.loadedURL)
        let finishedAfterStop = await waitUntil(timeout: 0.3) {
            finished
        }
        XCTAssertFalse(finishedAfterStop, "停止ではセグメント完了コールバックを呼ばないこと")
    }

    func testStopPlaybackClearsViewModelPlayingSegmentID() {
        let viewModel = MainWindowViewModel(audioPlayer: service)
        let segment = TranscriptSegment(startTime: 0.0, endTime: 0.5, text: "test")

        viewModel.playingSegmentID = segment.id
        viewModel.stopPlayback()

        XCTAssertNil(viewModel.playingSegmentID)
    }

    func testFailedStatusFromStaleItemDoesNotFinishCurrentPlayback() async throws {
        let staleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-\(UUID().uuidString).wav")
        try Data("not an audio file".utf8).write(to: staleURL)
        let currentURL = try Self.makeSilentWAV(duration: 3.0)
        defer {
            try? FileManager.default.removeItem(at: staleURL)
            try? FileManager.default.removeItem(at: currentURL)
        }

        service.load(url: staleURL)
        service.playSegment(start: 0, end: 3.0)
        let staleItem = try XCTUnwrap(service.currentItemForTesting)
        let staleGeneration = 1

        let failed = await waitUntil(timeout: 3.0) { staleItem.status == .failed }
        XCTAssertTrue(failed, "旧 item が .failed になること")

        var currentFinishCount = 0
        service.load(url: currentURL)
        service.playSegment(start: 0, end: 3.0) {
            currentFinishCount += 1
        }

        // 新しい item の準備完了前に、旧 item の .failed 通知が遅れて届く。
        service.handlePlayerItemStatusChange(staleItem, generation: staleGeneration)

        let started = await waitUntil(timeout: 3.0) {
            self.service.isPlaying && self.service.hasActiveTimeObserver
        }
        XCTAssertTrue(started, "古い item の失敗通知で新しい再生の開始が妨げられないこと")
        XCTAssertEqual(currentFinishCount, 0, "現在の再生は終了しないこと")
    }

    func testFailedStatusOfCurrentItemFinishesPlayback() async throws {
        let brokenURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-\(UUID().uuidString).wav")
        try Data("not an audio file".utf8).write(to: brokenURL)
        defer { try? FileManager.default.removeItem(at: brokenURL) }

        var finishCount = 0
        service.load(url: brokenURL)
        service.playSegment(start: 0, end: 1.0) {
            finishCount += 1
        }

        let finished = await waitUntil(timeout: 3.0) { finishCount == 1 }
        XCTAssertTrue(finished, "現在の item の失敗では完了コールバックが呼ばれること")
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    func testDependencyInitWiresPlaybackTimeUpdateCallback() async {
        var dependencies = AppDependencies()
        dependencies.audioPlayer = service
        let viewModel = MainWindowViewModel(dependencies: dependencies)

        XCTAssertNotNil(service.onPlaybackTimeUpdate, "init(dependencies:) でも再生位置コールバックを設定すること")

        service.onPlaybackTimeUpdate?(0, 10)

        let updated = await waitUntil(timeout: 2.0) {
            viewModel.playbackPositionText == "00:10"
        }
        XCTAssertTrue(updated, "再生位置コールバックで playbackPositionText が更新されること")
    }

    func testOnSegmentFinishedCallbackFires() async throws {
        var finished = false

        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.05) {
            finished = true
        }

        _ = await waitUntil(timeout: 3.0) {
            finished
        }

        XCTAssertTrue(finished)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    func testPauseResumePreservesSegmentFinishedCallback() async throws {
        var finishCount = 0
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 1.0) {
            finishCount += 1
        }

        let started = await waitUntil(timeout: 2.0) {
            self.service.isPlaying
                && self.service.hasActiveTimeObserver
                && self.service.currentPlaybackTime > 0
        }
        XCTAssertTrue(started, "一時停止前に再生が開始されていること")

        service.pause()
        service.pause()
        XCTAssertFalse(service.isPlaying)
        XCTAssertTrue(service.hasActiveTimeObserver)

        // セグメント長より長く待っても、一時停止中には完了しないこと。
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertEqual(finishCount, 0)
        XCTAssertFalse(service.isPlaying)

        service.resume()
        XCTAssertTrue(service.isPlaying)
        XCTAssertTrue(service.hasActiveTimeObserver)

        let completed = await waitUntil(timeout: 3.0) {
            finishCount > 0
        }
        XCTAssertTrue(completed, "再開後の終端で完了コールバックを呼ぶこと")
        XCTAssertEqual(finishCount, 1)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(finishCount, 1, "完了コールバックは一度だけ呼ぶこと")
    }

    func testPauseBeforePlaybackStartsCancelsPendingStart() async throws {
        var finished = false
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.2) {
            finished = true
        }
        // ステータス監視や seek 完了の Task が実行される前に一時停止する。
        service.pause()

        let playbackStartedOrFinished = await waitUntil(timeout: 2.0) {
            self.service.isPlaying || self.service.hasActiveTimeObserver || finished
        }
        XCTAssertFalse(playbackStartedOrFinished, "一時停止後に保留中の再生を開始しないこと")
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
        XCTAssertFalse(finished)
    }

    func testPauseBeforePlaybackStartsThenResumeFiresSegmentFinishedCallback() async throws {
        var finishCount = 0
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.25) {
            finishCount += 1
        }
        // 開始完了前に一時停止する。
        service.pause()

        let startedWhilePaused = await waitUntil(timeout: 0.3) {
            self.service.isPlaying || self.service.hasActiveTimeObserver || finishCount > 0
        }
        XCTAssertFalse(startedWhilePaused, "一時停止中は開始も完了もしないこと")

        // 再開すると seek と timeObserver 登録が行われ、終端で完了コールバックが発火すること。
        service.resume()

        let completed = await waitUntil(timeout: 3.0) {
            finishCount > 0
        }
        XCTAssertTrue(completed, "開始前の一時停止から再開した場合も完了コールバックが呼ばれること")
        XCTAssertEqual(finishCount, 1)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    func testResumeAfterSegmentFinishedDoesNotRestartPlayback() async throws {
        var finishCount = 0
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.05) {
            finishCount += 1
        }

        let completed = await waitUntil(timeout: 3.0) {
            finishCount == 1
        }
        XCTAssertTrue(completed)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)

        service.resume()
        XCTAssertFalse(service.isPlaying, "セグメント終了後の resume() で再生を再開してはならない")
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    func testPauseResumeAtEndOfAudioFiresFinishedCallback() async throws {
        let shortURL = try Self.makeSilentWAV(duration: 0.3)
        defer { try? FileManager.default.removeItem(at: shortURL) }

        var finishCount = 0
        service.load(url: shortURL)
        // セグメント終端が音声末尾以上の場合でも、EOF 通知で完了コールバックが発火すること。
        service.playSegment(start: 0.0, end: 0.5) {
            finishCount += 1
        }

        let started = await waitUntil(timeout: 2.0) {
            self.service.isPlaying && self.service.hasActiveTimeObserver
        }
        XCTAssertTrue(started)

        service.pause()
        XCTAssertFalse(service.isPlaying)
        service.resume()

        let completed = await waitUntil(timeout: 3.0) {
            finishCount == 1
        }
        XCTAssertTrue(completed, "音声末尾に到達した場合も完了コールバックが呼ばれること")
        XCTAssertEqual(finishCount, 1)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    func testViewModelPauseResumeClearsPlayingAndPausedStateOnFinish() async throws {
        let viewModel = MainWindowViewModel(audioPlayer: service)
        viewModel.selectedFile = AudioFileInfo(
            url: tempAudioURL,
            fileName: tempAudioURL.lastPathComponent,
            fileExtension: "wav",
            fileSizeBytes: 128,
            formattedFileSize: "128 bytes"
        )
        let segment = TranscriptSegment(startTime: 0.0, endTime: 0.3, text: "hello")

        viewModel.playSegment(segment)
        XCTAssertEqual(viewModel.playingSegmentID, segment.id)
        XCTAssertFalse(viewModel.isSegmentPaused)

        viewModel.pausePlayback()
        XCTAssertTrue(viewModel.isSegmentPaused)

        viewModel.resumePlayback()
        XCTAssertFalse(viewModel.isSegmentPaused)

        let cleared = await waitUntil(timeout: 3.0) {
            viewModel.playingSegmentID == nil
        }
        XCTAssertTrue(cleared, "一時停止・再開後の終了で playingSegmentID が解除されること")
        XCTAssertFalse(viewModel.isSegmentPaused)
        XCTAssertEqual(viewModel.playbackPositionText, "")
    }

    func testStatusChangeIgnoresStalePendingGeneration() throws {
        let service = AudioPlayerService()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("status-generation-\(UUID().uuidString).wav")
        let wavHeader = Data([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x24, 0x00, 0x00, 0x00, // size
            0x57, 0x41, 0x56, 0x45, // WAVE
            0x66, 0x6d, 0x74, 0x20, // fmt
            0x10, 0x00, 0x00, 0x00, // fmt size
            0x01, 0x00, // PCM
            0x01, 0x00, // channels
            0x40, 0x1f, 0x00, 0x00, // sample rate 8000
            0x80, 0x3e, 0x00, 0x00, // byte rate
            0x02, 0x00, // block align
            0x10, 0x00, // bits
            0x64, 0x61, 0x74, 0x61, // data
            0x00, 0x00, 0x00, 0x00  // data size 0
        ])
        FileManager.default.createFile(atPath: url.path, contents: wavHeader)

        service.load(url: url)
        service.playSegment(start: 0, end: 0.5)
        service.stop()

        XCTAssertFalse(service.isPlaying)
    }

    // セグメントを素早く2回連続でタップしても、後者のセグメントの再生が開始されること
    // （状態遷移 isPlaying / hasActiveTimeObserver で検証）
    func testConsecutivePlaySegmentStartsLatestSegment() async throws {
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.1)
        service.playSegment(start: 0.0, end: 2.0)

        let startedPlaying = await waitUntil(timeout: 2.0) {
            self.service.isPlaying
                && self.service.hasActiveTimeObserver
                && self.service.currentSegmentEndTime == 2.0
        }
        XCTAssertTrue(startedPlaying, "連続タップ後、後者のセグメントの再生が開始されること")

        service.stop()
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    // 連続で playSegment を呼んでも、finish コールバックが誤って早期に発火せず、
    // 後から呼んだセグメントの終了時にだけ発火すること
    func testConsecutivePlaySegmentFiresFinishCallbackOnlyForLatestSegment() async throws {
        var firstFinished = false
        var secondFinished = false

        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.1) {
            firstFinished = true
        }
        service.playSegment(start: 0.0, end: 2.0) {
            secondFinished = true
        }

        // 後者のセグメントの再生が開始される（状態遷移で確認）
        _ = await waitUntil(timeout: 2.0) {
            self.service.isPlaying && self.service.hasActiveTimeObserver
        }

        // 後者のセグメント終端を迎える前に、完了コールバックが誤って発火していないこと
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(firstFinished, "古いセグメントの完了コールバックは発火してはならない")
        XCTAssertFalse(secondFinished, "後者のセグメント終端前に完了コールバックが発火してはならない")

        // 後者のセグメントの終了時にだけ完了コールバックが発火し、再生状態がリセットされること
        let secondCompleted = await waitUntil(timeout: 3.0) {
            secondFinished
        }
        XCTAssertTrue(secondCompleted, "後者のセグメント終了時に完了コールバックが発火すること")
        XCTAssertFalse(firstFinished)
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private static func makeSilentWAV(duration: TimeInterval) throws -> URL {
        let sampleRate = 44_100
        let channelCount = 1
        let bitsPerSample = 16
        let frameCount = Int(duration * Double(sampleRate))
        let bytesPerFrame = channelCount * bitsPerSample / 8
        let dataSize = frameCount * bytesPerFrame

        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(channelCount).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        data.append(UInt32(byteRate).littleEndianData)
        let blockAlign = channelCount * bitsPerSample / 8
        data.append(UInt16(blockAlign).littleEndianData)
        data.append(UInt16(bitsPerSample).littleEndianData)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.append(UInt32(dataSize).littleEndianData)
        data.append(Data(count: dataSize))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-player-test-\(UUID().uuidString).wav")
        try data.write(to: url)
        return url
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}
