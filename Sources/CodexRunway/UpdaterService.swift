import AppKit
import CodexRunwayCore
import Foundation
import Sparkle

@MainActor
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private let settings: RunwaySettings
    private var updater: SPUUpdater?
    private var userDriver: RunwaySparkleUserDriver?
    private static let automaticCheckInterval: TimeInterval = 3_600

    init(settings: RunwaySettings) {
        self.settings = settings
        super.init()
        configureSparkle()
        applyPreferences()
    }

    func applyPreferences() {
        updater?.automaticallyDownloadsUpdates = false
        updater?.automaticallyChecksForUpdates = settings.preferences.automaticallyChecksForUpdates
        updater?.updateCheckInterval = Self.automaticCheckInterval
    }

    func checkForUpdates() {
        switch installReadiness {
        case .ready:
            break
        case .developmentMode:
            showAlert(
                title: settings.l10n.text(.updateCheckFailed),
                message: settings.l10n.text(.updateUnavailableInDevelopment))
            return
        case .signingKeyMissing:
            showAlert(
                title: settings.l10n.text(.updateCheckFailed),
                message: settings.l10n.text(.updateSigningKeyMissing))
            return
        }

        updater?.checkForUpdates()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://github.com/Licoy/codex-runway/releases/latest/download/appcast-\(Self.architecture).xml"
    }

    private func configureSparkle() {
        guard isAppBundle, hasSparklePublicKey else { return }
        let userDriver = RunwaySparkleUserDriver(settings: settings)
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: self)
        do {
            try updater.start()
        } catch {
            return
        }
        self.userDriver = userDriver
        self.updater = updater
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: settings.l10n.text(.ok))
        alert.runModal()
    }

    private var hasSparklePublicKey: Bool {
        UpdateInstallEnvironment.hasValidSparklePublicKey(sparklePublicKey)
    }

    private var installReadiness: UpdateInstallReadiness {
        UpdateInstallEnvironment(
            bundlePathExtension: Bundle.main.bundleURL.pathExtension,
            sparklePublicKey: sparklePublicKey,
            hasUpdater: updater != nil)
            .readiness
    }

    private var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private var sparklePublicKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
