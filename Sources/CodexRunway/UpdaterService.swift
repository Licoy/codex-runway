import AppKit
import CodexRunwayCore
import Foundation
import Sparkle

@MainActor
final class UpdaterService: NSObject, SPUUpdaterDelegate {
    private enum UpdateCheckSource { case manual, automatic }

    private let settings: RunwaySettings
    private var updater: SPUUpdater?
    private var userDriver: RunwaySparkleUserDriver?
    private var automaticCheckTimer: Timer?
    private var isCheckingForLatestRelease = false
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/Licoy/codex-runway/releases/latest")!
    private static let automaticCheckInterval: TimeInterval = 3_600

    init(settings: RunwaySettings) {
        self.settings = settings
        super.init()
        configureSparkle()
        applyPreferences()
    }

    func applyPreferences() {
        updater?.automaticallyChecksForUpdates = false
        if settings.preferences.automaticallyChecksForUpdates {
            startAutomaticChecks()
        } else {
            stopAutomaticChecks()
        }
    }

    func checkForUpdates() {
        checkForUpdates(source: .manual)
    }

    private func checkForUpdates(source: UpdateCheckSource) {
        switch installReadiness {
        case .ready:
            break
        case .developmentMode:
            if source == .manual {
                showAlert(
                    title: settings.l10n.text(.updateCheckFailed),
                    message: settings.l10n.text(.updateUnavailableInDevelopment))
            }
            return
        case .signingKeyMissing:
            if source == .manual {
                showAlert(
                    title: settings.l10n.text(.updateCheckFailed),
                    message: settings.l10n.text(.updateSigningKeyMissing))
            }
            return
        }

        guard !isCheckingForLatestRelease else { return }
        isCheckingForLatestRelease = true
        Task { @MainActor in
            defer { isCheckingForLatestRelease = false }
            let result = await latestReleaseResult()
            handle(result, source: source)
        }
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

    private func startAutomaticChecks() {
        guard automaticCheckTimer == nil else { return }
        checkForUpdates(source: .automatic)
        automaticCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.automaticCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates(source: .automatic)
            }
        }
    }

    private func stopAutomaticChecks() {
        automaticCheckTimer?.invalidate()
        automaticCheckTimer = nil
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

    private func handle(_ result: UpdateCheckResult, source: UpdateCheckSource) {
        if source == .automatic && !settings.preferences.automaticallyChecksForUpdates { return }
        switch result {
        case .upToDate:
            if source == .manual {
                showAlert(title: settings.l10n.text(.checkForUpdates), message: settings.l10n.text(.upToDate))
            }
        case .updateAvailable:
            guard let updater else {
                if source == .manual {
                    showAlert(
                        title: settings.l10n.text(.updateCheckFailed),
                        message: settings.l10n.text(.updateSigningKeyMissing))
                }
                return
            }
            updater.checkForUpdates()
        case .failed(let message):
            if source == .manual {
                showAlert(title: settings.l10n.text(.updateCheckFailed), message: message)
            }
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
