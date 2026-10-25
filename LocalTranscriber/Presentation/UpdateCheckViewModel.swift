import AppKit
import Foundation

@MainActor
final class UpdateCheckViewModel: ObservableObject {
    @Published private(set) var updateOffer: UpdateOffer?

    private let updateChecker: any UpdateChecking
    private let settings: AppSettings
    private var hasCheckedOnLaunch = false
    private var checkGeneration = 0

    init(updateChecker: any UpdateChecking = UpdateCheckService(), settings: AppSettings = .shared) {
        self.updateChecker = updateChecker
        self.settings = settings
    }

    func checkOnLaunch() {
        guard !hasCheckedOnLaunch else { return }
        hasCheckedOnLaunch = true
        guard settings.updateCheckEnabled else { return }

        checkGeneration += 1
        let generation = checkGeneration
        Task {
            let offer = await updateChecker.checkForUpdate()
            guard generation == checkGeneration else { return }
            updateOffer = offer
        }
    }

    /// メニューからの手動確認。起動時フラグに関係なく常にチェックする。
    func checkNow() {
        checkGeneration += 1
        let generation = checkGeneration
        Task {
            let offer = await updateChecker.checkForUpdate()
            guard generation == checkGeneration else { return }
            updateOffer = offer
        }
    }

    func dismissUpdateOffer() {
        checkGeneration += 1
        updateOffer = nil
    }

    func openDownloadPage() {
        guard let downloadURL = updateOffer?.downloadURL else { return }
        NSWorkspace.shared.open(downloadURL)
        checkGeneration += 1
        updateOffer = nil
    }
}
