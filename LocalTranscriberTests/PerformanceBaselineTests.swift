import XCTest
import WhisperKit
@testable import LocalTranscriber

/// 調査用の速度計測プローブ（回帰テスト／閾値アサーションではない）。
/// - 結果は print するだけで、環境差に依存する閾値は設けない
/// - テスト用 wav が無い環境（CI 含む）では XCTSkip する
/// - ローカル絶対パスは開発マシン上の DerivedData 探索用のフォールバック
final class PerformanceBaselineTests: XCTestCase {

    private let modelsRoot = AppDirectories.modelsDirectory

    private var fixtureWAVURL: URL?
    private var longAudioURL: URL?

    override func setUpWithError() throws {
        // WhisperKit リポジトリ内のテスト用 wav を探す（相対パス優先）
        let candidates = [
            URL(fileURLWithPath: "DerivedData/SourcePackages/checkouts/argmax-oss-swift/Tests/WhisperKitTests/Resources/ja_test_clip.wav"),
            URL(fileURLWithPath: "/Users/fukutomiteppei/Documents/GitHub/Transnote/DerivedData/SourcePackages/checkouts/argmax-oss-swift/Tests/WhisperKitTests/Resources/ja_test_clip.wav"),
        ]
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

        // 約3分の音声に加工（発話+無音でリアルな会議を模す）
        longAudioURL = try Self.makeLongAudio(from: whisperWAV, targetSeconds: 180)

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

    private static func makeLongAudio(from sourceURL: URL, targetSeconds: Int) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("transnote-bench-\(UUID().uuidString).wav")
        let repeats = max(1, targetSeconds / 4)
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        p.arguments = filterArgs
        try p.run()
        p.waitUntilExit()
        guard FileManager.default.fileExists(atPath: tmp.path) else {
            throw NSError(domain: "bench", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg failed"])
        }
        return tmp
    }
}
