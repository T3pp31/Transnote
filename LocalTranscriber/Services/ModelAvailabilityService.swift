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
        var candidateCount = 0

        for url in variantDirectories(named: whisperKitModelName) {
            guard hasRequiredModelFilesDirectly(in: url) else { continue }

            let score = matchScore(for: url, whisperKitModelName: whisperKitModelName)
            if score > bestScore {
                bestScore = score
                bestMatch = url
                candidateCount = 1
            } else if score == bestScore, let current = bestMatch {
                candidateCount += 1
                // 同スコア時は更新日時が新しい方を優先し、同一日時は名前→パスの昇順で決定的に決める
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

    /// variant 名に一致するディレクトリを再帰的に列挙する（ファイルの存在・サイズ検証は行わない）。
    /// ダウンロード失敗時のクリーンアップで、ダウンロード前に存在したフォルダを特定するために使う。
    /// - Parameter includingHidden: `true` のとき HuggingFace の `.cache` 等も列挙する。
    ///   モデル選択では不完全なステージング領域を除外し、失敗時クリーンアップでは残渣を消せるよう含める。
    func variantDirectories(named whisperKitModelName: String, includingHidden: Bool = false) -> [URL] {
        guard fileManager.fileExists(atPath: modelsRoot.path) else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            return []
        }

        return enumerator.compactMap { object in
            guard let url = object as? URL else { return nil }
            guard isDirectory(url) else { return nil }
            if !includingHidden, hasHiddenPathComponent(url) { return nil }
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

    /// 同スコアの候補同士の比較。更新日時が新しい方を優先し、同一日時は名前、
    /// さらに同一名なら正規化パスの昇順で決定的に決める。
    /// 更新日時を取得できない場合も名前→パスで比較し、列挙順に依存しない。
    private func isPreferredOver(_ newCandidate: URL, current: URL) -> Bool {
        let newDate = modificationDate(of: newCandidate)
        let currentDate = modificationDate(of: current)

        if let newDate, let currentDate, newDate != currentDate {
            return newDate > currentDate
        }

        let newName = newCandidate.lastPathComponent
        let currentName = current.lastPathComponent
        if newName != currentName {
            return newName < currentName
        }

        return newCandidate.standardizedFileURL.path < current.standardizedFileURL.path
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
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

    /// モデルファイルが存在し、かつ中身がある（＝正常にダウンロードされた）かどうかを返す。
    /// - `.mlmodelc` / `.mlpackage` はファイルの場合もディレクトリ（バンドル）の場合もある。
    /// - ファイルは 0 バイトなら不完全。ディレクトリは inode サイズが常に 0 超のため、
    ///   子エントリが 1 つ以上あることまで確認する。
    private func isValidModelFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        if isDirectory.boolValue {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path) else {
                return false
            }
            return !contents.isEmpty
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return false }
        let size = attributes[.size] as? NSNumber
        return (size?.intValue ?? -1) > 0
    }
}
