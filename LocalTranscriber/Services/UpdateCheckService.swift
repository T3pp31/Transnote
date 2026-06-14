import Foundation

struct UpdateOffer: Sendable, Equatable {
    let latestVersion: String
    let currentVersion: String
    let downloadURL: URL
    let releaseNotes: String?
}

protocol UpdateChecking: Sendable {
    func checkForUpdate() async -> UpdateOffer?
}

struct UpdateCheckService: UpdateChecking {
    private let config: AppConfig
    private let session: URLSession
    private let currentVersionProvider: @Sendable () -> String

    init(
        config: AppConfig = .shared,
        session: URLSession = .shared,
        currentVersionProvider: @escaping @Sendable () -> String = { AppVersion.current() }
    ) {
        self.config = config
        self.session = session
        self.currentVersionProvider = currentVersionProvider
    }

    func checkForUpdate() async -> UpdateOffer? {
        guard config.updateCheckEnabled else {
            return nil
        }

        do {
            let release = try await fetchLatestRelease()
            let currentVersion = currentVersionProvider()
            let latestVersion = AppVersion.normalize(release.tagName)

            guard AppVersion.isNewer(latestVersion, than: currentVersion) else {
                AppLogger.info(
                    "App is up to date (current: \(currentVersion), latest: \(latestVersion))",
                    logger: AppLogger.general
                )
                return nil
            }

            let downloadURL = resolveDownloadURL(from: release.assets)
            return UpdateOffer(
                latestVersion: latestVersion,
                currentVersion: currentVersion,
                downloadURL: downloadURL,
                releaseNotes: release.body
            )
        } catch {
            AppLogger.error("Update check failed: \(error.localizedDescription)", logger: AppLogger.general)
            return nil
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: config.githubReleasesAPIURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Transnote", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdateCheckError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func resolveDownloadURL(from assets: [GitHubReleaseAsset]) -> URL {
        if let preferred = assets.first(where: { $0.name == config.updateDMGAssetName }) {
            return preferred.browserDownloadURL
        }
        if let dmg = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            return dmg.browserDownloadURL
        }
        return config.updateDownloadFallbackURL
    }
}

enum UpdateCheckError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
