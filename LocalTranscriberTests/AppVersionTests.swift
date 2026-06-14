import XCTest
@testable import LocalTranscriber

final class AppVersionTests: XCTestCase {
    // Given: 同じバージョン文字列
    // When: compare を実行
    // Then: orderedSame を返す
    func testCompareReturnsSameForEqualVersions() {
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.1.0"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("v0.1.0", to: "0.1.0"), .orderedSame)
    }

    // Given: 新版と旧版
    // When: compare を実行
    // Then: 正しい大小関係を返す
    func testCompareOrdersSemanticVersions() {
        XCTAssertEqual(AppVersion.compare("0.2.0", to: "0.1.0"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.2.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("0.10.0", to: "0.9.0"), .orderedDescending)
    }

    // Given: 先頭に v が付いたタグ名
    // When: normalize を実行
    // Then: v を除去する
    func testNormalizeStripsVersionPrefix() {
        XCTAssertEqual(AppVersion.normalize("v0.2.0"), "0.2.0")
        XCTAssertEqual(AppVersion.normalize("V1.0.0"), "1.0.0")
    }

    // Given: 新版候補
    // When: isNewer を実行
    // Then: 期待どおり判定する
    func testIsNewerDetectsAvailableUpdate() {
        XCTAssertTrue(AppVersion.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(AppVersion.isNewer("0.1.0", than: "0.2.0"))
    }
}
