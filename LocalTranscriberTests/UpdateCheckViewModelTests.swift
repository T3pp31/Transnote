import Combine
import XCTest
@testable import LocalTranscriber

@MainActor
final class UpdateCheckViewModelTests: XCTestCase {
    func testCheckOnLaunchCanRunAfterInitiallyDisabled() async throws {
        let settings = try makeSettings(enabled: false)
        let checker = StubUpdateChecker(offer: makeOffer())
        let viewModel = UpdateCheckViewModel(updateChecker: checker, settings: settings)

        // 無効時の複数回の呼び出しは、通信も起動時チェックの消費もしない。
        await assertNoCheck(checker) {
            viewModel.checkOnLaunch()
            viewModel.checkOnLaunch()
        }
        XCTAssertEqual(checker.callCount, 0)
        XCTAssertNil(viewModel.updateOffer)

        settings.updateCheckEnabled = true
        await waitForResult(from: viewModel) {
            viewModel.checkOnLaunch()
            viewModel.checkOnLaunch()
        }
        XCTAssertEqual(checker.callCount, 1)
        XCTAssertEqual(viewModel.updateOffer, checker.offer)

        // 実行済みなら、再表示や設定の無効化・再有効化でも繰り返さない。
        await assertNoCheck(checker) {
            viewModel.checkOnLaunch()
            settings.updateCheckEnabled = false
            viewModel.checkOnLaunch()
            settings.updateCheckEnabled = true
            viewModel.checkOnLaunch()
        }
        XCTAssertEqual(checker.callCount, 1)
        XCTAssertEqual(viewModel.updateOffer, checker.offer)
    }

    func testCheckOnLaunchRunsOnlyOnceEvenWhenNoOfferIsReturned() async throws {
        let settings = try makeSettings(enabled: true)
        let checker = StubUpdateChecker(offer: nil)
        let viewModel = UpdateCheckViewModel(updateChecker: checker, settings: settings)

        await waitForResult(from: viewModel) {
            viewModel.checkOnLaunch()
            viewModel.checkOnLaunch()
        }
        XCTAssertEqual(checker.callCount, 1)
        XCTAssertNil(viewModel.updateOffer)

        await assertNoCheck(checker) {
            viewModel.checkOnLaunch()
        }
        XCTAssertEqual(checker.callCount, 1)
    }

    func testCheckNowCanRunRepeatedlyWhileAutomaticChecksAreDisabled() async throws {
        let settings = try makeSettings(enabled: false)
        let checker = StubUpdateChecker(offer: makeOffer())
        let viewModel = UpdateCheckViewModel(updateChecker: checker, settings: settings)

        viewModel.checkOnLaunch()
        for expectedCount in 1...2 {
            await waitForResult(from: viewModel) {
                viewModel.checkNow()
            }
            XCTAssertEqual(checker.callCount, expectedCount)
            XCTAssertEqual(viewModel.updateOffer, checker.offer)
        }
    }

    private func makeSettings(enabled: Bool) throws -> AppSettings {
        let suiteName = "UpdateCheckViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        defaults.set(enabled, forKey: "updateCheckEnabled")
        return AppSettings(defaults: defaults)
    }

    private func makeOffer() -> UpdateOffer {
        UpdateOffer(
            latestVersion: "0.2.0",
            currentVersion: "0.1.0",
            downloadURL: URL(string: "https://github.com/T3pp31/Transnote/releases/latest/download/Transnote.dmg")!,
            sha256URL: nil,
            releaseNotes: nil
        )
    }

    private func waitForResult(from viewModel: UpdateCheckViewModel, action: () -> Void) async {
        let received = expectation(description: "更新確認結果が反映される")
        let subscription = viewModel.$updateOffer.dropFirst().sink { _ in
            received.fulfill()
        }
        defer { subscription.cancel() }
        action()
        await fulfillment(of: [received], timeout: 1)
    }

    private func assertNoCheck(_ checker: StubUpdateChecker, action: () -> Void) async {
        let unexpectedCheck = expectation(description: "更新確認を実行しない")
        unexpectedCheck.isInverted = true
        checker.onCheck = { unexpectedCheck.fulfill() }
        defer { checker.onCheck = nil }
        action()
        await fulfillment(of: [unexpectedCheck], timeout: 0.1)
    }
}

@MainActor
private final class StubUpdateChecker: UpdateChecking {
    let offer: UpdateOffer?
    private(set) var callCount = 0
    var onCheck: (() -> Void)?

    init(offer: UpdateOffer?) {
        self.offer = offer
    }

    func checkForUpdate() async -> UpdateOffer? {
        callCount += 1
        onCheck?()
        return offer
    }
}
