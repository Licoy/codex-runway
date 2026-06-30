import CodexRunwayCore
import Foundation
import SwiftUI

enum CostRangeQueryError: Error {
    case usageUnavailable
}

@MainActor
final class RunwayModel: ObservableObject {
    struct DetailLine: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    @Published var statusText: String
    @Published var quotaText: String
    @Published var resetCreditsText: String
    @Published var costText: String
    @Published var costSubtitle: String
    @Published var sessionText: String
    @Published var quotaLines: [DetailLine] = []
    @Published var resetCreditLines: [DetailLine] = []
    @Published var costLines: [DetailLine] = []
    @Published var sessionLines: [DetailLine] = []
    @Published var quotaMeters: [QuotaMeter] = []
    @Published var resetCreditSummary: ResetCreditSummary?
    @Published var resetCreditDetails: [ResetCreditDetail] = []
    @Published var costDetail: ApiEquivalentSummary?
    @Published var costScanNote: String?
    @Published var accountDisplay: CodexAccountDisplay
    @Published var lastError: String?
    @Published var isRefreshing = false

    private let authStore = CodexAuthStore()
    private let quotaClient = QuotaClient()
    private let sessionRepair = SessionRepairService()
    private let costCacheStore = UsageCostCacheStore()
    private let settings: RunwaySettings
    private var latestAuth: CodexAuth?
    private var latestQuota: QuotaSnapshot?
    private var latestResetCredits: ResetCreditsSnapshot?
    private var latestCost: ApiEquivalentSummary?
    private var latestSessionReport: SessionRepairReport?

    init(settings: RunwaySettings) {
        self.settings = settings
        let l10n = settings.l10n
        self.statusText = l10n.text(.statusLogin)
        self.quotaText = l10n.text(.notLoaded)
        self.resetCreditsText = l10n.text(.notLoaded)
        self.costText = l10n.text(.notScanned)
        self.costSubtitle = ""
        self.sessionText = l10n.text(.notScanned)
        self.accountDisplay = CodexAccountDisplay.make(auth: nil, quotaPlan: nil)
        if let cached = costCacheStore.load() {
            applyCost(cached)
        }
    }

    private var l10n: L10n { settings.l10n }

    func refresh() {
        Task { await refreshNow() }
    }

    func tick(now: Date = Date()) {
        if let latestQuota {
            statusText = menuBarText(for: latestQuota, now: now)
        }
        if let latestCost {
            costSubtitle = costSubtitle(for: latestCost, now: now)
        }
    }

    func nextDueQuotaReset(after triggeredReset: Date?, now: Date = Date()) -> Date? {
        latestQuota?.nextDueReset(after: triggeredReset, now: now)
    }

    func refreshSessionReport() {
        Task { await refreshSessionReportNow() }
    }

    func repairSessions() {
        Task {
            do {
                let service = sessionRepair
                let report = try await Task.detached { try service.repair() }.value
                applySessionReport(report)
                let backup = report.backupPath?.lastPathComponent ?? l10n.text(.noPreviousIndex)
                sessionText = "\(l10n.text(.rebuilt)) \(report.plannedEntries). \(l10n.text(.backup)): \(backup)"
            } catch {
                sessionText = "\(l10n.text(.repairFailed)): \(error.localizedDescription)"
            }
        }
    }

    var repairWarning: String {
        l10n.text(.repairConfirmMessage)
    }

    func relabel() {
        accountDisplay = CodexAccountDisplay.make(auth: latestAuth, quotaPlan: latestQuota?.plan)
        if let latestQuota { applyQuota(latestQuota) } else { statusText = l10n.text(.statusLogin); quotaText = l10n.text(.notLoaded) }
        if let latestResetCredits { applyResetCredits(latestResetCredits) } else { resetCreditsText = l10n.text(.notLoaded) }
        if let latestCost { applyCost(latestCost, clearsScanNote: false) } else { costText = l10n.text(.notScanned); costSubtitle = "" }
        if let latestSessionReport { applySessionReport(latestSessionReport) } else { sessionText = l10n.text(.notScanned) }
    }

    private func refreshSessionReportNow() async {
        do {
            let service = sessionRepair
            let report = try await Task.detached { try service.dryRun() }.value
            applySessionReport(report)
        } catch {
            sessionText = l10n.text(.sessionScanFailed)
            sessionLines = [DetailLine(title: l10n.text(.error), value: error.localizedDescription)]
        }
    }

