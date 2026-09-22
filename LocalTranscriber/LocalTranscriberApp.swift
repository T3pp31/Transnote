import SwiftUI

@main
struct LocalTranscriberApp: App {
    init() {
        AppDirectories.ensureDirectoriesExist()
        // 設定不整合（defaultModelID 等が Models に無い等）を起動時に検出してログへ出力する。
        for error in AppConfig.shared.validationErrors {
            AppLogger.error("AppConfig validation: \(error)", logger: AppLogger.general)
        }
    }

    var body: some Scene {
        WindowGroup("Transnote") {
            MainWindowView()
        }
        .defaultSize(width: 800, height: 680)
        .commands {
            TranscriptionCommands()
        }
    }
}
