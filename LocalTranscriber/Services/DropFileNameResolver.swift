import Foundation

enum DropFileNameResolver {
    static func resolve(
        suggestedName: String?,
        tempURL: URL,
        typeIdentifiers: [String]
    ) -> String {
        AudioFileNameResolver.resolve(
            sourceURL: tempURL,
            suggestedName: suggestedName,
            typeIdentifiers: typeIdentifiers
        )
    }
}
