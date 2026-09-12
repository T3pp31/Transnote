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
    /// GitHub Releases API の `html_url` が、期待リポジトリのリリースタグページかを判定する。
    /// 許容するのは `https://github.com/{owner}/{repo}/releases/tag/{tag}` のみ。
    /// クエリへリポジトリパスを埋め込む部分文字列一致は使わない。
    static func matchesReleaseHTMLURL(_ url: URL, expectedRepository: String) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.host?.lowercased() == "github.com" else {
            return false
        }

        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard components.count == 5,
              components[2] == "releases",
              components[3] == "tag",
              !components[4].isEmpty else {
            return false
        }

        return "\(components[0])/\(components[1])" == expectedRepository
    }
}
