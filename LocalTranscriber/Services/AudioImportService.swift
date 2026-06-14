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
        // #region agent log
        DebugSessionLogger.log(
            location: "AudioImportService.swift:importFile",
            message: "importFile entry",
            data: [
                "sourcePath": sourceURL.path,
                "lastPathComponent": sourceURL.lastPathComponent,
                "pathExtension": sourceURL.pathExtension,
                "preferredFileName": preferredFileName ?? "nil",
                "fileExists": String(fileManager.fileExists(atPath: sourceURL.path)),
                "alreadyImported": String(isAlreadyImported(sourceURL)),
            ],
            hypothesisId: "B,C",
            runId: "post-fix-v5"
        )
        // #endregion

        if isAlreadyImported(sourceURL) {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw AppError.fileNotFound
            }
            return sourceURL
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            // #region agent log
            DebugSessionLogger.log(
                location: "AudioImportService.swift:importFile",
                message: "source file not found",
                data: ["sourcePath": sourceURL.path],
                hypothesisId: "C"
            )
            // #endregion
            throw AppError.fileNotFound
        }

        try fileManager.createDirectory(at: importsRoot, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(
            for: resolvedFileName(preferredFileName: preferredFileName, sourceURL: sourceURL)
        )

        let didAccessSource = sourceURL.startAccessingSecurityScopedResource()
        // #region agent log
        DebugSessionLogger.log(
            location: "AudioImportService.swift:importFile",
            message: "security scoped access",
            data: [
                "didAccessSource": String(didAccessSource),
                "destinationPath": destinationURL.path,
            ],
            hypothesisId: "B"
        )
        // #endregion
        defer {
            if didAccessSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            // #region agent log
            DebugSessionLogger.log(
                location: "AudioImportService.swift:importFile",
                message: "copyItem succeeded",
                data: ["destinationPath": destinationURL.path],
                hypothesisId: "B,E"
            )
            // #endregion
        } catch {
            let copyError = error.localizedDescription
            let isReadable = fileManager.isReadableFile(atPath: sourceURL.path)
            // #region agent log
            DebugSessionLogger.log(
                location: "AudioImportService.swift:importFile",
                message: "copyItem failed, trying fallback",
                data: [
                    "copyError": copyError,
                    "isReadable": String(isReadable),
                ],
                hypothesisId: "B"
            )
            // #endregion
            if isReadable {
                let data = try Data(contentsOf: sourceURL)
                fileManager.createFile(atPath: destinationURL.path, contents: data)
                // #region agent log
                DebugSessionLogger.log(
                    location: "AudioImportService.swift:importFile",
                    message: "fallback Data write succeeded",
                    data: [
                        "destinationPath": destinationURL.path,
                        "dataSize": String(data.count),
                    ],
                    hypothesisId: "B"
                )
                // #endregion
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
