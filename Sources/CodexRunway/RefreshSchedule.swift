import Foundation

struct RefreshSchedule: Sendable {
    private var deadline = Date.distantFuture
    private var latestCompletion: Date?
    private var isRefreshInFlight = false

    mutating func refreshStarted() {
        isRefreshInFlight = true
        deadline = .distantFuture
    }

    mutating func refreshCompleted(at completion: Date, interval: TimeInterval) {
        isRefreshInFlight = false
        latestCompletion = completion
        deadline = completion.addingTimeInterval(interval)
    }

    mutating func intervalChanged(to interval: TimeInterval, now: Date) {
        guard !isRefreshInFlight else { return }
        deadline = (latestCompletion ?? now).addingTimeInterval(interval)
    }

    func isDue(at now: Date) -> Bool {
        !isRefreshInFlight && now >= deadline
    }
}
