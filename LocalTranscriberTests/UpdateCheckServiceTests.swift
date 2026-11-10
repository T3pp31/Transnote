import XCTest
@testable import LocalTranscriber

final class UpdateCheckServiceTests: XCTestCase {
    private var session: URLSession!
    private var config: AppConfig!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "UpdateCheckServiceTests"
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
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
        defaults = nil
        super.tearDown()
    }

    // Given: 現在版より新しいリリースと DMG asset
    // When: checkForUpdate を実行
    // Then: UpdateOffer を返す
    func testCheckForUpdateReturnsOfferWhenNewerVersionExists() async {
        defaults.set("\"previous-etag\"", forKey: "updateETag")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Transnote")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"previous-etag\"")
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()

        XCTAssertEqual(offer?.latestVersion, "0.2.0")
        XCTAssertEqual(offer?.currentVersion, "0.1.0")
        XCTAssertEqual(
            offer?.downloadURL,
            URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")
        )
        XCTAssertEqual(offer?.releaseNotes, "Bug fixes")
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        XCTAssertNotNil(defaults.object(forKey: "lastUpdateCheckDate") as? Date)

        let repeatedOffer = await service.checkForUpdate()
        XCTAssertNil(repeatedOffer)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: 期待する DMG 以外の .dmg のみが添付されたリリース
    // When: checkForUpdate を実行
    // Then: fallback URL を使う
    func testCheckForUpdateUsesFallbackWhenOnlyUnexpectedDMGExists() async {
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
                  "name": "Other.dmg",
                  "browser_download_url": "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Other.dmg"
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.downloadURL, config.updateDownloadFallbackURL)
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: html_url に期待リポジトリ文字列が埋め込まれた別リポジトリ
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilWhenRepositoryHTMLURLContainsExpectedPath() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://evil.example/redirect?x=github.com/T3pp31/Transnote",
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: GitHub REST API 相当（repository フィールドなし）の新しいリリース
    // When: checkForUpdate を実行
    // Then: html_url からリポジトリを検証し UpdateOffer を返す
    func testCheckForUpdateReturnsOfferWhenRepositoryFieldIsAbsent() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": "Bug fixes",
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()

        XCTAssertEqual(offer?.latestVersion, "0.2.0")
        XCTAssertEqual(offer?.currentVersion, "0.1.0")
        XCTAssertEqual(
            offer?.downloadURL,
            URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")
        )
    }

    // Given: repository フィールドなし、html_url に期待リポジトリ文字列のみ埋め込み
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilWhenRepositoryFieldIsAbsentAndHTMLURLIsUnrelated() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://evil.example/redirect?x=github.com/T3pp31/Transnote",
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: repository.full_name が不一致、html_url は期待リポジトリ
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilWhenRepositoryFullNameConflictsWithHTMLURL() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: repository.full_name は期待リポジトリ、html_url は別ホスト
    // When: checkForUpdate を実行
    // Then: html_url 検証で拒否し nil を返す
    func testCheckForUpdateReturnsNilWhenRepositoryFullNameMatchesButHTMLURLDoesNot() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://evil.example/malicious-release",
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
    }

    // Given: repository が JSON null、html_url は期待リポジトリ
    // When: checkForUpdate を実行
    // Then: UpdateOffer を返す
    func testCheckForUpdateReturnsOfferWhenRepositoryFieldIsNull() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": "Bug fixes",
              "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
              "repository": null,
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertEqual(offer?.latestVersion, "0.2.0")
        XCTAssertEqual(
            offer?.downloadURL,
            URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")
        )
    }

    // Given: html_url がタグなしの /releases
    // When: checkForUpdate を実行
    // Then: nil を返す
    func testCheckForUpdateReturnsNilWhenHTMLURLLacksReleaseTag() async {
        MockURLProtocol.requestHandler = { _ in
            let json = """
            {
              "tag_name": "v0.2.0",
              "body": null,
              "html_url": "https://github.com/T3pp31/Transnote/releases",
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
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
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        XCTAssertNil(defaults.object(forKey: "lastUpdateCheckDate"))
    }

    func testCheckForUpdateUpdatesThrottleOnNotModified() async {
        defaults.set("\"etag-304\"", forKey: "updateETag")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"etag-304\"")
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 304,
                httpVersion: nil,
                headerFields: ["ETag": "\"etag-304\""]
            )!
            return (response, Data())
        }

        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" },
            checkInterval: 6 * 60 * 60,
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        XCTAssertNotNil(defaults.object(forKey: "lastUpdateCheckDate") as? Date)
        XCTAssertEqual(defaults.string(forKey: "updateETag"), "\"etag-304\"")

        let repeatedOffer = await service.checkForUpdate()
        XCTAssertNil(repeatedOffer)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
    }

    func testCheckForUpdateAcceptsResponsesUpToSizeLimit() async {
        let limit = 8 * 1024 * 1024
        for size in [limit - 1, limit] {
            let data = releaseData(paddedTo: size)
            MockURLProtocol.requestHandler = { _ in
                let response = HTTPURLResponse(
                    url: self.config.githubReleasesAPIURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Length": String(size), "ETag": "\"boundary-etag\""]
                )!
                return (response, data)
            }
            let service = UpdateCheckService(
                config: config,
                session: session,
                currentVersionProvider: { "0.1.0" },
                checkInterval: 0,
                defaults: defaults
            )

            let offer = await service.checkForUpdate()

            XCTAssertEqual(offer?.latestVersion, "0.2.0", "size: \(size)")
            XCTAssertEqual(defaults.string(forKey: "updateETag"), "\"boundary-etag\"")
        }
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testCheckForUpdateRejectsOversizedContentLengthBeforeBodyArrives() async {
        await assertRejectsUnfinishedResponse(
            headerFields: ["Content-Length": String(8 * 1024 * 1024 + 1)]
        )
    }

    func testCheckForUpdateCancelsOversizedBodyWithoutContentLength() async {
        await assertRejectsUnfinishedResponse(
            headerFields: [:],
            data: releaseData(paddedTo: 8 * 1024 * 1024 + 1)
        )
    }

    func testCheckForUpdateCancelsOversizedBodyWithUnderreportedContentLength() async {
        await assertRejectsUnfinishedResponse(
            headerFields: ["Content-Length": "1"],
            data: releaseData(paddedTo: 8 * 1024 * 1024 + 1)
        )
    }

    func testCheckForUpdateReturnsNilWhenBodyStreamFails() async {
        defaults.set("\"previous-etag\"", forKey: "updateETag")
        MockURLProtocol.loadingHandler = { urlProtocol in
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "\"incomplete-etag\""]
            )!
            urlProtocol.client?.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            urlProtocol.client?.urlProtocol(urlProtocol, didLoad: Data("{\"tag_name\":".utf8))
            urlProtocol.client?.urlProtocol(urlProtocol, didFailWithError: URLError(.networkConnectionLost))
        }
        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()

        XCTAssertNil(offer)
        XCTAssertEqual(MockURLProtocol.requestCount, 1)
        XCTAssertNil(defaults.object(forKey: "lastUpdateCheckDate"))
        XCTAssertEqual(defaults.string(forKey: "updateETag"), "\"previous-etag\"")
    }

    private func releaseData(paddedTo size: Int) -> Data {
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/T3pp31/Transnote/releases/tag/v0.2.0",
          "assets": []
        }
        """
        var data = Data(json.utf8)
        data.append(Data(repeating: 0x20, count: size - data.count))
        return data
    }

    private func assertRejectsUnfinishedResponse(
        headerFields: [String: String],
        data: Data? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        defaults.set("\"previous-etag\"", forKey: "updateETag")
        let cancelled = expectation(description: "本文の受信完了を待たずにリクエストをキャンセルする")
        MockURLProtocol.stopLoadingHandler = { cancelled.fulfill() }
        MockURLProtocol.loadingHandler = { urlProtocol in
            let response = HTTPURLResponse(
                url: self.config.githubReleasesAPIURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headerFields
            )!
            urlProtocol.client?.urlProtocol(urlProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data {
                let split = data.count / 2
                urlProtocol.client?.urlProtocol(urlProtocol, didLoad: data.prefix(split))
                urlProtocol.client?.urlProtocol(urlProtocol, didLoad: data.dropFirst(split))
            }
            // EOF を送らない。全量を待つ実装ではタイムアウトし、早期中断を検出できる。
        }
        let service = UpdateCheckService(
            config: config,
            session: session,
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )
        let check = Task { await service.checkForUpdate() }

        await fulfillment(of: [cancelled], timeout: 30)
        // 回帰時にタイムアウトしても、未完了の通信を残さない。
        check.cancel()
        let offer = await check.value

        XCTAssertNil(offer, file: file, line: line)
        XCTAssertEqual(MockURLProtocol.requestCount, 1, file: file, line: line)
        XCTAssertNil(defaults.object(forKey: "lastUpdateCheckDate"), file: file, line: line)
        XCTAssertEqual(defaults.string(forKey: "updateETag"), "\"previous-etag\"", file: file, line: line)
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
            MockURLProtocol.didReceiveRequest = true
            throw URLError(.badURL)
        }

        let service = UpdateCheckService(
            config: disabledConfig,
            session: session,
            currentVersionProvider: { "0.1.0" },
            defaults: defaults
        )

        let offer = await service.checkForUpdate()
        XCTAssertNil(offer)
        XCTAssertFalse(MockURLProtocol.didReceiveRequest)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var loadingHandler: ((MockURLProtocol) -> Void)?
    static var stopLoadingHandler: (() -> Void)?
    static var didReceiveRequest = false
    static var requestCount = 0

    static func reset() {
        requestHandler = nil
        loadingHandler = nil
        stopLoadingHandler = nil
        didReceiveRequest = false
        requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        if let loadingHandler = Self.loadingHandler {
            loadingHandler(self)
            return
        }
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

    override func stopLoading() {
        Self.stopLoadingHandler?()
    }
}