    private func applySessionReport(_ report: SessionRepairReport) {
        latestSessionReport = report
        sessionText = "\(report.missingIndexIDs.count) \(l10n.text(.missing)), \(report.orphanIndexIDs.count) \(l10n.text(.orphan)), \(report.duplicateIndexIDs.count) \(l10n.text(.duplicate))"
        sessionLines = [
            DetailLine(title: l10n.text(.plannedEntries), value: "\(report.plannedEntries)"),
            DetailLine(title: l10n.text(.missingFromIndex), value: "\(report.missingIndexIDs.count)"),
            DetailLine(title: l10n.text(.orphanIndexRows), value: "\(report.orphanIndexIDs.count)"),
            DetailLine(title: l10n.text(.duplicateIndexIDs), value: "\(report.duplicateIndexIDs.count)"),
            DetailLine(title: l10n.text(.staleTitles), value: "\(report.staleTitleIDs.count)"),
        ]
        if let backup = report.backupPath?.lastPathComponent {
            sessionLines.append(DetailLine(title: l10n.text(.backup), value: backup))
        }
    }

    private func refreshNow() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let auth = try await loadValidAuth(preferCached: false)
            let quotaSnapshot = try await quotaClient.fetchQuota(auth: auth)
            latestQuota = quotaSnapshot
            applyQuota(quotaSnapshot)
            let resetSnapshot = try await quotaClient.fetchResetCredits(auth: auth)
            latestResetCredits = resetSnapshot
            applyResetCredits(resetSnapshot)
            await scanCost(quotaSnapshot, auth: auth)
            await refreshSessionReportNow()
            lastError = nil
        } catch {
            statusText = l10n.text(.statusError)
            lastError = error.localizedDescription
        }
    }

    func queryCost(range: ApiCostRange) async throws -> ApiEquivalentSummary {
        let now = Date()
        do {
            let local = try await Task.detached {
                try UsageCostScanner().scanAPIEquivalent(window: range.window, calculatedAt: now)
            }.value
            if local.isDisplayableCost {
                return local
            }
        } catch {
            // Fall through to online analytics.
        }
        let auth = try await loadValidAuth(preferCached: true)
        let summary = try await quotaClient.fetchDailyWorkspaceUsage(
            auth: auth,
            startDate: range.apiStartDate,
            endDate: range.apiEndDate,
            window: range.window,
            calculatedAt: now)
        guard summary.isDisplayableCost else { throw CostRangeQueryError.usageUnavailable }
        return summary
    }

    private func loadValidAuth(preferCached: Bool) async throws -> CodexAuth {
        var auth: CodexAuth
        if preferCached, let latestAuth {
            auth = latestAuth
        } else {
            do {
                auth = try authStore.load()
            } catch {
                latestAuth = nil
                accountDisplay = CodexAccountDisplay.make(auth: nil, quotaPlan: nil)
                throw error
            }
        }
        if TokenInspector.isExpired(auth.tokens.accessToken) {
            try await TokenRefresher().refresh(&auth, store: authStore)
        }
        latestAuth = auth
        accountDisplay = CodexAccountDisplay.make(auth: auth, quotaPlan: latestQuota?.plan)
        return auth
    }

    private func applyQuota(_ quota: QuotaSnapshot) {
        accountDisplay = CodexAccountDisplay.make(auth: latestAuth, quotaPlan: quota.plan)
        statusText = menuBarText(for: quota, now: quota.updatedAt)
        let unknown = l10n.text(.unknown)
        let secondary = quota.secondary.map { "\(l10n.text(.weeklyUsage)) \($0.usedPercent)%" } ?? "\(l10n.text(.weeklyUsage)) n/a"
        quotaText = "\(l10n.text(.plan)) \(quota.plan ?? unknown) · \(l10n.text(.fiveHourUsage)) \(quota.primary.usedPercent)% · \(secondary)"
        quotaMeters = quotaMeters(from: quota)
        quotaLines = [
            DetailLine(title: l10n.text(.plan), value: quota.plan ?? unknown),
            DetailLine(title: l10n.text(.fiveHourUsage), value: windowText(quota.primary, now: quota.updatedAt)),
        ]
        if let secondary = quota.secondary {
            quotaLines.append(DetailLine(title: l10n.text(.weeklyUsage), value: windowText(secondary, now: quota.updatedAt)))
        }
        for extra in quota.additionalWindows {
            quotaLines.append(DetailLine(title: extra.name, value: windowText(extra.window, now: quota.updatedAt)))
        }
        if let balance = quota.creditsBalance {
            quotaLines.append(DetailLine(title: l10n.text(.creditsBalance), value: String(format: "%.2f", balance)))
        }
    }

    private func applyResetCredits(_ snapshot: ResetCreditsSnapshot) {
        let next = snapshot.credits
            .filter { $0.status == "available" }
            .compactMap(\.expiresAt)
            .min()
        latestResetCredits = snapshot
        resetCreditSummary = ResetCreditSummary(snapshot: snapshot)
        let suffix = next.map { " · \(l10n.text(.left)) \(duration($0.timeIntervalSince(snapshot.updatedAt)))" } ?? ""
        resetCreditsText = "\(snapshot.availableCount) \(l10n.text(.available)) / \(snapshot.credits.count) \(l10n.text(.total))\(suffix)"
        resetCreditLines = [
            DetailLine(title: l10n.text(.available), value: "\(snapshot.availableCount)"),
            DetailLine(title: l10n.text(.total), value: "\(snapshot.credits.count)"),
        ]
        resetCreditLines.append(contentsOf: snapshot.credits.prefix(6).enumerated().map { index, credit in
            let expiry = credit.expiresAt.map {
                "\(Self.displayDate($0)) · \(duration($0.timeIntervalSince(snapshot.updatedAt))) \(l10n.text(.left))"
            } ?? l10n.text(.noExpiry)
            return DetailLine(title: "\(l10n.text(.credit)) \(index + 1)", value: "\(localizedStatus(credit.status)) · \(expiry)")
        })
        resetCreditDetails = ResetCreditSummary.sortedByExpiry(snapshot.credits).enumerated().map { index, credit in
            let remaining = max(0, credit.remainingSeconds)
            let hasExpiry = credit.expiresAt != nil
            return ResetCreditDetail(
                id: credit.id ?? "\(index)",
                title: "\(l10n.text(.credit)) \(index + 1)",
                statusText: localizedStatus(credit.status),
                state: resetCreditState(credit),
                expiresAt: credit.expiresAt,
                remainingDuration: remaining,
                remainingProgress: hasExpiry ? min(1, remaining / (30 * 24 * 3_600)) : 1)
        }
    }

    private func scanCost(_ quota: QuotaSnapshot, auth: CodexAuth) async {
        guard let secondary = quota.secondary,
              let reset = secondary.resetsAt,
              let minutes = secondary.windowMinutes
        else {
            if latestCost != nil {
                noteCostScanFailure(l10n.text(.usageAnalyticsUnavailable))
            } else {
                clearCost(l10n.text(.usageAnalyticsUnavailable))
            }
            return
        }
        let window = DateInterval(start: reset.addingTimeInterval(-TimeInterval(minutes * 60)), end: reset)
        let now = Date()
        do {
            let local = try await Task.detached {
                try UsageCostScanner().scanAPIEquivalent(window: window, calculatedAt: now)
            }.value
            if local.isDisplayableCost {
                applyCost(local)
                cacheCost(local)
                return
            }
        } catch {
            if latestCost != nil {
                noteCostScanFailure(error.localizedDescription)
            } else {
                costLines = [DetailLine(title: l10n.text(.costScanFailed), value: error.localizedDescription)]
            }
        }
        do {
            let summary = try await quotaClient.fetchDailyWorkspaceUsage(
                auth: auth,
                startDate: Self.apiDateString(now.addingTimeInterval(-30 * 86_400)),
                endDate: Self.apiDateString(now.addingTimeInterval(86_400)),
                window: window)
            if summary.isDisplayableCost {
                applyCost(summary)
                cacheCost(summary)
            } else if latestCost != nil {
                noteCostScanFailure(l10n.text(.usageAnalyticsUnavailable))
            } else {
                clearCost(l10n.text(.usageAnalyticsUnavailable))
            }
        } catch {
            if latestCost != nil {
                noteCostScanFailure(error.localizedDescription)
            } else {
                clearCost(l10n.text(.usageAnalyticsUnavailable))
                costLines = [DetailLine(title: l10n.text(.error), value: error.localizedDescription)]
            }
        }
    }

    private func applyCost(_ summary: ApiEquivalentSummary, now: Date = Date(), clearsScanNote: Bool = true) {
        if clearsScanNote { costScanNote = nil }
        latestCost = summary
        costDetail = summary
        let amount = summary.estimatedUSD.map(DurationFormatter.money) ?? "--"
        costText = "\(amount) \(l10n.text(.apiEquivalent)) · \(Self.compactNumber(summary.totals.totalTokens)) \(l10n.text(.tokens)) · \(sourceText(summary.source))"
        costSubtitle = costSubtitle(for: summary, now: now)
        costLines = [
            DetailLine(title: l10n.text(.estimatedAPICost), value: amount),
            DetailLine(title: l10n.text(.tokens), value: Self.compactNumber(summary.totals.totalTokens)),
            DetailLine(title: l10n.text(.inputCachedOutput), value: "\(Self.compactNumber(summary.totals.uncachedInputTokens)) / \(Self.compactNumber(summary.totals.cachedInputTokens)) / \(Self.compactNumber(summary.totals.outputTokens))"),
            DetailLine(title: l10n.text(.turns), value: "\(summary.totals.turns)"),
            DetailLine(title: l10n.text(.apiCostSource), value: sourceText(summary.source)),
            DetailLine(title: l10n.text(.pricingVersion), value: summary.pricingVersion),
        ]
        if summary.source == .onlineAnalytics {
            costLines.append(DetailLine(title: l10n.text(.rawAnalyticsCredits), value: Self.creditText(summary.rawCredits)))
        }
        if let costScanNote {
            costLines.append(DetailLine(title: l10n.text(.costScanFailed), value: costScanNote))
        }
    }

    private func clearCost(_ text: String) {
        latestCost = nil
        costDetail = nil
        costScanNote = nil
        costText = text
        costSubtitle = ""
        costLines = [DetailLine(title: l10n.text(.apiCost), value: text)]
    }

    private func cacheCost(_ summary: ApiEquivalentSummary) {
        guard summary.isDisplayableCost else { return }
        try? costCacheStore.save(summary)
    }

    private func noteCostScanFailure(_ text: String) {
        guard let latestCost else { return }
        costScanNote = text
        applyCost(latestCost, clearsScanNote: false)
    }

    private func costSubtitle(for summary: ApiEquivalentSummary, now: Date) -> String {
        let pricing = summary.confidence == .tokensOnly ? l10n.text(.tokensOnly) : l10n.text(.apiTokenPricing)
        let calculated = DurationFormatter.relativePast(since: summary.calculatedAt, now: now, language: l10n.language)
        return "\(l10n.text(.weeklyUsage)) · \(pricing) · \(summary.totals.turns) \(l10n.text(.turns)) · \(l10n.text(.calculatedAt)) \(calculated)"
    }

    private func windowText(_ window: RateWindow, now: Date) -> String {
        let reset = window.resetsAt.map { " · \(l10n.text(.resetsIn)) \(duration($0.timeIntervalSince(now)))" } ?? ""
        return "\(window.usedPercent)% \(l10n.text(.used))\(reset)"
    }

    private func quotaMeters(from quota: QuotaSnapshot) -> [QuotaMeter] {
        var meters = [
            QuotaMeter(title: l10n.text(.fiveHourUsage), window: quota.primary, now: quota.updatedAt, markerPercents: [20, 50, 80]),
        ]
        if let secondary = quota.secondary {
            meters.append(QuotaMeter(title: l10n.text(.weeklyUsage), window: secondary, now: quota.updatedAt, markerPercents: [20, 50, 80]))
        }
        meters.append(contentsOf: quota.additionalWindows.map {
            QuotaMeter(title: $0.name, window: $0.window, now: quota.updatedAt, markerPercents: [20, 50, 80])
        })
        return meters
    }

    private func localizedStatus(_ status: String) -> String {
        switch status {
        case "available":
            return l10n.text(.statusAvailable)
        case "used":
            return l10n.text(.statusUsed)
        default:
            return l10n.text(.statusUnknown)
        }
    }

    private func resetCreditState(_ credit: ResetCredit) -> ResetCreditState {
        guard credit.status == "available" else { return .unavailable }
        guard credit.expiresAt != nil else { return .available }
        if credit.remainingSeconds <= 7 * 24 * 3_600 { return .expiring }
        return .available
    }

    private func menuBarText(for quota: QuotaSnapshot, now: Date) -> String {
        guard let reset = quota.primary.resetsAt else {
            return quota.primary.usedPercent >= 100 ? l10n.text(.statusWait) : "\(quota.primary.usedPercent)%"
        }
        let text = duration(reset.timeIntervalSince(now), includeSeconds: false)
        return quota.primary.usedPercent >= 100 ? "\(l10n.text(.statusWait)) \(text)" : text
    }

    private func duration(_ seconds: TimeInterval, includeSeconds: Bool = true) -> String {
        DurationFormatter.localized(seconds, language: l10n.language, includeSeconds: includeSeconds)
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func apiDateString(_ date: Date) -> String {
        apiDateFormatter.string(from: date)
    }

    private static func displayDateString(_ value: String) -> String {
        guard let date = apiDateFormatter.date(from: value) else { return value }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func creditText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func sourceText(_ source: ApiEquivalentSource) -> String {
        switch source {
        case .localSessions:
            return l10n.text(.sourceLocalSessions)
        case .onlineAnalytics:
            return l10n.text(.sourceOnlineSupplement)
        case .unavailable:
            return l10n.text(.usageAnalyticsUnavailable)
        }
    }

    private static func compactNumber(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.2fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
