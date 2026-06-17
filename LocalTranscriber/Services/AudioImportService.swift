import Foundation

struct AudioImportService: Sendable {
    private let importsRoot: URL
    private let fileManager: FileManager

    init(
        importsRoot: URL = AppDirectories.importsDirectory,
        fileManager: FileManager = .default
    ) {
        self.importsRoot = importsRoot
        self.fileManager = fileManager
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
                let data = try Data(contentsOf: sourceURL)
                fileManager.createFile(atPath: destinationURL.path, contents: data)
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
