import XCTest
@testable import LocalTranscriber

final class UpdateCheckServiceTests: XCTestCase {
    private var session: URLSession!
    private var config: AppConfig!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        config = AppConfig(
            supportedExtensions: ["wav"],
            defaultModelID: "base",
            defaultLanguageID: "auto",
            modelsDirectoryName: "Models",
            models: [],
            languages: [],
            updateCheckEnabled: true,
            githubReleasesAPIURL: URL(string: "https://api.github.com/repos/T3pp31/Transnote/releases/latest")!,
            updateDownloadFallbackURL: URL(
                string: "https://github.com/T3pp31/Transnote/releases/latest/download/Transnote.dmg"
            )!,
            updateDMGAssetName: "Transnote.dmg",
            allowedUpdateDownloadHosts: ["github.com", "objects.githubusercontent.com"],
            maxImportFileSizeBytes: 524_288_000
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        config = nil
        super.tearDown()
    }

    // Given: 現在版より新しいリリースと DMG asset
    // When: checkForUpdate を実行
    // Then: UpdateOffer を返す
    func testCheckForUpdateReturnsOfferWhenNewerVersionExists() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": "Bug fixes",
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()

        XCTAssertEqual(offer?.latestVersion, "0.2.0")
        XCTAssertEqual(offer?.currentVersion, "0.1.0")
        XCTAssertEqual(
            offer?.downloadURL,
            URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")
        )
        XCTAssertEqual(offer?.releaseNotes, "Bug fixes")
    }

    // Given: 現在版と同じリリース
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilWhenUpToDate() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.1.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.1.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": []
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: asset が無いリリース
    // When: checkForUpdate を実行
    // Then: fallback URL を使う
    func testCheckForUpdateUsesFallbackWhenAssetMissing() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": []
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.downloadURL, config.updateDownloadFallbackURL)
    }

    // Given: 不正なダウンロード URL が返る
    // When: checkForUpdate を実行
    // Then: fallback URL を使う
    func testCheckForUpdateUsesFallbackWhenAssetURLIsNotAllowed() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://evil.example.com/malware.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.downloadURL, config.updateDownloadFallbackURL)
    }

    // Given: 不正な asset URL と不正な fallback
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilWhenNoAllowedDownloadURL() async {
        let unsafeConfig = AppConfig(
            supportedExtensions: ["wav"],
            defaultModelID: "base",
            defaultLanguageID: "auto",
            modelsDirectoryName: "Models",
            models: [],
            languages: [],
            updateCheckEnabled: true,
            githubReleasesAPIURL: config.githubReleasesAPIURL,
            updateDownloadFallbackURL: URL(string: "https://evil.example.com/fallback.dmg")!,
            updateDMGAssetName: "Transnote.dmg",
            allowedUpdateDownloadHosts: ["github.com", "objects.githubusercontent.com"],
            maxImportFileSizeBytes: 524_288_000
        )

        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": {
                "full_name": "T3pp31/Transnote"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "file:///tmp/malware.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: unsafeConfig.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: unsafeConfig,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: 別リポジトリのリリースレスポンス
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilWhenRepositoryDoesNotMatch() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/evil/OtherApp/releases/tag/v0.2.0",
              "repository": {
                "full_name": "evil/OtherApp"
              },
              "assets": [
                {
                  "name": "Transnote.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg"
                }
              ]
            }
            """
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: API がエラーを返す
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilOnHTTPError() async {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: 更新チェックが無効
    // When: checkForUpdate を実行
    // Then: ネットワークに触れず nil を返す
    func testCheckForUpdateSkipsWhenDisabled() async {
        let disabledConfig = AppConfig(
            supportedExtensions: ["wav"],
            defaultModelID: "base",
            defaultLanguageID: "auto",
            modelsDirectoryName: "Models",
            models: [],
            languages: [],
            updateCheckEnabled: false,
            githubReleasesAPIURL: config.githubReleasesAPIURL,
            updateDownloadFallbackURL: config.updateDownloadFallbackURL,
            updateDMGAssetName: "Transnote.dmg",
            allowedUpdateDownloadHosts: config.allowedUpdateDownloadHosts,
            maxImportFileSizeBytes: config.maxImportFileSizeBytes
        )

        MockURLProtocol.requestHandler = { _ in
            XCTFail("Network should not be called when update check is disabled")
            fatalError("unreachable")
        }

        let service = UpdateCheckService(
            config: disabledConfig,
            session: session,
            currentVersionProvider: { "0.1.0" }
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
