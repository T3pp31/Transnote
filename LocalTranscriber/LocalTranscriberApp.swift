import SwiftUI

@main
struct LocalTranscriberApp: App {
    init() {
        AppDirectories.ensureDirectoriesExist()
        // Imports/ に残った古い一時ファイルや完了済み音声を自動クリーンアップする。
        try? AudioImportService().cleanupExpiredImports()
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
