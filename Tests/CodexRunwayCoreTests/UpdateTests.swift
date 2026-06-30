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
