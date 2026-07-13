import Foundation
import Testing
@testable import CodexRunway
@testable import CodexRunwayCore

@Suite("Runway model refresh")
@MainActor
struct RunwayModelRefreshTests {
    @Test("full refresh starts independent popover sections without waiting for API cost")
    func fullRefreshStartsIndependentSectionsWithoutWaitingForAPICost() async throws {
        let recorder = RefreshEventRecorder()
        let settings = RunwaySettings(store: PreferencesStore(defaults: scopedDefaults()))
        settings.updateShowsCostSummary(true)
        settings.updateShowsSessionRepairSummary(true)
        settings.updateShowsRecentSessions(true)

        let quota = Self.quotaSnapshot()
        let services = RunwayModelServices(
            loadValidAuth: { _, _ in Self.auth() },
            fetchQuota: { _ in
                await recorder.record("quota-start")
                try await Task.sleep(for: .milliseconds(20))
                await recorder.record("quota-finish")
                return quota
            },
            fetchResetCredits: { _ in
                await recorder.record("reset-start")
                try await Task.sleep(for: .milliseconds(220))
                await recorder.record("reset-finish")
                return ResetCreditsSnapshot(availableCount: 0, credits: [], updatedAt: Date())
            },
            scanAPIEquivalent: { window, now in
                await recorder.record("cost-start")
                try await Task.sleep(for: .milliseconds(160))
                await recorder.record("cost-finish")
                return Self.costSummary(window: window, calculatedAt: now)
            },
            fetchDailyWorkspaceUsage: { _, _, _, window, now in
                Self.costSummary(window: window, calculatedAt: now)
            },
            dryRunSessions: {
                await recorder.record("repair-start")
                return SessionRepairReport(
                    missingIndexIDs: [],
                    orphanIndexIDs: [],
                    duplicateIndexIDs: [],
                    staleTitleIDs: [],
                    backupPath: nil,
                    plannedEntries: 0)
            },
            scanRecentSessions: { _ in
                await recorder.record("recent-start")
                return SessionActivitySummary(items: [])
            })
        let model = RunwayModel(settings: settings, services: services)

        model.refresh()
        try await recorder.waitFor("cost-finish")
        try await recorder.waitFor("reset-finish")

        let events = await recorder.events
        let repairStart = try #require(events.firstIndex(of: "repair-start"))
        let recentStart = try #require(events.firstIndex(of: "recent-start"))
        let costStart = try #require(events.firstIndex(of: "cost-start"))
        let costFinish = try #require(events.firstIndex(of: "cost-finish"))
        let resetFinish = try #require(events.firstIndex(of: "reset-finish"))
        #expect(events.filter { $0 == "quota-start" }.count == 1)
        #expect(repairStart < costFinish)
        #expect(recentStart < costFinish)
        #expect(costStart < resetFinish)
    }

    @Test("default API cost summary scans today's range")
    func defaultAPICostSummaryScansToday() async throws {
        let recorder = CostRangeRecorder()
        let settings = RunwaySettings(store: PreferencesStore(defaults: scopedDefaults()))
        settings.updateShowsCostSummary(true)
        let services = Self.costRangeServices(recorder: recorder)
        let model = RunwayModel(settings: settings, services: services)

        model.refreshCost()

        let captured = try await recorder.waitForWindow(count: 2)
        let calendar = Calendar.autoupdatingCurrent
        #expect(captured.window.start == calendar.startOfDay(for: captured.now))
        #expect(captured.window.end == captured.now)
    }

    @Test("current cycle API cost summary scans elapsed quota weekly range")
    func currentCycleAPICostSummaryScansQuotaWindow() async throws {
        let recorder = CostRangeRecorder()
        let settings = RunwaySettings(store: PreferencesStore(defaults: scopedDefaults()))
        settings.updateApiCostSummaryRange(.current)
        let quota = Self.quotaSnapshot(secondaryReset: Date().addingTimeInterval(10_080 * 60))
        let services = Self.costRangeServices(quota: quota, recorder: recorder)
        let model = RunwayModel(settings: settings, services: services)

        model.refreshCost()

        let captured = try await recorder.waitForWindow()
        let secondary = try #require(quota.secondary)
        let reset = try #require(secondary.resetsAt)
        let minutes = try #require(secondary.windowMinutes)
        #expect(captured.window.start == reset.addingTimeInterval(-TimeInterval(minutes * 60)))
        #expect(captured.window.end == captured.now)
    }

