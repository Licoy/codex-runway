import Foundation

public struct ApiCostRange: Sendable, Equatable {
    public var window: DateInterval
    public var apiStartDate: String
    public var apiEndDate: String

    public init(window: DateInterval, apiStartDate: String, apiEndDate: String) {
        self.window = window
        self.apiStartDate = apiStartDate
        self.apiEndDate = apiEndDate
    }

    public static func currentCycle(
        from summary: ApiEquivalentSummary,
        calendar: Calendar = .autoupdatingCurrent) -> ApiCostRange
    {
        range(window: summary.window, calendar: calendar)
    }

    public static func range(
        window: DateInterval,
        calendar: Calendar = .autoupdatingCurrent) -> ApiCostRange
    {
        make(window: window, calendar: calendar)
    }

    public static func previousCycle(
        from summary: ApiEquivalentSummary,
        calendar: Calendar = .autoupdatingCurrent) -> ApiCostRange
    {
        previousCycle(from: summary.window, calendar: calendar)
    }

    public static func previousCycle(
        from window: DateInterval,
        calendar: Calendar = .autoupdatingCurrent) -> ApiCostRange
    {
        let duration = window.duration
        let previous = DateInterval(
            start: window.start.addingTimeInterval(-duration),
            end: window.start)
        return make(window: previous, calendar: calendar)
    }

    public static func thisMonth(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent) -> ApiCostRange
    {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        return make(window: DateInterval(start: start, end: now), calendar: calendar)
    }

    public static func today(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent) -> ApiCostRange
    {
        make(window: DateInterval(start: calendar.startOfDay(for: now), end: now), calendar: calendar)
    }

    public static func custom(
        start: Date,
        end: Date,
        calendar: Calendar = .autoupdatingCurrent) -> ApiCostRange?
    {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay <= endDay,
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay)
        else { return nil }
        return ApiCostRange(
            window: DateInterval(start: startDay, end: endExclusive),
            apiStartDate: dayString(startDay, calendar: calendar),
            apiEndDate: dayString(endDay, calendar: calendar))
    }

    private static func make(window: DateInterval, calendar: Calendar) -> ApiCostRange {
        // DateInterval is half-open [start, end). When `end` lands on a day boundary,
        // the last included instant is the previous calendar day for API inclusive dates.
        let endInclusive = inclusiveEndDate(for: window, calendar: calendar)
        return ApiCostRange(
            window: window,
            apiStartDate: dayString(window.start, calendar: calendar),
            apiEndDate: dayString(endInclusive, calendar: calendar))
    }

    private static func inclusiveEndDate(for window: DateInterval, calendar: Calendar) -> Date {
        guard window.duration > 0 else { return window.start }
        let end = window.end
        if calendar.startOfDay(for: end) == end {
            return end.addingTimeInterval(-1)
        }
        return end
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
