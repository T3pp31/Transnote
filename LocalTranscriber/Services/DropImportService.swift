import Foundation
import UniformTypeIdentifiers

enum DropImportService {
    static func preferredTypeIdentifiers(from provider: NSItemProvider) -> [String] {
        let priority = [
            UTType.mpeg4Audio.identifier,
            "public.mpeg-4-audio",
            "com.apple.m4a-audio",
            UTType.mp3.identifier,
            UTType.wav.identifier,
            "public.flac",
            UTType.audio.identifier,
            UTType.fileURL.identifier,
        ]

        var ordered: [String] = []
        for identifier in priority where provider.hasItemConformingToTypeIdentifier(identifier) {
            if !ordered.contains(identifier) {
                ordered.append(identifier)
            }
        }

        for identifier in provider.registeredTypeIdentifiers where !ordered.contains(identifier) {
            ordered.append(identifier)
        }

        return ordered
    }

    static func resolvedFileName(
        sourceURL: URL,
        suggestedName: String?,
        typeIdentifiers: [String]
    ) -> String {
        DropFileNameResolver.resolve(
            suggestedName: suggestedName,
            tempURL: sourceURL,
            typeIdentifiers: typeIdentifiers
        )
    }

    static func hasSupportedExtension(_ fileName: String, supportedExtensions: [String]) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }
}
