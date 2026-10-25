import AVFoundation
import WhisperKit
import XCTest
@testable import LocalTranscriber

/// 調査用の速度計測プローブ（回帰テスト／閾値アサーションではない）。
/// - 結果は print するだけで、環境差に依存する閾値は設けない
/// - テスト用 wav が無い環境（CI 含む）では XCTSkip する
/// - フィクスチャの追加候補は環境変数 TRANSNOTE_BENCH_FIXTURE で上書きできる
final class PerformanceBaselineTests: XCTestCase {
    private struct FFmpegUnavailableError: LocalizedError {
        let errorDescription: String?
    }


    private let modelsRoot = AppDirectories.modelsDirectory

    private var fixtureWAVURL: URL?
    private var longAudioURL: URL?

    override func setUpWithError() throws {
        // WhisperKit リポジトリ内のテスト用 wav を探す（相対パス優先）
        var candidates = [
            URL(fileURLWithPath: "DerivedData/SourcePackages/checkouts/argmax-oss-swift/Tests/WhisperKitTests/Resources/ja_test_clip.wav"),
        ]
        if let overridePath = ProcessInfo.processInfo.environment["TRANSNOTE_BENCH_FIXTURE"], !overridePath.isEmpty {
            candidates.insert(URL(fileURLWithPath: overridePath), at: 0)
        }
        fixtureWAVURL = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    override func tearDownWithError() throws {
        if let longAudioURL {
            try? FileManager.default.removeItem(at: longAudioURL)
        }
    }

    /// 既存コード（WhisperKitTranscriber + 現在の逐次処理）での速度計測。
    /// 長い音声ほど VAD 並列化が効かないことによる影響が出る。
    func testBaselineTranscriptionSpeed() async throws {
        guard let whisperWAV = fixtureWAVURL else {
            throw XCTSkip("no whisper test wav")
        }

        // 約3分の音声に加工（同一クリップの実長から反復数を決める）
        longAudioURL = try await Self.makeLongAudio(from: whisperWAV, targetSeconds: 180)

        let transcriber = WhisperKitTranscriber()

        let job = TranscriptionJob(
            audioFileURL: longAudioURL!,
            sourceFileName: "long-baseline.wav",
            modelID: "large-v3-turbo",
            whisperKitModelName: "large-v3-turbo",
            modelDisplayName: "Large v3 Turbo",
            languageID: "ja"
        )

        let start = Date()
        let transcript = try await transcriber.transcribe(job)
        let elapsed = Date().timeIntervalSince(start)

        print("=== BASELINE (current code) ===")
        print("audio: \(longAudioURL!.lastPathComponent)")
        print("elapsed: \(String(format: "%.2f", elapsed))s")
        print("text length: \(transcript.fullText.count)")
        print("segments: \(transcript.segments.count)")
        XCTAssertFalse(transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static func requiredRepeats(sourceDuration: TimeInterval, targetSeconds: Int) -> Int {
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            return 1
        }
        return max(1, Int((Double(targetSeconds) / sourceDuration).rounded(.up)))
    }

    private static func makeLongAudio(from sourceURL: URL, targetSeconds: Int) async throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transnote-bench-\(UUID().uuidString).wav")
        let sourceDuration = CMTimeGetSeconds(try await AVURLAsset(url: sourceURL).load(.duration))
        let repeats = requiredRepeats(sourceDuration: sourceDuration, targetSeconds: targetSeconds)
        var args: [String] = []
        for _ in 0..<repeats {
            args.append("-i")
            args.append(sourceURL.path)
        }
        let filter = (0..<repeats).map { "[\($0):a]" }.joined() + "concat=n=\(repeats):v=0:a=1[out]"
        var filterArgs = ["-y"]
        for a in args {
            filterArgs.append(a)
        }
        filterArgs += [
            "-filter_complex", filter,
            "-map", "[out]",
            tmp.path,
        ]
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        guard let ffmpegPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw FFmpegUnavailableError(errorDescription: "ffmpeg not found")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpegPath)
        p.arguments = filterArgs
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tmp.path) else {
            try? FileManager.default.removeItem(at: tmp)
            throw NSError(domain: "bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg failed"])
        }
        return tmp
    }

    func testRequiredRepeatsUsesMeasuredSourceDuration() {
        XCTAssertEqual(Self.requiredRepeats(sourceDuration: 4, targetSeconds: 180), 45)
        XCTAssertEqual(Self.requiredRepeats(sourceDuration: 2, targetSeconds: 180), 90)
        XCTAssertEqual(Self.requiredRepeats(sourceDuration: 8, targetSeconds: 180), 23)
        XCTAssertEqual(Self.requiredRepeats(sourceDuration: .infinity, targetSeconds: 180), 1)
        XCTAssertEqual(Self.requiredRepeats(sourceDuration: 0, targetSeconds: 180), 1)
    }
}
