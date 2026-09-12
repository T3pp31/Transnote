import Foundation

enum UpdateURLValidator {
    static func isAllowedDownloadURL(_ url: URL, allowedHosts: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return allowedHosts.contains { $0.lowercased() == host }
    }

    static func validatedDownloadURL(
        _ candidate: URL,
        fallback: URL,
        allowedHosts: [String]
    ) -> URL? {
        if isAllowedDownloadURL(candidate, allowedHosts: allowedHosts) {
            return candidate
        }
        if isAllowedDownloadURL(fallback, allowedHosts: allowedHosts) {
            return fallback
        }
        return nil
    }
}

enum UpdateRepositoryValidator {
    /// GitHub Releases API の `html_url` が、期待リポジトリのリリースページかを判定する。
    /// クエリへリポジトリパスを埋め込む部分文字列一致は使わない。
    static func matchesReleaseHTMLURL(_ url: URL, expectedRepository: String) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.host?.lowercased() == "github.com" else {
            return false
        }

        var components = url.pathComponents
        if components.first == "/" {
            components.removeFirst()
        }

        guard components.count >= 3, components[2] == "releases" else {
            return false
        }

        return "\(components[0])/\(components[1])" == expectedRepository
    }
}
