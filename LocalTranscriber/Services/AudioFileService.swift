import Foundation

struct AudioFileInfo: Sendable, Equatable {
    let url: URL
    let fileName: String
    let fileExtension: String
    let fileSizeBytes: Int64
    let formattedFileSize: String
}

struct AudioFileService {
    let supportedExtensions: [String]

    init(supportedExtensions: [String] = AppConfig.shared.supportedExtensions) {
        self.supportedExtensions = supportedExtensions.map { $0.lowercased() }
    }

    func validate(url: URL) throws -> AudioFileInfo {
        let ext = url.pathExtension.lowercased()
        // #region agent log
        DebugSessionLogger.log(
            location: "AudioFileService.swift:validate",
            message: "validate entry",
            data: [
                "url": url.path,
                "detectedExtension": ext.isEmpty ? "unknown" : ext,
                "supportedExtensions": supportedExtensions.joined(separator: ","),
            ],
            hypothesisId: "A"
        )
        // #endregion
        guard supportedExtensions.contains(ext) else {
            // #region agent log
            DebugSessionLogger.log(
                location: "AudioFileService.swift:validate",
                message: "unsupported extension rejected",
                data: ["detectedExtension": ext.isEmpty ? "unknown" : ext],
                hypothesisId: "A"
            )
            // #endregion
            throw AppError.unsupportedFileExtension(ext.isEmpty ? "unknown" : ext)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.fileNotFound
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        return AudioFileInfo(
            url: url,
            fileName: url.lastPathComponent,
            fileExtension: ext,
            fileSizeBytes: fileSize,
            formattedFileSize: Self.formatByteCount(fileSize)
        )
    }

    static func formatByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
