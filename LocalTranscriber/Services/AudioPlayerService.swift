import AVFoundation
import Foundation

@MainActor
final class AudioPlayerService {
    nonisolated init() {}

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var segmentEndTime: TimeInterval = 0
    private var onFinished: (() -> Void)?
    private var pendingStartTime: TimeInterval?
    /// 再生の世代番号。playSegment を呼ぶたびに加算し、古い seek 完了コールバックを無視するために使う。
    private var playbackGeneration = 0
    /// pendingStartTime に対応する世代番号。ステータス監視経由で開始する際に使用する。
    private var pendingPlaybackGeneration = 0

    private(set) var isPlaying = false
    private(set) var loadedURL: URL?

    var hasActiveTimeObserver: Bool {
        timeObserver != nil
    }

    func load(url: URL) {
        stop(resetPlayer: false)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        loadedURL = url
    }

    func playSegment(
        start: TimeInterval,
        end: TimeInterval,
        onFinished: (() -> Void)? = nil
    ) {
        clearSegmentPlayback()
        cancelStatusObservation()

        guard let player else {
            AppLogger.error("Audio playback failed: player is not loaded", logger: AppLogger.general)
            return
        }

        guard end > start else {
            AppLogger.error("Audio playback failed: invalid segment range \(start)-\(end)", logger: AppLogger.general)
            onFinished?()
            return
        }

        segmentEndTime = end
        self.onFinished = onFinished
        pendingStartTime = start
        // 新しい再生リクエストごとに世代を進める（古い seek コールバックを無効化するため）
        playbackGeneration += 1
        let generation = playbackGeneration

        if let item = player.currentItem, item.status == .readyToPlay {
            beginPlayback(at: start, generation: generation)
        } else if let item = player.currentItem {
            pendingPlaybackGeneration = generation
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                Task { @MainActor in
                    self?.handlePlayerItemStatusChange(item)
                }
            }
        } else {
            AppLogger.error("Audio playback failed: player item is missing", logger: AppLogger.general)
            onFinished?()
        }
    }

    func stop() {
        stop(resetPlayer: true)
    }

    private func stop(resetPlayer: Bool) {
        clearSegmentPlayback()
        cancelStatusObservation()
        player?.pause()
        isPlaying = false
        segmentEndTime = 0
        pendingStartTime = nil
        pendingPlaybackGeneration = 0

        if resetPlayer {
            player = nil
            loadedURL = nil
        }
    }

    private func handlePlayerItemStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            cancelStatusObservation()
            if let start = pendingStartTime {
                beginPlayback(at: start, generation: pendingPlaybackGeneration)
            }
        case .failed:
            cancelStatusObservation()
            let message = item.error?.localizedDescription ?? "unknown error"
            AppLogger.error("Audio playback failed to load: \(message)", logger: AppLogger.general)
            finishSegmentPlayback()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func beginPlayback(at start: TimeInterval, generation: Int) {
        guard let player else { return }

        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                // 古い seek の完了コールバックは無視する（世代が異なる場合）
                guard let self else { return }
                guard self.playbackGeneration == generation else { return }

                guard finished else {
                    // seek が別の seek に割り込まれた場合。ここでは完了扱いにせず何もしない
                    return
                }
                self.player?.play()
                self.isPlaying = true
                self.installTimeObserver()
            }
        }
    }

    private func installTimeObserver() {
        guard let player else { return }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if time.seconds >= self.segmentEndTime {
                self.finishSegmentPlayback()
            }
        }
    }

    private func finishSegmentPlayback() {
        let callback = onFinished
        clearSegmentPlayback()
        cancelStatusObservation()
        pendingStartTime = nil
        pendingPlaybackGeneration = 0
        player?.pause()
        isPlaying = false
        callback?()
    }

    private func clearSegmentPlayback() {
        removeTimeObserver()
        player?.pause()
        isPlaying = false
        onFinished = nil
        pendingStartTime = nil
        pendingPlaybackGeneration = 0
    }

    private func cancelStatusObservation() {
        statusObservation = nil
    }

    private func removeTimeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }
}
