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
        if isAlreadyImported(sourceURL) {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AppError.fileNotFound
            }
            return sourceURL
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppError.fileNotFound
        }

        try validateFileSize(at: sourceURL)

        try fileManager.createDirectory(at: importsRoot, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(
            for: resolvedFileName(preferredFileName: preferredFileName, sourceURL: sourceURL)
        )

        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            let isReadable = fileManager.isReadableFile(atPath: sourceURL.path)
            if isReadable {
                try copyFileStreaming(from: sourceURL, to: destinationURL)
            } else {
                throw AppError.fileAccessDenied
            }
        }

        AppLogger.info(
            "Imported audio to sandbox: \(destinationURL.lastPathComponent)",
            logger: AppLogger.fileAccess
        )
        return destinationURL
    }

    private func validateFileSize(at url: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            return
        }
        if fileSize.int64Value > maxImportFileSizeBytes {
            throw AppError.fileTooLarge
        }
    }

    private func copyFileStreaming(from sourceURL: URL, to destinationURL: URL) throws {
        guard let inputStream = InputStream(url: sourceURL) else {
            throw AppError.fileAccessDenied
        }

        fileManager.createFile(atPath: destinationURL.path, contents: nil)

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

        while inputStream.hasBytesAvailable {
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                try? fileManager.removeItem(at: destinationURL)
                throw AppError.fileAccessDenied
            }
            if bytesRead == 0 {
                break
            }

            let bytesWritten = outputStream.write(buffer, maxLength: bytesRead)
            if bytesWritten != bytesRead {
                try? fileManager.removeItem(at: destinationURL)
                throw AppError.fileAccessDenied
            }
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
}
