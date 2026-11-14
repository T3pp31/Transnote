import Foundation

struct AudioImportService: Sendable {
    private static let copyBufferSize = 64 * 1024

    private let importsRoot: URL
    private let fileManager: FileManager
    private let maxImportFileSizeBytes: Int64

    init(
        importsRoot: URL = AppDirectories.importsDirectory,
        fileManager: FileManager = .default,
        maxImportFileSizeBytes: Int64 = AppConfig.shared.maxImportFileSizeBytes
    ) {
        self.importsRoot = importsRoot
        self.fileManager = fileManager
        self.maxImportFileSizeBytes = maxImportFileSizeBytes
    }

    func importFile(from sourceURL: URL, preferredFileName: String? = nil) throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppError.fileNotFound
        }

        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        // Sandbox では security-scoped access 開始後に属性を読む。
        // Imports/ 内のファイルも、コピーを省略する前に同じ検証を行う。
        try validateImportFile(at: sourceURL)
        if isAlreadyImported(sourceURL) {
            return sourceURL
        }

        try fileManager.createDirectory(at: importsRoot, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(
            for: resolvedFileName(preferredFileName: preferredFileName, sourceURL: sourceURL)
        )

        // 部分ファイルが Imports/ に残らないよう、一時ファイルへコピーしてから atomic rename する。
        // 一時ファイルは同一ディレクトリ（同一ボリューム）に置くことで moveItem を atomic にする。
        let temporaryURL = importsRoot.appendingPathComponent(".\(destinationURL.lastPathComponent).tmp-\(UUID().uuidString)")
        var importSucceeded = false
        defer {
            if !importSucceeded {
                removeFileIfExistsIfFailed(temporaryURL)
            }
        }

        // copyItem は事前検証後に増加したファイルのコピー量を制限できないため、
        // 常に書き込み前に累積サイズを検査するストリーミングコピーを使う。
        try copyFileStreaming(from: sourceURL, to: temporaryURL)

        // 一時ファイルを最終 URL へ atomic に rename する（同名競合・部分ファイル防止）
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)

        // クリーンアップ判定にはソースの録音日ではなく「取り込み日」を使う。
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: destinationURL.path)

        AppLogger.info(
            "Imported audio to sandbox: \(destinationURL.lastPathComponent)",
            logger: AppLogger.fileAccess
        )
        importSucceeded = true
        return destinationURL
    }

    private func validateImportFile(at url: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value >= 0 else {
            throw AppError.fileAccessDenied
        }
        if fileSize.int64Value > maxImportFileSizeBytes {
            throw AppError.fileTooLarge
        }
    }

    private func copyFileStreaming(from sourceURL: URL, to destinationURL: URL) throws {
        guard let inputStream = InputStream(url: sourceURL) else {
            throw AppError.fileAccessDenied
        }

        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw AppError.fileAccessDenied
        }

        guard let outputStream = OutputStream(url: destinationURL, append: false) else {
            throw AppError.fileAccessDenied
        }

        inputStream.open()
        outputStream.open()
        defer {
            inputStream.close()
            outputStream.close()
        }

        var buffer = [UInt8](repeating: 0, count: Self.copyBufferSize)
        var copiedBytes: Int64 = 0

        // hasBytesAvailable は read の前に必ずしも正確ではないため、
        // read が 0（EOF）を返すまで読み続ける。
        while true {
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                throw AppError.fileAccessDenied
            }
            if bytesRead == 0 {
                break
            }

            // 加算前に残り容量と比較し、オーバーフローと上限超過の書き込みを防ぐ。
            guard Int64(bytesRead) <= maxImportFileSizeBytes - copiedBytes else {
                throw AppError.fileTooLarge
            }
            copiedBytes += Int64(bytesRead)

            // OutputStream.write は部分書き込みを行うことがあるため、
            // 書き込めた分を進め、残りを再度書き込むループにする。
            var writtenTotal = 0
            while writtenTotal < bytesRead {
                let remaining = Array(buffer[writtenTotal..<bytesRead])
                let bytesWritten = outputStream.write(remaining, maxLength: remaining.count)
                if bytesWritten <= 0 {
                    throw AppError.fileAccessDenied
                }
                writtenTotal += bytesWritten
            }
        }
    }

    /// ファイルが存在する場合のみ削除する。importFile の失敗時にストリームを閉じてから
    /// 一時ファイルの残骸を取り除くためのヘルパー。失敗しても無視する。
    func removeFileIfExistsIfFailed(_ url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func isAlreadyImported(_ url: URL) -> Bool {
        let sourcePath = url.standardizedFileURL.path
        let importsPath = importsRoot.standardizedFileURL.path
        guard sourcePath.hasPrefix(importsPath + "/") else {
            return false
        }
        return fileManager.fileExists(atPath: sourcePath)
    }

    private func resolvedFileName(preferredFileName: String?, sourceURL: URL) -> String {
        AudioFileNameResolver.resolve(
            sourceURL: sourceURL,
            preferredFileName: preferredFileName
        )
    }

    private func uniqueDestinationURL(for fileName: String) -> URL {
        let baseURL = importsRoot.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 1

        while true {
            let candidateName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            let candidateURL = importsRoot.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    /// Imports/ 配下の古いインポートファイルを削除する。
    /// 
    /// 文字起こし完了後に元音声が不要になった場合や、失敗して残った一時ファイルが
    /// 蓄積しないよう、指定日数より古いファイルだけを対象にする。
    /// 一時ファイル（\.tmp- プレフィックス）も同様に対象とする。
    func cleanupExpiredImports(maxAge: TimeInterval = 30 * 24 * 60 * 60, now: Date = Date()) throws {
        guard fileManager.fileExists(atPath: importsRoot.path) else {
            return
        }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: importsRoot,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return
        }

        for case let url as URL in enumerator {
            let resourceValues = try? url.resourceValues(forKeys: keys)
            guard resourceValues?.isRegularFile == true else {
                continue
            }
            guard let modificationDate = resourceValues?.contentModificationDate else {
                continue
            }
            if now.timeIntervalSince(modificationDate) > maxAge {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
