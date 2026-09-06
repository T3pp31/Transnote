import Foundation
@testable import LocalTranscriber

/// Resolves a localization key from the app bundle that owns `Localizable.xcstrings`.
/// Bare `NSLocalizedString` in unit tests uses `Bundle.main` (the test bundle).
func L(_ key: String, comment: String = "") -> String {
    NSLocalizedString(key, bundle: Bundle(for: MainWindowViewModel.self), comment: comment)
}
