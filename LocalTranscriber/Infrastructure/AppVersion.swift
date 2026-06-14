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
        let left = normalize(lhs).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let right = normalize(rhs).split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftPart = index < left.count ? left[index] : "0"
            let rightPart = index < right.count ? right[index] : "0"

            let leftNumber = Int(leftPart) ?? Int(leftPart.filter(\.isNumber)) ?? 0
            let rightNumber = Int(rightPart) ?? Int(rightPart.filter(\.isNumber)) ?? 0

            if leftNumber < rightNumber {
                return .orderedAscending
            }
            if leftNumber > rightNumber {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, to: current) == .orderedDescending
    }
}
