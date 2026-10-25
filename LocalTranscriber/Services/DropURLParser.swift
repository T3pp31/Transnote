import Foundation

enum DropURLParser {
    static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            if string.hasPrefix("file://"), let url = URL(string: string) {
                return url
            }
            if string.hasPrefix("file://"),
               string.dropFirst("file://".count).hasPrefix("/") {
                return URL(fileURLWithPath: String(string.dropFirst("file://".count)))
            }
            return URL(fileURLWithPath: string)
        }

        return nil
    }
}
