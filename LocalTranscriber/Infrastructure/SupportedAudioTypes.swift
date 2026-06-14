import Foundation
import UniformTypeIdentifiers

enum SupportedAudioTypes {
    private static let extensionToUTType: [String: UTType] = [
        "wav": .wav,
        "mp3": .mp3,
        "m4a": .mpeg4Audio,
        "flac": UTType(filenameExtension: "flac") ?? .audio,
    ]

    static func utType(forExtension ext: String) -> UTType? {
        extensionToUTType[ext.lowercased()]
    }

    static func allowedContentTypes(for supportedExtensions: [String]) -> [UTType] {
        supportedExtensions.compactMap { utType(forExtension: $0) }
    }

    static func resolveExtension(for url: URL, preferredFileName: String? = nil) -> String? {
        let pathExt = url.pathExtension.lowercased()
        if !pathExt.isEmpty {
            return pathExt
        }

        if let preferredFileName {
            let preferredExt = (preferredFileName as NSString).pathExtension.lowercased()
            if !preferredExt.isEmpty {
                return preferredExt
            }
        }

        if let resourceValues = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = resourceValues.contentType {
            return extensionForContentType(contentType)
        }

        return nil
    }

    static func isSupported(
        url: URL,
        supportedExtensions: [String],
        preferredFileName: String? = nil
    ) -> Bool {
        let normalized = supportedExtensions.map { $0.lowercased() }
        guard let ext = resolveExtension(for: url, preferredFileName: preferredFileName) else {
            return false
        }
        return normalized.contains(ext)
    }

    private static func extensionForContentType(_ type: UTType) -> String? {
        for (ext, utType) in extensionToUTType where type.conforms(to: utType) {
            return ext
        }
        return nil
    }
}
