import XCTest
@testable import LocalTranscriber

/// 調査用プローブ（回帰テストではない）。
/// ローカルに既にあるモデルフォルダの解決結果をログ出力するだけで、
/// ネットワーク／ダウンロードには触れず、失敗もしない（常に pass）。
final class ModelResolveProbeTests: XCTestCase {
    func testProbeModelFolders() {
        let service = ModelAvailabilityService(modelsRoot: AppDirectories.modelsDirectory)
        let variants = ["tiny", "large-v3-v20240930_turbo", "large-v3-v20240930_626MB", "base"]
        for variant in variants {
            let folder = service.modelFolder(for: variant)
            print("=== PROBE \(variant): \(folder?.path ?? "NIL")")
            if let folder {
                print("=== PROBE valid: \(service.validateModelFolder(folder))")
            }
        }
        let allDirs = service.variantDirectories(named: "large-v3-v20240930_turbo")
        print("=== PROBE variantDirs count: \(allDirs.count)")
        for d in allDirs {
            print("=== PROBE dir: \(d.path)")
        }
        // 調査用のため断言は置かない（環境にモデルが無くても CI を落とさない）
        XCTAssertTrue(true)
    }
}
