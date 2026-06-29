import AppKit
import CodexRunwayCore
import Foundation
import Sparkle

@MainActor
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private let settings: RunwaySettings
    private var updaterController: SPUStandardUpdaterController?
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/Licoy/codex-runway/releases/latest")!

    init(settings: RunwaySettings) {
        self.settings = settings
        super.init()
        configureSparkle()
        applyPreferences()
    }

    func applyPreferences() {
        updaterController?.updater.automaticallyChecksForUpdates = settings.preferences.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        Task {
            let result = await latestReleaseResult()
            handle(result)
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://github.com/Licoy/codex-runway/releases/latest/download/appcast-\(Self.architecture).xml"
    }

    private func configureSparkle() {
        guard hasSparklePublicKey else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil)
    }

    private func latestReleaseResult() async -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexRunway/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return UpdateCheckResult.fromHTTP(statusCode: status, data: data, currentVersion: Self.currentVersion)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func handle(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate:
            showAlert(title: settings.l10n.text(.checkForUpdates), message: settings.l10n.text(.upToDate))
        case .updateAvailable:
            guard let updaterController else {
                showAlert(
                    title: settings.l10n.text(.updateCheckFailed),
                    message: settings.l10n.text(.updateSigningKeyMissing))
                return
            }
            updaterController.checkForUpdates(nil)
        case .failed(let message):
            showAlert(title: settings.l10n.text(.updateCheckFailed), message: message)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: settings.l10n.text(.ok))
        alert.runModal()
    }

    private var hasSparklePublicKey: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !key.isEmpty && !key.contains("__")
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1"
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
