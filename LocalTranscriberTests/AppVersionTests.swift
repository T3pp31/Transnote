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
        XCTAssertTrue(AppVersion.isNewer("0.1.0", than: "0.1.0-rc1"))
    }

    // Given: 安定版とプレリリース版
    // When: compare を実行
    // Then: プレリリース版の方が小さい
    func testCompareOrdersStableVersionsAfterPrereleases() {
        XCTAssertEqual(AppVersion.compare("0.1.0-alpha", to: "0.1.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("0.1.0-beta", to: "0.1.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-rc1", to: "1.0.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.1.0-rc1"), .orderedDescending)
    }

    // Given: 同じメジャー系内のプレリリース同士
    // When: compare を実行
    // Then: SemVer 規約どおり辞書順・数値で判定する
    func testCompareOrdersPrereleases() {
        XCTAssertEqual(AppVersion.compare("1.0.0-alpha", to: "1.0.0-beta"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-alpha.1", to: "1.0.0-alpha.2"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-1", to: "1.0.0-alpha"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("1.0.0-alpha.10", to: "1.0.0-alpha.9"), .orderedDescending)
    }

    // Given: v プレフィックス付きのプレリリースタグ
    // When: normalize して compare を実行
    // Then: プレフィックスなしと同じ結果になる
    func testCompareAfterNormalizingPrefixedPrerelease() {
        XCTAssertEqual(AppVersion.compare("v0.2.0-rc1", to: "0.2.0"), .orderedAscending)
        XCTAssertEqual(AppVersion.compare("v0.1.0-rc1", to: "0.1.0"), .orderedAscending)
    }

    // Given: ビルドメタデータ付きのバージョン
    // When: compare を実行
    // Then: ビルドメタデータは比較に影響しない
    func testCompareIgnoresBuildMetadata() {
        XCTAssertEqual(AppVersion.compare("0.1.0+build5", to: "0.1.0+build9"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("0.1.0", to: "0.1.0+build2"), .orderedSame)
    }

    // Given: プレリリースとビルドメタデータの両方を持つバージョン
    // When: compare を実行
    // Then: プレリリースに基づいて比較され、ビルドメタデータは無視される
    func testCompareWithBothPrereleaseAndBuildMetadata() {
        XCTAssertEqual(AppVersion.compare("0.1.0-rc1+build5", to: "0.1.0-rc1+build9"), .orderedSame)
        XCTAssertEqual(AppVersion.compare("0.1.0-rc1+build5", to: "0.1.0"), .orderedAscending)
    }

    // Given: Int に収まらないコア番号
    // When: compare を実行
    // Then: 桁あふれして 0 扱いにならず、大きい方が新しい
    func testCompareDoesNotOverflowLargeCoreNumbers() {
        XCTAssertEqual(
            AppVersion.compare("9223372036854775808.0.0", to: "2.0.0"),
            .orderedDescending
        )
        XCTAssertEqual(
            AppVersion.compare("2.0.0", to: "9223372036854775808.0.0"),
            .orderedAscending
        )
        XCTAssertEqual(
            AppVersion.compare("9223372036854775808.0.0", to: "9223372036854775808.0.0"),
            .orderedSame
        )
    }

    // Given: 符号付きに見えるプレリリース識別子
    // When: compare を実行
    // Then: ASCII 数字のみを数値識別子とみなし、"-1" は非数値として 0 より大きい
    func testCompareTreatsSignedPrereleaseIdentifierAsNonNumeric() {
        XCTAssertEqual(AppVersion.compare("1.0.0--1", to: "1.0.0-0"), .orderedDescending)
        XCTAssertEqual(AppVersion.compare("1.0.0-0", to: "1.0.0--1"), .orderedAscending)
    }
}