    @Test("previous cycle API cost summary scans the full previous quota weekly range")
    func previousCycleAPICostSummaryScansFullPreviousQuotaWindow() async throws {
        let recorder = CostRangeRecorder()
        let settings = RunwaySettings(store: PreferencesStore(defaults: scopedDefaults()))
        settings.updateApiCostSummaryRange(.previous)
        let quota = Self.quotaSnapshot(secondaryReset: Date().addingTimeInterval(10_080 * 60))
        let services = Self.costRangeServices(quota: quota, recorder: recorder)
        let model = RunwayModel(settings: settings, services: services)

        model.refreshCost()

        let captured = try await recorder.waitForWindow(count: 2)
        let secondary = try #require(quota.secondary)
        let reset = try #require(secondary.resetsAt)
        let minutes = try #require(secondary.windowMinutes)
        let duration = TimeInterval(minutes * 60)
        let cycleStart = reset.addingTimeInterval(-duration)
        #expect(captured.window.start == cycleStart.addingTimeInterval(-duration))
        #expect(captured.window.end == cycleStart)
    }

    @Test("API cost summary hides bad analytics response for unavailable selected range")
    func apiCostSummaryHidesBadAnalyticsResponseForUnavailableRange() async throws {
        let recorder = CostRangeRecorder()
        let settings = RunwaySettings(store: PreferencesStore(defaults: scopedDefaults()))
        settings.updateShowsCostSummary(true)
        settings.updateApiCostSummaryRange(.current)
        let quota = Self.quotaSnapshot()
        let secondary = try #require(quota.secondary)
        let reset = try #require(secondary.resetsAt)
        let minutes = try #require(secondary.windowMinutes)
        let currentStart = reset.addingTimeInterval(-TimeInterval(minutes * 60))
        let services = RunwayModelServices(
            loadValidAuth: { _, _ in Self.auth() },
            fetchQuota: { _ in quota },
            fetchResetCredits: { _ in ResetCreditsSnapshot(availableCount: 0, credits: [], updatedAt: Date()) },
            scanAPIEquivalent: { window, now in
                await recorder.record(window: window, now: now)
                if window.start == currentStart {
                    return Self.costSummary(window: window, calculatedAt: now)
                }
                return ApiEquivalentSummary.unavailable(window: window, calculatedAt: now)
            },
            fetchDailyWorkspaceUsage: { _, _, _, _, _ in
                throw URLError(.badServerResponse)
            },
            dryRunSessions: {
                SessionRepairReport(
                    missingIndexIDs: [],
                    orphanIndexIDs: [],
                    duplicateIndexIDs: [],
                    staleTitleIDs: [],
                    backupPath: nil,
                    plannedEntries: 0)
            },
            scanRecentSessions: { _ in SessionActivitySummary(items: []) })
        let model = RunwayModel(settings: settings, services: services)

        model.refreshCost()
        _ = try await recorder.waitForWindow()
        for _ in 0..<100 {
            if model.costText.contains("$1") { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        settings.updateApiCostSummaryRange(.today)
        model.refreshCost()
        _ = try await recorder.waitForWindow(count: 3)
        let unavailable = settings.l10n.text(.usageAnalyticsUnavailable)
        for _ in 0..<100 {
            if model.costText == unavailable { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        let lineText = model.costLines.map(\.value).joined(separator: " ")
        #expect(model.costText == unavailable)
        #expect(model.costScanNote == nil)
        #expect(!model.costText.contains("$1"))
        #expect(!lineText.contains("NSURLErrorDomain"))
        #expect(!lineText.contains("-1011"))
    }

    @Test("quota labels follow the primary window duration")
    func quotaLabelsFollowPrimaryWindowDuration() async throws {
        let weekly = Self.quotaSnapshot(primaryMinutes: 10_080)
        let weeklySettings = RunwaySettings(store: PreferencesStore(defaults: scopedDefaults()))
        let weeklyModel = RunwayModel(
            settings: weeklySettings,
            services: Self.costRangeServices(quota: weekly, recorder: CostRangeRecorder()))

        weeklyModel.refreshQuota()
        try await waitForQuota(in: weeklyModel)

        #expect(weeklyModel.quotaText.contains(weeklySettings.l10n.text(.weeklyUsage)))
        #expect(!weeklyModel.quotaText.contains(weeklySettings.l10n.text(.fiveHourUsage)))
        #expect(weeklyModel.quotaLines[1].title == weeklySettings.l10n.text(.weeklyUsage))
        #expect(weeklyModel.quotaMeters.first?.title == weeklySettings.l10n.text(.weeklyUsage))

        let fiveHour = Self.quotaSnapshot(primaryMinutes: 300)
        let fiveHourSettings = RunwaySettings(store: PreferencesStore(defaults: scopedDefaults()))
        let fiveHourModel = RunwayModel(
            settings: fiveHourSettings,
            services: Self.costRangeServices(quota: fiveHour, recorder: CostRangeRecorder()))

        fiveHourModel.refreshQuota()
        try await waitForQuota(in: fiveHourModel)

        #expect(fiveHourModel.quotaText.contains(fiveHourSettings.l10n.text(.fiveHourUsage)))
        #expect(fiveHourModel.quotaLines[1].title == fiveHourSettings.l10n.text(.fiveHourUsage))
        #expect(fiveHourModel.quotaMeters.first?.title == fiveHourSettings.l10n.text(.fiveHourUsage))
    }

    private func scopedDefaults() -> UserDefaults {
        let suite = "codex-runway-refresh-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitForQuota(in model: RunwayModel) async throws {
        for _ in 0..<100 {
            if !model.quotaMeters.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for quota refresh")
    }

    nonisolated private static func quotaSnapshot(primaryMinutes: Int = 300, secondaryReset: Date? = nil) -> QuotaSnapshot {
        let now = Date(timeIntervalSince1970: 1_782_710_000)
        return QuotaSnapshot(
            plan: "pro",
            primary: RateWindow(usedPercent: 20, windowMinutes: primaryMinutes, resetsAt: now.addingTimeInterval(3_600)),
            secondary: RateWindow(usedPercent: 30, windowMinutes: 10_080, resetsAt: secondaryReset ?? now.addingTimeInterval(10_080 * 60)),
            additionalWindows: [],
            creditsBalance: nil,
            updatedAt: now)
    }

    nonisolated private static func auth() -> CodexAuth {
        CodexAuth(
            authMode: "chatgpt",
            tokens: .init(accessToken: "token", refreshToken: "refresh", accountId: "acct"),
            lastRefresh: nil)
    }

    nonisolated private static func costRangeServices(
        quota: QuotaSnapshot = quotaSnapshot(),
        recorder: CostRangeRecorder) -> RunwayModelServices
    {
        RunwayModelServices(
            loadValidAuth: { _, _ in Self.auth() },
            fetchQuota: { _ in quota },
            fetchResetCredits: { _ in ResetCreditsSnapshot(availableCount: 0, credits: [], updatedAt: Date()) },
            scanAPIEquivalent: { window, now in
                await recorder.record(window: window, now: now)
                return Self.costSummary(window: window, calculatedAt: now)
            },
            fetchDailyWorkspaceUsage: { _, _, _, window, now in
                Self.costSummary(window: window, calculatedAt: now)
            },
            dryRunSessions: {
                SessionRepairReport(
                    missingIndexIDs: [],
                    orphanIndexIDs: [],
                    duplicateIndexIDs: [],
                    staleTitleIDs: [],
                    backupPath: nil,
                    plannedEntries: 0)
            },
            scanRecentSessions: { _ in SessionActivitySummary(items: []) })
    }

    nonisolated private static func costSummary(window: DateInterval, calculatedAt: Date) -> ApiEquivalentSummary {
        ApiEquivalentSummary(
            source: .localSessions,
            confidence: .priced,
            window: window,
            estimatedUSD: 1,
            totals: ApiEquivalentTotals(
                totalTokens: 10,
                uncachedInputTokens: 5,
                cachedInputTokens: 2,
                outputTokens: 3,
                turns: 1,
                threads: 1),
            dailyRows: [],
            modelRows: [],
            clientRows: [],
            rawCredits: 0,
            warnings: [],
            pricingVersion: "test",
            calculatedAt: calculatedAt)
    }
}

private actor CostRangeRecorder {
    private var captures: [(window: DateInterval, now: Date)] = []

    func record(window: DateInterval, now: Date) {
        captures.append((window, now))
    }

    func waitForWindow(count: Int = 1) async throws -> (window: DateInterval, now: Date) {
        for _ in 0..<100 {
            if captures.count >= count, let captured = captures.last { return captured }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for API cost range")
        throw CancellationError()
    }
}

private actor RefreshEventRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func waitFor(_ event: String) async throws {
        for _ in 0..<100 {
            if events.contains(event) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for \(event); events: \(events)")
    }
}
