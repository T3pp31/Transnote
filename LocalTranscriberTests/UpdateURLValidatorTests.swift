import XCTest
@testable import LocalTranscriber

final class UpdateURLValidatorTests: XCTestCase {
    private let allowedHosts = ["github.com", "objects.githubusercontent.com"]

    // Given: 許可ホストと完全一致する HTTPS URL
    // When: isAllowedDownloadURL を実行
    // Then: true を返す
    func testIsAllowedDownloadURLAcceptsExactHostMatch() {
        XCTAssertTrue(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/latest/download/Transnote.dmg")!,
                allowedHosts: allowedHosts
            )
        )
        XCTAssertTrue(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://objects.githubusercontent.com/github-production-release-asset-2e65be/Transnote.dmg")!,
                allowedHosts: allowedHosts
            )
        )
    }

    // Given: 許可ホストのサブドメイン URL
    // When: isAllowedDownloadURL を実行
    // Then: false を返す
    func testIsAllowedDownloadURLRejectsSubdomainWildcard() {
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://evil.github.com/malware.dmg")!,
                allowedHosts: allowedHosts
            )
        )
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://cdn.objects.githubusercontent.com/malware.dmg")!,
                allowedHosts: allowedHosts
            )
        )
    }

    // Given: 非 HTTPS または許可外ホスト
    // When: isAllowedDownloadURL を実行
    // Then: false を返す
    func testIsAllowedDownloadURLRejectsNonHTTPSAndUnknownHosts() {
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "http://github.com/Transnote.dmg")!,
                allowedHosts: allowedHosts
            )
        )
        XCTAssertFalse(
            UpdateURLValidator.isAllowedDownloadURL(
                URL(string: "https://evil.example.com/malware.dmg")!,
                allowedHosts: allowedHosts
            )
        )
    }

    // Given: GitHub Releases API が返す html_url
    // When: matchesReleaseHTMLURL を実行
    // Then: 期待リポジトリなら true
    func testMatchesReleaseHTMLURLAcceptsGitHubReleasePage() {
        XCTAssertTrue(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote/releases/tag/v1.0.8")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: クエリに期待リポジトリ文字列を埋め込んだ別ホスト URL
    // When: matchesReleaseHTMLURL を実行
    // Then: false を返す
    func testMatchesReleaseHTMLURLRejectsEmbeddedRepositorySubstring() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://evil.example/redirect?x=github.com/T3pp31/Transnote")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: 別リポジトリのリリースページ
    // When: matchesReleaseHTMLURL を実行
    // Then: false を返す
    func testMatchesReleaseHTMLURLRejectsOtherRepository() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/evil/OtherApp/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: リポジトリ名が前方一致する別リポジトリ
    // When: matchesReleaseHTMLURL を実行
    // Then: false を返す
    func testMatchesReleaseHTMLURLRejectsRepositoryNamePrefix() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com/T3pp31/Transnote-malware/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }

    // Given: github.com 以外、または HTTPS 以外
    // When: matchesReleaseHTMLURL を実行
    // Then: false を返す
    func testMatchesReleaseHTMLURLRejectsNonGitHubHostsAndHTTP() {
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "http://github.com/T3pp31/Transnote/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
        XCTAssertFalse(
            UpdateRepositoryValidator.matchesReleaseHTMLURL(
                URL(string: "https://github.com.evil.com/T3pp31/Transnote/releases/tag/v0.2.0")!,
                expectedRepository: "T3pp31/Transnote"
            )
        )
    }
}
