import Foundation

public struct RunwayStatusWindow: Codable, Sendable, Equatable {
    public var name: String
    public var usedPercent: Int
    public var resetsAt: Date?
}

public struct RunwayStatusQuota: Codable, Sendable, Equatable {
    public var plan: String?
    public var primary: RunwayStatusWindow
    public var secondary: RunwayStatusWindow?
    public var additionalWindows: [RunwayStatusWindow]
    public var creditsBalance: Double?
    public var updatedAt: Date

    public init(snapshot: QuotaSnapshot) {
        self.plan = snapshot.plan
        self.primary = RunwayStatusWindow(name: "5-hour", usedPercent: snapshot.primary.usedPercent, resetsAt: snapshot.primary.resetsAt)
        self.secondary = snapshot.secondary.map { RunwayStatusWindow(name: "Weekly", usedPercent: $0.usedPercent, resetsAt: $0.resetsAt) }
        self.additionalWindows = snapshot.additionalWindows.map {
            RunwayStatusWindow(name: $0.name, usedPercent: $0.window.usedPercent, resetsAt: $0.window.resetsAt)
        }
        self.creditsBalance = snapshot.creditsBalance
        self.updatedAt = snapshot.updatedAt
    }
}

public struct RunwayStatusSnapshot: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var quota: RunwayStatusQuota?
    public var cost: ApiEquivalentSummary?
    public var sessions: SessionActivitySummary?

    public init(
        generatedAt: Date = Date(),
        quota: RunwayStatusQuota?,
        cost: ApiEquivalentSummary?,
        sessions: SessionActivitySummary?)
    {
        self.generatedAt = generatedAt
        self.quota = quota
        self.cost = cost
        self.sessions = sessions
    }
}

public struct RunwayStatusExporter: Sendable {
    public var statusURL: URL

    public init(statusURL: URL = Self.defaultStatusURL) {
        self.statusURL = statusURL
    }

    public func save(_ snapshot: RunwayStatusSnapshot) throws {
        try FileManager.default.createDirectory(
            at: statusURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: statusURL, options: .atomic)
    }

    public static var defaultStatusURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-runway", isDirectory: true)
            .appendingPathComponent("status.json")
    }
}
