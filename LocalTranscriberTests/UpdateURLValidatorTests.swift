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
}
