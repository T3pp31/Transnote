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
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            return nil
        }

        var bestMatch: URL?
        var bestScore = -1
        var candidateCount = 0

        for case let url as URL in enumerator {
            guard isDirectory(url) else { continue }
            // .cache 等の隠しフォルダ（HuggingFace のステージング領域）はモデルフォルダの候補にしない
            guard !hasHiddenPathComponent(url) else { continue }
            guard matchesVariant(url: url, whisperKitModelName: whisperKitModelName) else { continue }
            guard hasRequiredModelFilesDirectly(in: url) else { continue }

            let score = matchScore(for: url, whisperKitModelName: whisperKitModelName)
            if score > bestScore {
                bestScore = score
                bestMatch = url
                candidateCount = 1
            } else if score == bestScore, let current = bestMatch {
                candidateCount += 1
                // 同スコア時は更新日時が新しい方を優先し、同一日時は名前の昇順で決定的に決める
                if isPreferredOver(url, current: current) {
                    bestMatch = url
                }
            }
        }

        if let bestMatch, candidateCount > 1 {
            AppLogger.info(
                "複数のモデルフォルダを検出したため候補 \(candidateCount) 件のうち '\(bestMatch.lastPathComponent)' を選択しました（スコア: \(bestScore)）"
            )
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

    /// HuggingFace のダウンロードステージング領域（.cache 等）に当たる隠しパスかどうかを判定する。
    private func hasHiddenPathComponent(_ url: URL) -> Bool {
        url.pathComponents.contains { $0.hasPrefix(".") }
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

        if folderName == variant {
            return 100
        }

        if folderName == "openai_whisper-\(variant)" {
            return 90
        }

        if folderName.hasSuffix("-\(variant)") {
            return 80
        }

        return 0
    }

    /// 同スコアの候補同士の比較。更新日時が新しい方を優先し、同一日時は名前の昇順で決定的に決める。
    /// 更新日時を取得できない場合は false を返し、列挙順（現状維持）を優先する。
    private func isPreferredOver(_ newCandidate: URL, current: URL) -> Bool {
        let newDate = modificationDate(of: newCandidate)
        let currentDate = modificationDate(of: current)

        guard let newDate, let currentDate else { return false }
        if newDate != currentDate {
            return newDate > currentDate
        }
        return newCandidate.lastPathComponent < current.lastPathComponent
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
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
