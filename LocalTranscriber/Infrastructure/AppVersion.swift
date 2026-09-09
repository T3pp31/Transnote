import Foundation

enum AppVersion {
    static func current(bundle: Bundle = .main) -> String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    }

    static func compare(_ lhs: String, to rhs: String) -> ComparisonResult {
        let left = parsed(normalize(lhs))
        let right = parsed(normalize(rhs))

        // 1. MAJOR / MINOR / PATCH を数値比較する
        for index in 0..<max(left.core.count, right.core.count) {
            let leftNumber = index < left.core.count ? left.core[index] : 0
            let rightNumber = index < right.core.count ? right.core[index] : 0

            if leftNumber < rightNumber {
                return .orderedAscending
            }
            if leftNumber > rightNumber {
                return .orderedDescending
            }
        }

        // 2. 数値部分が同一の場合、プレリリースを SemVer 規約どおり比較する
        switch (left.prerelease, right.prerelease) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            // プレリリースなしの方がプレリリースありよりも新しい
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        case let (leftIdentifiers?, rightIdentifiers?):
            return comparePrerelease(leftIdentifiers, rightIdentifiers)
        }
        // ビルドメタデータは比較に影響しない
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, to: current) == .orderedDescending
    }

    private struct ParsedVersion {
        let core: [Int]
        let prerelease: [String]?
    }

    /// `MAJOR.MINOR.PATCH[-prerelease][+build]` をパースする。
    /// - ビルドメタデータ（`+` 以降）は比較対象から除外する
    /// - プレリリース（最初の `-` 以降）をドット区切りの識別子リストとして保持する
    private static func parsed(_ version: String) -> ParsedVersion {
        guard !version.isEmpty else {
            return ParsedVersion(core: [], prerelease: nil)
        }

        let withoutBuild = version.split(separator: "+", maxSplits: 1).first.map(String.init) ?? version
        let parts = withoutBuild.split(separator: "-", maxSplits: 1).map(String.init)
        let coreString = parts[0]
        let prerelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : nil

        let core = coreString
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        return ParsedVersion(core: core, prerelease: prerelease)
    }

    /// プレリリース識別子リストを SemVer 規約どおり比較する。
    /// - 同一プレフィックスの場合、短いリストの方が小さい
    private static func comparePrerelease(_ leftIdentifiers: [String], _ rightIdentifiers: [String]) -> ComparisonResult {
        let count = max(leftIdentifiers.count, rightIdentifiers.count)
        for index in 0..<count {
            if index >= leftIdentifiers.count {
                return .orderedAscending
            }
            if index >= rightIdentifiers.count {
                return .orderedDescending
            }

            let result = compareIdentifier(leftIdentifiers[index], rightIdentifiers[index])
            if result != .orderedSame {
                return result
            }
        }
        return .orderedSame
    }

    /// プレリリース識別子 1 つを比較する。
    /// - 数値のみの識別子は数値比較
    /// - 数値識別子は非数値識別子より小さい
    /// - 両方非数値の場合は ASCII 辞書順
    private static func compareIdentifier(_ left: String, _ right: String) -> ComparisonResult {
        switch (Int(left), Int(right)) {
        case let (leftNumber?, rightNumber?):
            if leftNumber < rightNumber {
                return .orderedAscending
            }
            if leftNumber > rightNumber {
                return .orderedDescending
            }
            return .orderedSame
        case (_?, nil):
            return .orderedAscending
        case (nil, _?):
            return .orderedDescending
        case (nil, nil):
            return left.compare(right, options: .literal)
        }
    }
}
