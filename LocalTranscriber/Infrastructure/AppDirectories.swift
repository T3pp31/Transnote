import Foundation

enum AppDirectories {
    static var applicationSupport: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return url.appendingPathComponent("LocalTranscriber", isDirectory: true)
    }

    static var modelsDirectory: URL {
        applicationSupport.appendingPathComponent(AppConfig.shared.modelsDirectoryName, isDirectory: true)
    }

    static var exportsDirectory: URL {
        applicationSupport.appendingPathComponent("Exports", isDirectory: true)
    }

    static var importsDirectory: URL {
        applicationSupport.appendingPathComponent("Imports", isDirectory: true)
    }

    static var dropStagingDirectory: URL {
        applicationSupport.appendingPathComponent("DropStaging", isDirectory: true)
    }

    static func ensureDirectoriesExist() {
        let directories = [applicationSupport, modelsDirectory, exportsDirectory, importsDirectory, dropStagingDirectory]
        for directory in directories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
