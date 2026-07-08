import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("API cost ranges")
struct ApiCostRangeTests {
    @Test("current cycle uses the summary window")
    func currentCycleUsesSummaryWindow() {
        let window = DateInterval(
            start: Self.date("2026-06-24T00:00:00Z"),
            end: Self.date("2026-07-01T00:00:00Z"))
        let summary = Self.summary(window: window)

        let range = ApiCostRange.currentCycle(from: summary, calendar: Self.utcCalendar)

        #expect(range.window == window)
        #expect(range.apiStartDate == "2026-06-24")
        #expect(range.apiEndDate == "2026-07-01")
    }

    @Test("previous cycle uses the same duration before the current cycle")
    func previousCycleUsesSameDuration() {
        let window = DateInterval(
            start: Self.date("2026-06-24T00:00:00Z"),
            end: Self.date("2026-07-01T00:00:00Z"))
        let summary = Self.summary(window: window)

        let range = ApiCostRange.previousCycle(from: summary, calendar: Self.utcCalendar)

        #expect(range.window.start == Self.date("2026-06-17T00:00:00Z"))
        #expect(range.window.end == Self.date("2026-06-24T00:00:00Z"))
        #expect(range.apiStartDate == "2026-06-17")
        #expect(range.apiEndDate == "2026-06-24")
    }

    @Test("previous cycle can use an explicit full current cycle window")
    func previousCycleUsesExplicitCurrentCycleWindow() {
        let currentWindow = DateInterval(
            start: Self.date("2026-06-24T00:00:00Z"),
            end: Self.date("2026-07-01T00:00:00Z"))

        let range = ApiCostRange.previousCycle(from: currentWindow, calendar: Self.utcCalendar)

        #expect(range.window.start == Self.date("2026-06-17T00:00:00Z"))
        #expect(range.window.end == Self.date("2026-06-24T00:00:00Z"))
        #expect(range.apiStartDate == "2026-06-17")
        #expect(range.apiEndDate == "2026-06-24")
    }

    @Test("this month starts at the local first day")
    func thisMonthUsesLocalCalendarMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Self.date("2026-06-30T06:03:12Z")

        let range = ApiCostRange.thisMonth(now: now, calendar: calendar)

        #expect(range.window.start == Self.date("2026-05-31T16:00:00Z"))
        #expect(range.window.end == now)
        #expect(range.apiStartDate == "2026-06-01")
        #expect(range.apiEndDate == "2026-06-30")
    }

    @Test("today starts at the local day")
    func todayUsesLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Self.date("2026-06-30T06:03:12Z")

        let range = ApiCostRange.today(now: now, calendar: calendar)

        #expect(range.window.start == Self.date("2026-06-29T16:00:00Z"))
        #expect(range.window.end == now)
        #expect(range.apiStartDate == "2026-06-30")
        #expect(range.apiEndDate == "2026-06-30")
    }

    @Test("custom range includes full start and end days")
    func customRangeIncludesWholeDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let range = try #require(ApiCostRange.custom(
            start: Self.date("2026-06-10T23:30:00Z"),
            end: Self.date("2026-06-12T01:00:00Z"),
            calendar: calendar))

        #expect(range.window.start == Self.date("2026-06-10T16:00:00Z"))
        #expect(range.window.end == Self.date("2026-06-12T16:00:00Z"))
        #expect(range.apiStartDate == "2026-06-11")
        #expect(range.apiEndDate == "2026-06-12")
    }

    @Test("custom range rejects start after end")
    func customRangeRejectsStartAfterEnd() {
        let range = ApiCostRange.custom(
            start: Self.date("2026-06-12T00:00:00Z"),
            end: Self.date("2026-06-11T00:00:00Z"),
            calendar: Self.utcCalendar)

        #expect(range == nil)
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func summary(window: DateInterval) -> ApiEquivalentSummary {
        ApiEquivalentSummary(
            source: .localSessions,
            confidence: .priced,
            window: window,
            estimatedUSD: 1,
            totals: ApiEquivalentTotals(
                totalTokens: 1,
                uncachedInputTokens: 1,
                cachedInputTokens: 0,
                outputTokens: 0,
                turns: 1,
                threads: 1),
            dailyRows: [],
            modelRows: [],
            clientRows: [],
            rawCredits: 0,
            warnings: [],
            pricingVersion: "test",
            calculatedAt: window.end)
    }
}
