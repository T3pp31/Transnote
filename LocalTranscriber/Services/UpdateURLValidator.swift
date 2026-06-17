import Foundation

enum UpdateURLValidator {
    static func isAllowedDownloadURL(_ url: URL, allowedHosts: [String]) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return allowedHosts.contains { allowedHost in
            let normalized = allowedHost.lowercased()
            return host == normalized || host.hasSuffix(".\(normalized)")
        }
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
