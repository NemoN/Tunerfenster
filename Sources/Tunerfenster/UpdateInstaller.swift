import AppKit
import Combine
import Sparkle

/// Sparkle owns the download, signature verification, replacement and relaunch.
/// The GitHub checker supplies only a feed belonging to the selected release.
@MainActor
final class UpdateInstaller: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateInstaller()
    @Published private(set) var isBusy = false
    @Published private(set) var failure: String?
    var prepareForRelaunch: (() async -> Void)?
    private var feed: URL?
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?

    /// Validate the exact bundled framework/configuration without contacting a server.
    static func checkConfiguration() throws {
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        try controller.updater.start()
    }

    static func supports(_ update: AppUpdate, bundle: Bundle = .main) -> Bool {
        guard bundle.bundleURL.pathExtension == "app",
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32,
              let url = update.installationFeedURL,
              update.downloadURL != nil else { return false }
        let expected = "https://github.com/NemoN/Tunerfenster/releases/download/v\(update.version)/appcast-\(update.architecture.rawValue).xml"
        // Releases without a v prefix are also supported by the GitHub checker.
        let unprefixed = expected.replacingOccurrences(of: "/download/v", with: "/download/")
        return url.absoluteString == expected || url.absoluteString == unprefixed
    }

    func install(_ update: AppUpdate) {
        guard !isBusy else { return }
        failure = nil
        guard Self.supports(update) else { failure = L10n.text("updateInstallerUnavailable"); return }
        feed = update.installationFeedURL
        if controller == nil {
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            do { try controller.updater.start() }
            catch {
                failure = L10n.text("updateInstallerUnavailable")
                self.controller = nil
                return
            }
            observation = controller.updater.publisher(for: \.sessionInProgress)
                .receive(on: RunLoop.main).assign(to: \.isBusy, on: self)
        }
        guard let controller, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func feedURLString(for updater: SPUUpdater) -> String? { feed?.absoluteString }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard let prepareForRelaunch else { return false }
        Task {
            await prepareForRelaunch()
            installHandler()
        }
        return true
    }
}
