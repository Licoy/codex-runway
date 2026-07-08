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
        ApiCostRange(
            window: window,
            apiStartDate: dayString(window.start, calendar: calendar),
            apiEndDate: dayString(window.end, calendar: calendar))
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
