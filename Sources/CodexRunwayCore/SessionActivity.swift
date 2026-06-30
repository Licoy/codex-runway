import Foundation

enum SessionProjectName {
    static let unknown = "Unknown project"

    static func displayName(for cwd: String?) -> String {
        guard let cwd = cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty else {
            return unknown
        }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }
}

public enum SessionActivityState: String, Codable, Sendable, Equatable {
    case recent
    case needsAttention
    case failed
}

public struct SessionActivityItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var projectName: String
    public var cwd: String?
    public var updatedAt: Date
    public var state: SessionActivityState
    public var totals: ApiEquivalentTotals
    public var estimatedUSD: Decimal?

    public init(
        id: String,
        title: String,
        projectName: String,
        cwd: String?,
        updatedAt: Date,
        state: SessionActivityState,
        totals: ApiEquivalentTotals,
        estimatedUSD: Decimal?)
    {
        self.id = id
        self.title = title
        self.projectName = projectName
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.state = state
        self.totals = totals
        self.estimatedUSD = estimatedUSD
    }
}

public struct SessionActivitySummary: Codable, Sendable, Equatable {
    public var items: [SessionActivityItem]

    public init(items: [SessionActivityItem]) {
        self.items = items
    }
}

public struct SessionActivityScanner: Sendable {
    public var codexHome: URL

    public init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexHome = codexHome
    }

    public func scan(limit: Int = 5) throws -> SessionActivitySummary {
        let items = try jsonlFiles().compactMap(parseSession)
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(0, limit))
        return SessionActivitySummary(items: Array(items))
    }

    private func parseSession(_ file: URL) throws -> SessionActivityItem? {
        let text = try String(contentsOf: file)
        var id: String?
        var cwd: String?
        var title: String?
        var updatedAt: Date?
        var state = SessionActivityState.recent
        var currentModel = "unknown-model"
        var byModel: [String: ApiEquivalentTotals] = [:]
        for line in text.split(separator: "\n").map(String.init) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let payload = object["payload"] as? [String: Any]
            if let stamp = object["timestamp"] as? String, let date = RunwayDates.parse(stamp) {
                updatedAt = max(updatedAt ?? date, date)
            }
            if object["type"] as? String == "session_meta" {
                id = id ?? payload?["id"] as? String ?? payload?["session_id"] as? String
                cwd = cwd ?? payload?["cwd"] as? String
            }
            if title == nil, payload?["type"] as? String == "message", payload?["role"] as? String == "user" {
                title = sessionText(payload?["content"]).flatMap(cleanSessionTitle)
            }
            state = stronger(state, detectedState(object: object, payload: payload))
            guard let record = try? JSONLineRecord.parse(line) else { continue }
            if let contextModel = record.contextModel { currentModel = contextModel }
            guard let usage = record.lastTokenUsage else { continue }
            let model = record.model ?? currentModel
            byModel[model, default: .zero] = byModel[model, default: .zero] + ApiEquivalentTotals(usage: usage, turns: 1, threads: 0)
        }
        guard let id, let updatedAt else { return nil }
        let totals = byModel.values.reduce(.zero, +)
        return SessionActivityItem(
            id: id,
            title: title ?? "Untitled",
            projectName: SessionProjectName.displayName(for: cwd),
            cwd: cwd,
            updatedAt: updatedAt,
            state: state,
            totals: totals,
            estimatedUSD: estimatedCost(byModel))
    }

    private func jsonlFiles() -> [URL] {
        ["sessions", "archived_sessions"].flatMap { folder in
            let root = codexHome.appendingPathComponent(folder, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                return [URL]()
            }
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        }
    }

    private func estimatedCost(_ byModel: [String: ApiEquivalentTotals]) -> Decimal? {
        guard !byModel.isEmpty else { return nil }
        return byModel.reduce(Decimal(0)) { result, item in
            result + (PricingTable.cost(model: item.key, totals: item.value) ?? PricingTable.equivalentCost(totals: item.value))
        }
    }
}

private func detectedState(object: [String: Any], payload: [String: Any]?) -> SessionActivityState {
    let text = [
        object["type"] as? String,
        payload?["type"] as? String,
        payload?["status"] as? String,
    ].compactMap(\.self).joined(separator: " ").lowercased()
    if text.contains("error") || text.contains("failed") { return .failed }
    if text.contains("approval") || text.contains("permission") || text.contains("waiting") { return .needsAttention }
    return .recent
}

private func stronger(_ lhs: SessionActivityState, _ rhs: SessionActivityState) -> SessionActivityState {
    if lhs == .failed || rhs == .failed { return .failed }
    if lhs == .needsAttention || rhs == .needsAttention { return .needsAttention }
    return .recent
}

private func sessionText(_ value: Any?) -> String? {
    if let text = value as? String { return text }
    if let array = value as? [[String: Any]] {
        return array.compactMap { $0["text"] as? String }.joined(separator: " ")
    }
    return nil
}

private func cleanSessionTitle(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(80))
}
