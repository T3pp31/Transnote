import AppKit
import Foundation

@MainActor
final class UpdateCheckViewModel: ObservableObject {
    @Published private(set) var updateOffer: UpdateOffer?

    private let updateChecker: any UpdateChecking
    private var hasCheckedOnLaunch = false

    init(updateChecker: any UpdateChecking = UpdateCheckService()) {
        self.updateChecker = updateChecker
    }

    func checkOnLaunch() {
        guard !hasCheckedOnLaunch else { return }
        hasCheckedOnLaunch = true

        Task {
            let offer = await updateChecker.checkForUpdate()
            updateOffer = offer
        }
    }

    func dismissUpdateOffer() {
        updateOffer = nil
    }

    func openDownloadPage() {
        guard let downloadURL = updateOffer?.downloadURL else { return }
        NSWorkspace.shared.open(downloadURL)
        updateOffer = nil
    }
}
