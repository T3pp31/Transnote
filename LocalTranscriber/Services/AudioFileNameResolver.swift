import Foundation
import UniformTypeIdentifiers

enum AudioFileNameResolver {
    static func resolve(
        sourceURL: URL,
        preferredFileName: String? = nil,
        suggestedName: String? = nil,
        typeIdentifiers: [String] = [],
        supportedExtensions: [String] = AppConfig.shared.supportedExtensions
    ) -> String {
        let supported = Set(supportedExtensions.map { $0.lowercased() })

        if let preferredFileName,
           let sanitized = sanitizeFileName(preferredFileName),
           isUsableFileName(sanitized, supportedExtensions: supported) {
            return sanitized
        }

        if let suggestedName,
           let sanitized = sanitizeFileName(suggestedName),
           isUsableFileName(sanitized, supportedExtensions: supported) {
            return sanitized
        }

        let component = sourceURL.lastPathComponent
        if let sanitized = sanitizeFileName(component),
           isUsableFileName(sanitized, supportedExtensions: supported) {
            return sanitized
        }

        if let extensionFromTypes = extensionFromTypeIdentifiers(typeIdentifiers, supportedExtensions: supported) {
            return "\(fallbackStem(from: sourceURL)).\(extensionFromTypes)"
        }

        if let extensionFromContentType = extensionFromContentType(of: sourceURL, supportedExtensions: supported) {
            return "\(fallbackStem(from: sourceURL)).\(extensionFromContentType)"
        }

        if let extensionFromMagicBytes = extensionFromMagicBytes(of: sourceURL, supportedExtensions: supported) {
            return "\(fallbackStem(from: sourceURL)).\(extensionFromMagicBytes)"
        }

        if let sanitized = sanitizeFileName(component) {
            return sanitized
        }
        return "imported-audio"
    }

    static func sanitizeFileName(_ fileName: String) -> String? {
        if fileName.contains("/") || fileName.contains("\\") {
            let components = fileName.split { $0 == "/" || $0 == "\\" }
            guard !components.isEmpty,
                  !components.contains(where: { $0 == ".." || $0 == "." }) else {
                return nil
            }
            let last = String(components.last!)
            guard !last.isEmpty else { return nil }
            return last
        }

        guard !fileName.isEmpty, fileName != ".", fileName != ".." else {
            return nil
        }
        return fileName
    }

    static func isUsableFileName(_ fileName: String, supportedExtensions: Set<String>) -> Bool {
        guard let sanitized = sanitizeFileName(fileName) else {
            return false
        }
        guard sanitized != "file URL" else {
            return false
        }
        let ext = (sanitized as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    private static func fallbackStem(from url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        if stem.isEmpty || stem == "file URL" || stem.hasPrefix("CFNetworkDownload") {
            return "imported-audio"
        }
        return stem
    }

    private static func extensionFromTypeIdentifiers(
        _ typeIdentifiers: [String],
        supportedExtensions: Set<String>
    ) -> String? {
        for identifier in typeIdentifiers {
            if let mapped = knownTypeExtensions[identifier]?.lowercased(),
               supportedExtensions.contains(mapped) {
                return mapped
            }

            guard let type = UTType(identifier),
                  let ext = type.preferredFilenameExtension?.lowercased(),
                  supportedExtensions.contains(ext) else {
                continue
            }
            return ext
        }
        return nil
    }

    private static let knownTypeExtensions: [String: String] = [
        "public.mpeg-4-audio": "m4a",
        "com.apple.m4a-audio": "m4a",
        "public.mp3": "mp3",
        "com.microsoft.waveform-audio": "wav",
        "public.wav": "wav",
        "public.flac": "flac",
    ]

    private static func extensionFromContentType(
        of url: URL,
        supportedExtensions: Set<String>
    ) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
              let contentType = values.contentType,
              let ext = contentType.preferredFilenameExtension?.lowercased(),
              supportedExtensions.contains(ext) else {
            return nil
        }
        return ext
    }

    private static func extensionFromMagicBytes(
        of url: URL,
        supportedExtensions: Set<String>
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 12), data.count >= 8 else {
            return nil
        }

        guard String(data: data[4 ..< 8], encoding: .ascii) == "ftyp" else {
            if String(data: data[0 ..< 4], encoding: .ascii) == "RIFF" {
                return supportedExtensions.contains("wav") ? "wav" : nil
            }
            if data.prefix(3) == Data("ID3".utf8) || (data.count >= 2 && data[0] == 0xFF && (data[1] & 0xE0) == 0xE0) {
                return supportedExtensions.contains("mp3") ? "mp3" : nil
            }
            if data.prefix(4) == Data("fLaC".utf8) {
                return supportedExtensions.contains("flac") ? "flac" : nil
            }
            return nil
        }

        guard data.count >= 12 else {
            return supportedExtensions.contains("m4a") ? "m4a" : nil
        }

        let brand = String(data: data[8 ..< 12], encoding: .ascii) ?? ""
        if brand.hasPrefix("M4A") || brand == "mp42" || brand == "isom" || brand == "M4B " {
            return supportedExtensions.contains("m4a") ? "m4a" : nil
        }

        return nil
    }
}
