import Foundation

public enum RunwayAlertKind: String, Codable, Sendable, Equatable {
    case quota
    case resetCredit
}

public struct RunwayAlert: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: RunwayAlertKind
    public var name: String
    public var threshold: Int?
    public var date: Date?
}

public enum RunwayAlertDecider {
    private static let quotaThresholds = [80, 95, 100]

    public static func quotaAlerts(_ snapshot: QuotaSnapshot) -> [RunwayAlert] {
        var rows = [("5-hour", snapshot.primary)]
        if let secondary = snapshot.secondary { rows.append(("Weekly", secondary)) }
        rows.append(contentsOf: snapshot.additionalWindows.map { ($0.name, $0.window) })
        return rows.compactMap { name, window in
            guard let threshold = quotaThresholds.last(where: { window.usedPercent >= $0 }) else { return nil }
            let resetID = window.resetsAt.map { Int($0.timeIntervalSince1970) } ?? 0
            return RunwayAlert(
                id: "quota:\(name):\(threshold):\(resetID)",
                kind: .quota,
                name: name,
                threshold: threshold,
                date: window.resetsAt)
        }
    }

    public static func resetCreditAlerts(_ snapshot: ResetCreditsSnapshot) -> [RunwayAlert] {
        snapshot.credits.compactMap { credit in
            guard ResetCreditRisk.classify(credit) == .expiring else { return nil }
            let expiryID = credit.expiresAt.map { Int($0.timeIntervalSince1970) } ?? 0
            let creditID = credit.id ?? "\(expiryID)"
            return RunwayAlert(
                id: "reset-credit:\(creditID):\(expiryID)",
                kind: .resetCredit,
                name: creditID,
                threshold: nil,
                date: credit.expiresAt)
        }
    }
}

public struct RunwayAlertStore: Sendable {
    public var stateURL: URL

    public init(stateURL: URL = Self.defaultStateURL) {
        self.stateURL = stateURL
    }

    public func unseen(_ alerts: [RunwayAlert]) throws -> [RunwayAlert] {
        var ids = load()
        let unseen = alerts.filter { !ids.contains($0.id) }
        guard !unseen.isEmpty else { return [] }
        unseen.forEach { ids.insert($0.id) }
        try save(ids)
        return unseen
    }

    private func load() -> Set<String> {
        guard let data = try? Data(contentsOf: stateURL),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(values)
    }

    private func save(_ ids: Set<String>) throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(ids).sorted().suffix(200))
        try data.write(to: stateURL, options: .atomic)
    }

    public static var defaultStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex-runway", isDirectory: true)
            .appendingPathComponent("alerts.json")
    }
}
