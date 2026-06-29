import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Update checking")
struct UpdateTests {
    @Test("app versions compare semantic tag strings")
    func appVersionComparesSemanticTags() throws {
        let initial = try #require(AppVersion("0.0.1"))
        let next = try #require(AppVersion("0.0.2"))
        let newerMinor = try #require(AppVersion("0.1.0"))
        let oldPatch = try #require(AppVersion("0.0.9"))
        let tagged = try #require(AppVersion("v0.0.1"))

        #expect(initial < next)
        #expect(newerMinor > oldPatch)
        #expect(tagged == initial)
    }

    @Test("latest release decodes tag and assets")
    func latestReleaseDecodesTagAndAssets() throws {
        let data = """
        {
          "tag_name": "v0.0.2",
          "html_url": "https://github.com/Licoy/codex-runway/releases/tag/v0.0.2",
          "assets": [
            {"name": "CodexRunway-macos-arm64.zip", "browser_download_url": "https://example.com/arm.zip"},
            {"name": "appcast-arm64.xml", "browser_download_url": "https://example.com/appcast.xml"}
          ]
        }
        """.data(using: .utf8)!

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        #expect(release.tagName == "v0.0.2")
        #expect(release.asset(named: "CodexRunway-macos-arm64.zip")?.downloadURL.absoluteString == "https://example.com/arm.zip")
    }

    @Test("missing latest release is treated as current")
    func missingLatestReleaseIsCurrent() throws {
        let result = UpdateCheckResult.fromHTTP(statusCode: 404, data: Data(), currentVersion: "0.0.1")

        #expect(result == .upToDate)
    }

    @Test("newer latest release is available")
    func newerLatestReleaseIsAvailable() throws {
        let data = #"{"tag_name":"v0.0.2","html_url":"https://github.com/Licoy/codex-runway/releases/tag/v0.0.2","assets":[]}"#
            .data(using: .utf8)!

        let result = UpdateCheckResult.fromHTTP(statusCode: 200, data: data, currentVersion: "0.0.1")

        #expect(result == .updateAvailable("v0.0.2"))
    }

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
