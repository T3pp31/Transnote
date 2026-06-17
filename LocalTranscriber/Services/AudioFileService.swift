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

    func validate(url: URL, preferredFileName: String? = nil) throws -> AudioFileInfo {
        let pathExt = url.pathExtension.lowercased()
        let ext: String
        if pathExt.isEmpty {
            guard let resolved = SupportedAudioTypes.resolveExtension(for: url, preferredFileName: preferredFileName),
                  supportedExtensions.contains(resolved) else {
                throw AppError.unsupportedFileExtension("unknown")
            }
            ext = resolved
        } else {
            guard supportedExtensions.contains(pathExt) else {
                throw AppError.unsupportedFileExtension(pathExt)
            }
            ext = pathExt
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
