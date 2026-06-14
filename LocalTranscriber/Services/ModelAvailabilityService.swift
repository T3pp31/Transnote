import Foundation

struct ModelAvailabilityService: Sendable {
    private let modelsRoot: URL
    private let fileManager: FileManager

    private static let requiredModelNames = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

    init(
        modelsRoot: URL = AppDirectories.modelsDirectory,
        fileManager: FileManager = .default
    ) {
        self.modelsRoot = modelsRoot
        self.fileManager = fileManager
    }

    func isDownloaded(whisperKitModelName: String) -> Bool {
        modelFolder(for: whisperKitModelName) != nil
    }

    func modelFolder(for whisperKitModelName: String) -> URL? {
        guard fileManager.fileExists(atPath: modelsRoot.path) else { return nil }

        guard let enumerator = fileManager.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return nil
        }

        var bestMatch: URL?
        var bestScore = -1

        for case let url as URL in enumerator {
            guard isDirectory(url) else { continue }
            guard matchesVariant(url: url, whisperKitModelName: whisperKitModelName) else { continue }
            guard hasRequiredModelFilesDirectly(in: url) else { continue }

            let score = matchScore(for: url, whisperKitModelName: whisperKitModelName)
            if score > bestScore {
                bestScore = score
                bestMatch = url
            }
        }

        return bestMatch
    }

    func validateModelFolder(_ folder: URL) -> Bool {
        hasRequiredModelFilesDirectly(in: folder)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    private func matchesVariant(url: URL, whisperKitModelName: String) -> Bool {
        let folderName = url.lastPathComponent.lowercased()
        let variant = whisperKitModelName.lowercased()

        if folderName == variant || folderName == "openai_whisper-\(variant)" {
            return true
        }

        return folderName.contains(variant)
    }

    private func matchScore(for url: URL, whisperKitModelName: String) -> Int {
        let folderName = url.lastPathComponent.lowercased()
        let variant = whisperKitModelName.lowercased()

        if folderName == variant || folderName == "openai_whisper-\(variant)" {
            return 100
        }

        if folderName.hasSuffix(variant) {
            return 80
        }

        return folderName.contains(variant) ? 10 : 0
    }

    /// WhisperKit は modelFolder 直下の .mlmodelc を参照するため、再帰検索は使わない。
    private func hasRequiredModelFilesDirectly(in folder: URL) -> Bool {
        Self.requiredModelNames.allSatisfy { name in
            let compiled = folder.appendingPathComponent("\(name).mlmodelc")
            let package = folder.appendingPathComponent("\(name).mlpackage")
            return fileManager.fileExists(atPath: compiled.path)
                || fileManager.fileExists(atPath: package.path)
        }
    }
}
