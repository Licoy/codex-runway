import Foundation

public enum LanguagePreference: String, CaseIterable, Codable, Sendable {
    case system
    case english
    case simplifiedChinese
}

public enum ResolvedLanguage: String, Sendable, Equatable {
    case english
    case simplifiedChinese
}

public enum AppearancePreference: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark
}

public enum StatusBarDisplayStyle: String, CaseIterable, Codable, Sendable {
    case countdown
    case battery
    case meters
    case rings
}

public enum StatusBarMetersDetailStyle: String, CaseIterable, Codable, Sendable {
    case remainingPercent
    case resetTime
    case both
}

public enum StatusBarBatteryScope: String, CaseIterable, Codable, Sendable {
    case fiveHour
    case weekly
    case both
}

public enum StatusBarBatteryDetailStyle: String, CaseIterable, Codable, Sendable {
    case countdown
    case remainingPercent
}

public struct RunwayPreferences: Codable, Sendable, Equatable {
    public var language: LanguagePreference
    public var appearance: AppearancePreference
    public var statusBarDisplayStyle: StatusBarDisplayStyle
    public var statusBarMetersDetailStyle: StatusBarMetersDetailStyle
    public var statusBarBatteryScope: StatusBarBatteryScope
    public var statusBarBatteryDetailStyle: StatusBarBatteryDetailStyle
    public var refreshIntervalSeconds: Int
    public var showsCostSummary: Bool
    public var showsSessionRepairSummary: Bool
    public var automaticallyChecksForUpdates: Bool

    public init(
        language: LanguagePreference = .system,
        appearance: AppearancePreference = .system,
        statusBarDisplayStyle: StatusBarDisplayStyle = .meters,
        statusBarMetersDetailStyle: StatusBarMetersDetailStyle = .remainingPercent,
        statusBarBatteryScope: StatusBarBatteryScope = .fiveHour,
        statusBarBatteryDetailStyle: StatusBarBatteryDetailStyle = .countdown,
        refreshIntervalSeconds: Int = 300,
        showsCostSummary: Bool = true,
        showsSessionRepairSummary: Bool = true,
        automaticallyChecksForUpdates: Bool = true)
    {
        self.language = language
        self.appearance = appearance
        self.statusBarDisplayStyle = statusBarDisplayStyle
        self.statusBarMetersDetailStyle = statusBarMetersDetailStyle
        self.statusBarBatteryScope = statusBarBatteryScope
        self.statusBarBatteryDetailStyle = statusBarBatteryDetailStyle
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.showsCostSummary = showsCostSummary
        self.showsSessionRepairSummary = showsSessionRepairSummary
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    enum CodingKeys: String, CodingKey {
        case language
        case appearance
        case statusBarDisplayStyle
        case statusBarMetersDetailStyle
        case statusBarBatteryScope
        case statusBarBatteryDetailStyle
        case refreshIntervalSeconds
        case showsCostSummary
        case showsSessionRepairSummary
        case automaticallyChecksForUpdates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(LanguagePreference.self, forKey: .language) ?? .system
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? .system
        statusBarDisplayStyle = try container.decodeIfPresent(StatusBarDisplayStyle.self, forKey: .statusBarDisplayStyle) ?? .meters
        statusBarMetersDetailStyle = try container.decodeIfPresent(StatusBarMetersDetailStyle.self, forKey: .statusBarMetersDetailStyle) ?? .remainingPercent
        statusBarBatteryScope = try container.decodeIfPresent(StatusBarBatteryScope.self, forKey: .statusBarBatteryScope) ?? .fiveHour
        statusBarBatteryDetailStyle = try container.decodeIfPresent(StatusBarBatteryDetailStyle.self, forKey: .statusBarBatteryDetailStyle) ?? .countdown
        refreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 300
        showsCostSummary = try container.decodeIfPresent(Bool.self, forKey: .showsCostSummary) ?? true
        showsSessionRepairSummary = try container.decodeIfPresent(Bool.self, forKey: .showsSessionRepairSummary) ?? true
        automaticallyChecksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? true
    }
}

public struct PreferencesStore {
    private let defaults: UserDefaults
    private let key = "runway.preferences"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> RunwayPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(RunwayPreferences.self, from: data)
        else { return RunwayPreferences() }
        return preferences
    }

    public func save(_ preferences: RunwayPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
