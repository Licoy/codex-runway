import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Runway preferences")
struct PreferencesTests {
    @Test("system language resolves from device locale")
    func resolvesSystemLanguage() {
        #expect(L10n.resolve(.system, localeIdentifier: "zh-Hans-CN") == .simplifiedChinese)
        #expect(L10n.resolve(.system, localeIdentifier: "en-US") == .english)
        #expect(L10n.resolve(.system, localeIdentifier: "fr-FR") == .english)
    }

    @Test("translations fall back to English")
    func translationsFallbackToEnglish() {
        let english = L10n(language: .english)
        let chinese = L10n(language: .simplifiedChinese)

        #expect(english.text(.settings) == "Settings")
        #expect(chinese.text(.settings) == "设置")
    }

    @Test("all localization keys have English and Chinese translations")
    func localizationCompleteness() {
        #expect(L10n.missingTranslations(for: .english).isEmpty)
        #expect(L10n.missingTranslations(for: .simplifiedChinese).isEmpty)
    }

    @Test("preferences persist to user defaults")
    func preferencesPersist() {
        let suiteName = "CodexRunwayPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PreferencesStore(defaults: defaults)

        store.save(RunwayPreferences(
            language: .english,
            appearance: .dark,
            statusBarDisplayStyle: .rings,
            statusBarMetersDetailStyle: .resetTime,
            statusBarBatteryScope: .both,
            statusBarBatteryDetailStyle: .remainingPercent,
            refreshIntervalSeconds: 120,
            showsCostSummary: false,
            showsSessionRepairSummary: false,
            automaticallyChecksForUpdates: false))

        #expect(store.load().language == .english)
        #expect(store.load().appearance == .dark)
        #expect(store.load().statusBarDisplayStyle == .rings)
        #expect(store.load().statusBarMetersDetailStyle == .resetTime)
        #expect(store.load().statusBarBatteryScope == .both)
        #expect(store.load().statusBarBatteryDetailStyle == .remainingPercent)
        #expect(store.load().refreshIntervalSeconds == 120)
        #expect(store.load().showsCostSummary == false)
        #expect(store.load().showsSessionRepairSummary == false)
        #expect(store.load().automaticallyChecksForUpdates == false)
    }

    @Test("old preferences use new status bar defaults")
    func oldPreferencesDefaultMetersDetail() throws {
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

        #expect(preferences.statusBarDisplayStyle == .meters)
        #expect(preferences.statusBarMetersDetailStyle == .remainingPercent)
        #expect(preferences.statusBarBatteryScope == .fiveHour)
        #expect(preferences.statusBarBatteryDetailStyle == .countdown)
        #expect(preferences.automaticallyChecksForUpdates)
    }

    @Test("reset short label uses time today and date otherwise")
    func resetShortLabel() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 9)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 18, minute: 30)))
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: 8)))

        #expect(ResetLabelFormatter.shortLabel(for: today, now: now, language: .simplifiedChinese, calendar: calendar) == "18:30")
        #expect(ResetLabelFormatter.shortLabel(for: later, now: now, language: .simplifiedChinese, calendar: calendar) == "7/3")
    }

    @Test("localized durations use readable units")
    func localizedDurationsUseReadableUnits() {
        let seconds: TimeInterval = 3_661

        #expect(DurationFormatter.localized(seconds, language: .simplifiedChinese) == "1小时1分钟1秒")
        #expect(DurationFormatter.localized(seconds, language: .english) == "1 hour 1 minute 1 second")
        #expect(DurationFormatter.localized(seconds, language: .simplifiedChinese, includeSeconds: false) == "1小时1分钟")
        #expect(DurationFormatter.localized(305 * 3_600 + 54 * 60, language: .simplifiedChinese) == "12天17小时")
        #expect(DurationFormatter.localized(305 * 3_600 + 54 * 60, language: .english) == "12 days 17 hours")
    }

    @Test("single instance guard rejects a second holder")
    func singleInstanceGuardRejectsSecondHolder() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = directory.appending(path: "app.lock")

        let first = try #require(try SingleInstanceGuard.acquire(lockURL: lock))
        #expect(try SingleInstanceGuard.acquire(lockURL: lock) == nil)
        _ = first
    }
}
