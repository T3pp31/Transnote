import SwiftUI

@main
struct LocalTranscriberApp: App {
    init() {
        AppDirectories.ensureDirectoriesExist()
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .defaultSize(width: 800, height: 640)
    }
}
