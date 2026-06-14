import XCTest
@testable import LocalTranscriber

@MainActor
final class AudioPlayerServiceTests: XCTestCase {
    private var service: AudioPlayerService!
    private var tempAudioURL: URL!

    override func setUp() async throws {
        service = AudioPlayerService()
        tempAudioURL = try Self.makeSilentWAV(duration: 1.0)
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
        service.load(url: tempAudioURL)
        service.playSegment(start: 0.0, end: 0.2)

        _ = await waitUntil(timeout: 2.0) {
            self.service.hasActiveTimeObserver
        }

        service.stop()

        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.hasActiveTimeObserver)
        XCTAssertNil(service.loadedURL)
    }

    func testStopPlaybackClearsViewModelPlayingSegmentID() {
        let viewModel = MainWindowViewModel(audioPlayer: service)
        let segment = TranscriptSegment(startTime: 0.0, endTime: 0.5, text: "test")

        viewModel.playingSegmentID = segment.id
        viewModel.stopPlayback()

        XCTAssertNil(viewModel.playingSegmentID)
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
