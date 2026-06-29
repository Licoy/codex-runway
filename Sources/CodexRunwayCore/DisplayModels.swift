import Foundation

public enum QuotaHealth: Sendable, Equatable {
    case green
    case yellow
    case red
}

public struct QuotaMeter: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public var title: String
    public var remainingPercent: Int
    public var usedPercent: Int
    public var resetsAt: Date?
    public var resetText: String?
    public var health: QuotaHealth
    public var markerPercents: [Int]

    public init(title: String, window: RateWindow, now: Date = Date(), markerPercents: [Int] = []) {
        self.title = title
        self.usedPercent = max(0, min(100, window.usedPercent))
        self.remainingPercent = max(0, 100 - usedPercent)
        self.resetsAt = window.resetsAt
        self.resetText = window.resetsAt.map {
            DurationFormatter.localized($0.timeIntervalSince(now), language: .english, includeSeconds: false)
        }
        self.health = Self.health(forUsedPercent: usedPercent)
        self.markerPercents = markerPercents
    }

    public static func health(forUsedPercent usedPercent: Int) -> QuotaHealth {
        let remaining = max(0, 100 - usedPercent)
        if remaining >= 50 { return .green }
        if remaining >= 20 { return .yellow }
        return .red
    }
}

public struct ResetCreditSummary: Sendable, Equatable {
    public static let expiringThreshold: TimeInterval = 7 * 24 * 3_600

    public var availableCount: Int
    public var stableAvailableCount: Int
    public var expiringCount: Int
    public var unavailableCount: Int
    public var totalCount: Int
    public var totalRemainingDuration: TimeInterval
    public var nextExpiryDate: Date?
    public var nextExpiryRemaining: TimeInterval?
    public var updatedAt: Date

    public init(snapshot: ResetCreditsSnapshot) {
        let available = snapshot.credits.filter { $0.status == "available" }
        let risks = snapshot.credits.map { ResetCreditRisk.classify($0) }
        self.availableCount = snapshot.availableCount
        self.stableAvailableCount = risks.filter { $0 == .available }.count
        self.expiringCount = risks.filter { $0 == .expiring }.count
        self.unavailableCount = risks.filter { $0 == .unavailable }.count
        self.totalCount = snapshot.credits.count
        self.totalRemainingDuration = available.reduce(TimeInterval(0)) { $0 + $1.remainingSeconds }
        let next = available.compactMap { credit -> (Date, TimeInterval)? in
            guard let expiry = credit.expiresAt else { return nil }
            return (expiry, credit.remainingSeconds)
        }.min { $0.0 < $1.0 }
        self.nextExpiryDate = next?.0
        self.nextExpiryRemaining = next?.1
        self.updatedAt = snapshot.updatedAt
    }

    public static func sortedByExpiry(_ credits: [ResetCredit]) -> [ResetCredit] {
        credits.sorted { lhs, rhs in
            switch (lhs.expiresAt, rhs.expiresAt) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return (lhs.id ?? "") < (rhs.id ?? "")
            }
        }
    }
}

public enum ResetCreditRisk: Sendable, Equatable {
    case available
    case expiring
    case unavailable

    public static func classify(
        _ credit: ResetCredit,
        expiringThreshold: TimeInterval = ResetCreditSummary.expiringThreshold)
        -> ResetCreditRisk
    {
        guard credit.status == "available" else { return .unavailable }
        guard credit.expiresAt != nil else { return .available }
        return credit.remainingSeconds <= expiringThreshold ? .expiring : .available
    }
}

public struct UsageCostDetail: Sendable, Equatable {
    public struct ModelLine: Sendable, Equatable, Identifiable {
        public var id: String { model }
        public var model: String
        public var usage: TokenUsage
        public var estimatedUSD: Decimal
        public var costShare: Double
    }

    public var estimatedUSD: Decimal
    public var pricingVersion: String
    public var uncachedInputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var models: [ModelLine]

    public init(summary: UsageCostSummary) {
        estimatedUSD = summary.estimatedUSD
        pricingVersion = summary.pricingVersion
        uncachedInputTokens = max(0, summary.totals.inputTokens - summary.totals.cachedInputTokens)
        cachedInputTokens = summary.totals.cachedInputTokens
        outputTokens = summary.totals.outputTokens
        totalTokens = uncachedInputTokens + cachedInputTokens + outputTokens
        let unknown = Set(summary.unknownModels)
        let total = NSDecimalNumber(decimal: summary.estimatedUSD).doubleValue
        models = summary.modelBreakdown
            .filter { !unknown.contains($0.model) }
            .map { line in
                let cost = NSDecimalNumber(decimal: line.estimatedUSD).doubleValue
                let share = total > 0 ? max(0, min(1, cost / total)) : 0
                return ModelLine(model: line.model, usage: line.usage, estimatedUSD: line.estimatedUSD, costShare: share)
            }
    }
}
