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

        var bestMatch: URL?
        var bestScore = -1

        for url in variantDirectories(named: whisperKitModelName) {
            guard hasRequiredModelFilesDirectly(in: url) else { continue }

            let score = matchScore(for: url, whisperKitModelName: whisperKitModelName)
            if score > bestScore {
                bestScore = score
                bestMatch = url
            }
        }

        return bestMatch
    }

    /// variant 名に一致するディレクトリを再帰的に列挙する（ファイルの存在・サイズ検証は行わない）。
    /// ダウンロード失敗時のクリーンアップで、ダウンロード前に存在したフォルダを特定するために使う。
    func variantDirectories(named whisperKitModelName: String) -> [URL] {
        guard fileManager.fileExists(atPath: modelsRoot.path) else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        return enumerator.compactMap { object in
            guard let url = object as? URL else { return nil }
            guard isDirectory(url) else { return nil }
            guard matchesVariant(url: url, whisperKitModelName: whisperKitModelName) else { return nil }
            return url
        }
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

        return folderName.hasSuffix("-\(variant)")
    }

    private func matchScore(for url: URL, whisperKitModelName: String) -> Int {
        let folderName = url.lastPathComponent.lowercased()
        let variant = whisperKitModelName.lowercased()

        if folderName == variant || folderName == "openai_whisper-\(variant)" {
            return 100
        }

        if folderName.hasSuffix("-\(variant)") {
            return 80
        }

        return 0
    }

    /// WhisperKit は modelFolder 直下の .mlmodelc を参照するため、再帰検索は使わない。
    /// 途中失敗で 0バイトのまま残ったファイルは「不完全」としてダウンロード済みとみなさない。
    private func hasRequiredModelFilesDirectly(in folder: URL) -> Bool {
        Self.requiredModelNames.allSatisfy { name in
            let compiled = folder.appendingPathComponent("\(name).mlmodelc")
            let package = folder.appendingPathComponent("\(name).mlpackage")
            return isValidModelFile(at: compiled)
                || isValidModelFile(at: package)
        }
    }

    /// モデルファイルが存在し、かつ 0バイトでない（＝正常にダウンロードされた）かどうかを返す。
    /// - `.mlmodelc` / `.mlpackage` はファイルの場合もディレクトリ（バンドル）の場合もあるため、
    ///   サイズ検証はどちらの場合でも共通して行う。0バイトの場合は不完全ダウンロードとして `false`。
    private func isValidModelFile(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        let size = attributes[.size] as? NSNumber
        return (size?.intValue ?? -1) > 0
    }
}
