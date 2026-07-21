import AppKit
import Foundation

public struct CodexAppRestartResult: Sendable, Equatable {
    public var terminatedCount: Int
    public var relaunched: Bool
    public var appPath: String?
    public var message: String?

    public var didRestart: Bool { terminatedCount > 0 || relaunched }
}

/// Locates, quits, and relaunches the Codex desktop app so a new `auth.json` is picked up.
public enum CodexAppRestarter {
    private static let preferredBundleIdentifiers = [
        "com.openai.codex",
    ]

    private static let preferredAppNames = [
        "Codex",
    ]

    public static func restart() async -> CodexAppRestartResult {
        let running = await MainActor.run { runningCodexApps() }
        let launchURL = await MainActor.run { preferredLaunchURL(from: running) }

        var terminated = 0
        for app in running {
            let ok = await MainActor.run { () -> Bool in
                if app.terminate() { return true }
                return app.forceTerminate()
            }
            if ok { terminated += 1 }
        }

        if terminated > 0 {
            try? await Task.sleep(nanoseconds: 450_000_000)
        }

        guard let launchURL else {
            return CodexAppRestartResult(
                terminatedCount: terminated,
                relaunched: false,
                appPath: nil,
                message: terminated > 0 ? nil : "Codex app not found")
        }

        let relaunched = await openApplication(at: launchURL)
        return CodexAppRestartResult(
            terminatedCount: terminated,
            relaunched: relaunched,
            appPath: launchURL.path,
            message: relaunched ? nil : "Could not relaunch \(launchURL.lastPathComponent)")
    }

    @MainActor
    private static func runningCodexApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular || app.activationPolicy == .accessory else {
                return false
            }
            if let bundle = app.bundleIdentifier?.lowercased() {
                if preferredBundleIdentifiers.contains(where: { bundle == $0 || bundle.hasPrefix($0 + ".") }) {
                    return true
                }
                // OpenAI Codex builds sometimes ship under product-specific ids.
                if bundle.contains("codex"), bundle.contains("openai") {
                    return true
                }
            }
            if let name = app.localizedName {
                return preferredAppNames.contains(where: { name.caseInsensitiveCompare($0) == .orderedSame })
            }
            return false
        }
    }

    @MainActor
    private static func preferredLaunchURL(from running: [NSRunningApplication]) -> URL? {
        if let bundleURL = running.compactMap(\.bundleURL).first {
            return bundleURL
        }
        let candidates = [
            "/Applications/Codex.app",
            NSHomeDirectory() + "/Applications/Codex.app",
        ].map { URL(fileURLWithPath: $0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func openApplication(at url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                    continuation.resume(returning: error == nil)
                }
            }
        }
    }
}
