import XCTest
@testable import LocalTranscriber

final class ModelDownloadIntegrationTests: XCTestCase {
    func testDownloadTinyModelToAppModelsDirectory() async throws {
        let modelsRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: modelsRoot) }

        // 保存結果と進捗通知は同じ実ダウンロードで検証し、tiny の二重取得を避ける。
        let progress = DownloadProgressRecorder()
        let service = ModelDownloadService(modelsRoot: modelsRoot)
        let path = try await service.downloadIfNeeded(
            whisperKitModelName: "tiny",
            modelDisplayName: "Tiny"
        ) { update in
            progress.append(update)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        let availability = ModelAvailabilityService(modelsRoot: modelsRoot)
        XCTAssertTrue(availability.isDownloaded(whisperKitModelName: "tiny"))

        let updates = progress.snapshot()
        let initialUpdate = try XCTUnwrap(updates.first, "ダウンロード進捗が通知されていません")
        XCTAssertEqual(initialUpdate.fraction, 0)
        XCTAssertTrue(updates.contains { $0.fraction > 0 }, "SDK のダウンロード進捗が転送されていません")
        // 再試行で進捗が戻る可能性があり、サービスは終端の 1.0 通知も合成しない。
        // 単調性・最終値ではなく、実際の通知の範囲とメタデータを検証する。
        for update in updates {
            XCTAssertTrue((0.0...1.0).contains(update.fraction), "範囲外の進捗: \(update.fraction)")
            XCTAssertEqual(update.phase, .downloadingModel)
            XCTAssertEqual(update.modelDisplayName, "Tiny")
        }
    }
}

// @Sendable なコールバックからの書込みとテストからの読取りを同期する。
private final class DownloadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [TranscriptionProgressUpdate] = []

    func append(_ update: TranscriptionProgressUpdate) {
        lock.lock()
        defer { lock.unlock() }
        updates.append(update)
    }

    func snapshot() -> [TranscriptionProgressUpdate] {
        lock.lock()
        defer { lock.unlock() }
        return updates
    }
}
