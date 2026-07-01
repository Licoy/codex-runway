import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Update checking")
struct UpdateTests {
    @Test("update install readiness distinguishes development and signing states")
    func updateInstallReadiness() {
        #expect(UpdateInstallEnvironment(bundlePathExtension: "", sparklePublicKey: nil, hasUpdater: false).readiness == .developmentMode)
        #expect(UpdateInstallEnvironment(bundlePathExtension: "app", sparklePublicKey: nil, hasUpdater: false).readiness == .signingKeyMissing)
        #expect(UpdateInstallEnvironment(bundlePathExtension: "app", sparklePublicKey: "__SPARKLE_PUBLIC_KEY__", hasUpdater: false).readiness == .signingKeyMissing)
        #expect(UpdateInstallEnvironment(bundlePathExtension: "app", sparklePublicKey: "public-key", hasUpdater: false).readiness == .signingKeyMissing)
        #expect(UpdateInstallEnvironment(bundlePathExtension: "app", sparklePublicKey: "public-key", hasUpdater: true).readiness == .ready)
    }

    @Test("launch update check only runs when signed app automatic checks are enabled")
    func launchUpdateCheckPolicy() {
        let ready = UpdateInstallEnvironment(bundlePathExtension: "app", sparklePublicKey: "public-key", hasUpdater: true)

        #expect(ready.shouldCheckForUpdatesOnLaunch(automaticallyChecksForUpdates: true))
        #expect(!ready.shouldCheckForUpdatesOnLaunch(automaticallyChecksForUpdates: false))
        #expect(!UpdateInstallEnvironment(bundlePathExtension: "", sparklePublicKey: "public-key", hasUpdater: true)
            .shouldCheckForUpdatesOnLaunch(automaticallyChecksForUpdates: true))
        #expect(!UpdateInstallEnvironment(bundlePathExtension: "app", sparklePublicKey: nil, hasUpdater: false)
            .shouldCheckForUpdatesOnLaunch(automaticallyChecksForUpdates: true))
    }

    @Test("old preferences enable automatic updates by default")
    func oldPreferencesEnableAutomaticUpdates() throws {
        let data = """
        {
          "language": "english",
          "appearance": "dark",
          "refreshIntervalSeconds": 300,
          "showsCostSummary": true,
          "showsSessionRepairSummary": true
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(RunwayPreferences.self, from: data)

        #expect(preferences.automaticallyChecksForUpdates)
    }
}
