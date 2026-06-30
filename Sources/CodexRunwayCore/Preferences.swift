import Foundation

public enum L10nKey: String, CaseIterable, Sendable {
    case apiCost
    case apiCostSource
    case apiEquivalent
    case apiTokenPricing
    case appearance
    case appearanceDark
    case appearanceLight
    case appearanceSystem
    case auto
    case about
    case advanced
    case account
    case automaticallyCheckForUpdates
    case available
    case availableResets
    case back
    case backup
    case cachedInputTokens
    case cachedInput
    case cancel
    case calculate
    case calculating
    case codexFolder
    case controlPanel
    case calculatedAt
    case costShare
    case costScanFailed
    case credit
    case creditsBalance
    case creditsUsed
    case currentCycle
    case currentCycleAmount
    case customRange
    case cycleStarted
    case date
    case burnRate
    case duplicate
    case duplicateIndexIDs
    case display
    case endDate
    case estimatedAPICost
    case expiresRemaining
    case expiresAt
    case expiryRisk
    case expiringSoon
    case error
    case checkForUpdates
    case fiveHourUsage
    case general
    case hours
    case modelBreakdown
    case noModelCostData
    case nonCachedInput
    case inputShort
    case inputCachedOutput
    case inputTokens
    case invalidDateRange
    case exportStatusJSON
    case exhaustsIn
    case language
    case languageEnglish
    case languageSimplifiedChinese
    case lastUpdated
    case later
    case left
    case minutes
    case missing
    case missingFromIndex
    case nextResetIn
    case nextExpiry
    case needsAttention
    case noExpiry
    case noAvailableResetCredits
    case notLoggedIn
    case noPreviousIndex
    case notLoaded
    case notScanned
    case ok
    case openControlPanel
    case openDetailsWindow
    case orphan
    case orphanIndexRows
    case outputTokens
    case outputShort
    case openGithub
    case tokenComposition
    case feedbackIssue
    case failed
    case historicalUsage
    case privacy
    case plan
    case planAPI
    case planBusiness
    case planEdu
    case planEnterprise
    case planFree
    case planPlus
    case planPro5x
    case planPro20x
    case planTeam
    case planUnknown
    case plannedEntries
    case pricingVersion
    case projectBreakdown
    case projectedAtReset
    case projectedWeeklyTotal
    case previousCycle
    case quota
    case quotaAlertBody
    case quotaAlertTitle
    case quotaAlertsDescription
    case quotaAlerts
    case quit
    case rawAnalyticsCredits
    case recent
    case recentSessionsDescription
    case refresh
    case refreshInterval
    case rebuilt
    case repair
    case repairConfirmMessage
    case repairConfirmTitle
    case repairFailed
    case repairIndex
    case resetsIn
    case resetCredits
    case resetCreditAlertBody
    case resetCreditAlertTitle
    case resetCreditAlertsDescription
    case resetCreditAlerts
    case resetCreditDetails
    case runway
    case seconds
    case sessionRepair
    case sessionScanFailed
    case recentSessions
    case settings
    case selfCheck
    case showDetails
    case showCostSummary
    case showRecentSessions
    case showSessionRepairSummary
    case sourceLocalSessions
    case sourceOnlineSupplement
    case staleTitles
    case status
    case statusAvailable
    case statusError
    case statusLogin
    case statusBarBattery
    case statusBarBatteryDetailCountdown
    case statusBarBatteryDetailRemainingPercent
    case statusBarBatteryDetailStyle
    case statusBarBatteryScope
    case statusBarBatteryScopeBoth
    case statusBarBatteryScopeFiveHour
    case statusBarBatteryScopeWeekly
    case statusBarCountdown
    case statusBarMetersDetailResetTime
    case statusBarMetersDetailRemainingPercent
    case statusBarMetersDetailBoth
    case statusBarMetersDetailStyle
    case statusBarMeters
    case statusBarRings
    case statusBarStyle
    case statusUsed
    case statusWait
    case statusUnknown
    case startDate
    case updateAvailable
    case updateCheckFailed
    case updateChecking
    case updateDownloadAndInstall
    case updateDownloadedReady
    case updateDownloading
    case updateExtracting
    case updateInstallAndRelaunch
    case updateInstallLater
    case updateInstalled
    case updateInstalledMessage
    case updateInstalling
    case updateLearnMore
    case updateReadyToInstall
    case updateSigningKeyMissing
    case updateSkipVersion
    case updateUnavailableInDevelopment
    case updateVersionAvailable
    case upToDate
    case total
    case totalRemaining
    case tokens
    case tokensOnly
    case testNotification
    case testNotificationBody
    case testNotificationDevelopmentMode
    case testNotificationSubtitle
    case testNotificationTitle
    case threads
    case thisMonth
    case turns
    case unknown
    case unknownAccount
    case unknownModels
    case unavailableCredits
    case usageAnalyticsUnavailable
    case used
    case usdPerCredit
    case version
    case weeklyValueEstimate
    case weeklyUsage
}

public struct L10n: Sendable {
    public var language: ResolvedLanguage

    public init(language: ResolvedLanguage) {
        self.language = language
    }

    public init(preference: LanguagePreference, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = Self.resolve(preference, preferredLanguages: preferredLanguages)
    }

    public init(preference: LanguagePreference, localeIdentifier: String) {
        self.language = Self.resolve(preference, localeIdentifier: localeIdentifier)
    }

    public static func resolve(_ preference: LanguagePreference, localeIdentifier: String) -> ResolvedLanguage {
        resolve(preference, preferredLanguages: [localeIdentifier])
    }

    public static func resolve(_ preference: LanguagePreference, preferredLanguages: [String]) -> ResolvedLanguage {
        switch preference {
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        case .system:
            return preferredLanguages.contains { $0.lowercased().hasPrefix("zh") } ? .simplifiedChinese : .english
        }
    }

    public func text(_ key: L10nKey) -> String {
        let table = language == .simplifiedChinese ? Self.zhHans : Self.en
        return table[key] ?? Self.en[key] ?? key.rawValue
    }

    public static func missingTranslations(for language: ResolvedLanguage) -> [L10nKey] {
        let table = language == .simplifiedChinese ? zhHans : en
        return L10nKey.allCases.filter { table[$0] == nil }
    }
}
