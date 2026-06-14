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
            return URL(fileURLWithPath: string)
        }

        return nil
    }
}
