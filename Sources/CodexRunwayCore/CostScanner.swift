import Foundation

public struct UsageCostScanner: Sendable {
    public var codexHome: URL

    public init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexHome = codexHome
    }

    public func scan(window: DateInterval) throws -> UsageCostSummary {
        var byModel: [String: TokenUsage] = [:]
        var unknown = Set<String>()
        for file in jsonlFiles(window: window) {
            try scan(file: file, window: window, byModel: &byModel, unknown: &unknown)
        }
        let breakdown = byModel.keys.sorted().map { model in
            let usage = byModel[model] ?? .zero
            let cost = PricingTable.cost(model: model, usage: usage)
            if cost == nil { unknown.insert(model) }
            return ModelCostBreakdown(model: model, usage: usage, estimatedUSD: cost ?? 0)
        }
        return UsageCostSummary(
            window: window,
            totals: byModel.values.reduce(.zero, +),
            modelBreakdown: breakdown,
            estimatedUSD: breakdown.reduce(Decimal(0)) { $0 + $1.estimatedUSD },
            pricingVersion: PricingTable.version,
            unknownModels: unknown.sorted())
    }

    public func scanAPIEquivalent(window: DateInterval) throws -> ApiEquivalentSummary {
        var byModel: [String: ApiEquivalentTotals] = [:]
        var byDay: [String: ApiEquivalentTotals] = [:]
        var byDayModel: [String: [String: ApiEquivalentTotals]] = [:]
        var unknown = Set<String>()
        for file in jsonlFiles(window: window) {
            try scanAPIEquivalent(
                file: file,
                window: window,
                byModel: &byModel,
                byDay: &byDay,
                byDayModel: &byDayModel,
                unknown: &unknown)
        }
        let modelRows = byModel.keys.sorted().map { model in
            let totals = byModel[model] ?? .zero
            let estimated = PricingTable.cost(model: model, totals: totals) ?? PricingTable.equivalentCost(totals: totals)
            return ApiEquivalentBreakdownRow(name: model, totals: totals, estimatedUSD: estimated, rawCredits: 0)
        }
        let dailyRows = byDay.keys.sorted().map { day in
            let totals = byDay[day] ?? .zero
            return ApiEquivalentDailyRow(
                date: day,
                totals: totals,
                estimatedUSD: Self.estimatedCost(byModel: byDayModel[day] ?? [:]),
                rawCredits: 0)
        }
        let totals = byDay.values.reduce(.zero, +)
        return ApiEquivalentSummary(
            source: totals.totalTokens > 0 ? .localSessions : .unavailable,
            confidence: totals.totalTokens > 0 ? .priced : .unavailable,
            window: window,
            estimatedUSD: modelRows.compactMap(\.estimatedUSD).reduce(Decimal(0), +),
            totals: totals,
            dailyRows: dailyRows,
            modelRows: modelRows,
            clientRows: [],
            rawCredits: 0,
            warnings: unknown.sorted().map { "unknown-model:\($0)" },
            pricingVersion: PricingTable.version)
    }

    private func scan(
        file: URL,
        window: DateInterval,
        byModel: inout [String: TokenUsage],
        unknown: inout Set<String>) throws
    {
        let text = try String(contentsOf: file)
        var currentModel = "unknown-model"
        for line in text.split(separator: "\n") {
            guard let record = try? JSONLineRecord.parse(String(line)),
                  window.contains(record.timestamp)
            else { continue }
            if let contextModel = record.contextModel {
                currentModel = contextModel
            }
            guard let usage = record.lastTokenUsage else { continue }
            let model = record.model ?? currentModel
            byModel[model, default: .zero] = byModel[model, default: .zero] + usage
            if PricingTable.price(for: model) == nil { unknown.insert(model) }
        }
    }

    private func scanAPIEquivalent(
        file: URL,
        window: DateInterval,
        byModel: inout [String: ApiEquivalentTotals],
        byDay: inout [String: ApiEquivalentTotals],
        byDayModel: inout [String: [String: ApiEquivalentTotals]],
        unknown: inout Set<String>) throws
    {
        let text = try String(contentsOf: file)
        var currentModel = "unknown-model"
        for line in text.split(separator: "\n") {
            guard let record = try? JSONLineRecord.parse(String(line)),
                  window.contains(record.timestamp)
            else { continue }
            if let contextModel = record.contextModel {
                currentModel = contextModel
            }
            guard let usage = record.lastTokenUsage else { continue }
            let model = record.model ?? currentModel
            let totals = ApiEquivalentTotals(usage: usage, turns: 1, threads: 0)
            let day = Self.dayString(record.timestamp)
            byModel[model, default: .zero] = byModel[model, default: .zero] + totals
            byDay[day, default: .zero] = byDay[day, default: .zero] + totals
            byDayModel[day, default: [:]][model, default: .zero] = byDayModel[day, default: [:]][model, default: .zero] + totals
            if PricingTable.price(for: model) == nil { unknown.insert(model) }
        }
    }

    private func jsonlFiles(window: DateInterval) -> [URL] {
        ["sessions", "archived_sessions"].flatMap { folder in
            let root = codexHome.appendingPathComponent(folder, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                return [URL]()
            }
            return enumerator.compactMap { ($0 as? URL) }
                .filter { $0.pathExtension == "jsonl" && isLikelyRelevant($0, window: window) }
        }
    }

    func isLikelyRelevant(_ file: URL, window: DateInterval) -> Bool {
        if let day = dayFromPath(file) {
            let calendar = Calendar(identifier: .gregorian)
            let padded = DateInterval(
                start: calendar.date(byAdding: .day, value: -1, to: window.start) ?? window.start,
                end: calendar.date(byAdding: .day, value: 1, to: window.end) ?? window.end)
            return padded.contains(day)
        }
        if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            return modified >= window.start.addingTimeInterval(-86_400) && modified <= window.end.addingTimeInterval(86_400)
        }
        return true
    }

    private func dayFromPath(_ file: URL) -> Date? {
        let components = file.pathComponents
        for index in 0..<(max(0, components.count - 2)) {
            guard components[index].count == 4,
                  let year = Int(components[index]),
                  let month = Int(components[index + 1]),
                  let day = Int(components[index + 2])
            else { continue }
            return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))
        }
        let name = file.lastPathComponent
        guard let match = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        return RunwayDates.parse(String(name[match]) + "T00:00:00Z")
    }

    private static func dayString(_ date: Date) -> String {
        ApiEquivalentSummary.apiDay(date)
    }

    private static func estimatedCost(byModel: [String: ApiEquivalentTotals]) -> Decimal {
        byModel.reduce(Decimal(0)) { result, item in
            result + (PricingTable.cost(model: item.key, totals: item.value) ?? PricingTable.equivalentCost(totals: item.value))
        }
    }
}

private extension ApiEquivalentTotals {
    init(usage: TokenUsage, turns: Int, threads: Int) {
        let uncached = max(0, usage.inputTokens - usage.cachedInputTokens)
        self.init(
            totalTokens: uncached + usage.cachedInputTokens + usage.outputTokens,
            uncachedInputTokens: uncached,
            cachedInputTokens: usage.cachedInputTokens,
            outputTokens: usage.outputTokens,
            turns: turns,
            threads: threads)
    }
}

struct JSONLineRecord {
    var timestamp: Date
    var model: String?
    var contextModel: String?
    var lastTokenUsage: TokenUsage?

    static func parse(_ line: String) throws -> JSONLineRecord {
        let data = Data(line.utf8)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let timestampText = object["timestamp"] as? String ?? ""
        let timestamp = RunwayDates.parse(timestampText) ?? .distantPast
        let payload = object["payload"] as? [String: Any]
        let turnContext = object["turn_context"] as? [String: Any]
        let contextModel = object["type"] as? String == "turn_context" ? payload?["model"] as? String : nil
        let model = turnContext?["model"] as? String ?? payload?["model"] as? String
        return JSONLineRecord(
            timestamp: timestamp,
            model: model,
            contextModel: contextModel,
            lastTokenUsage: tokenUsage(from: payload))
    }

    private static func tokenUsage(from payload: [String: Any]?) -> TokenUsage? {
        guard let info = payload?["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any]
        else { return nil }
        let input = usage["input_tokens"] as? Int ?? 0
        let cached = usage["cached_input_tokens"] as? Int ?? 0
        let output = (usage["output_tokens"] as? Int ?? 0) + (usage["reasoning_output_tokens"] as? Int ?? 0)
        return TokenUsage(inputTokens: input, cachedInputTokens: cached, outputTokens: output)
    }
}

public enum PricingTable {
    public static let version = "2026-06-29"

    public struct Price: Sendable {
        var inputPerMillion: Decimal
        var cachedInputPerMillion: Decimal
        var outputPerMillion: Decimal
    }

    public static func price(for model: String) -> Price? {
        let key = model.lowercased()
        if key.contains("gpt-5.3-codex") || key.contains("gpt-5.2-codex") {
            return Price(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14)
        }
        if key.contains("gpt-5.5") {
            return gpt55EquivalentPrice
        }
        if key.contains("gpt-5") {
            return Price(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10)
        }
        return nil
    }

    public static func cost(model: String, usage: TokenUsage) -> Decimal? {
        guard let price = price(for: model) else { return nil }
        return cost(usage: usage, price: price)
    }

    static func cost(model: String, totals: ApiEquivalentTotals) -> Decimal? {
        guard let price = price(for: model) else { return nil }
        return cost(totals: totals, price: price)
    }

    static func equivalentCost(totals: ApiEquivalentTotals) -> Decimal {
        cost(totals: totals, price: gpt55EquivalentPrice)
    }

    private static var gpt55EquivalentPrice: Price {
        Price(inputPerMillion: 5, cachedInputPerMillion: 0.5, outputPerMillion: 30)
    }

    private static func cost(usage: TokenUsage, price: Price) -> Decimal {
        return Decimal(usage.inputTokens - usage.cachedInputTokens) / 1_000_000 * price.inputPerMillion
            + Decimal(usage.cachedInputTokens) / 1_000_000 * price.cachedInputPerMillion
            + Decimal(usage.outputTokens) / 1_000_000 * price.outputPerMillion
    }

    private static func cost(totals: ApiEquivalentTotals, price: Price) -> Decimal {
        Decimal(totals.uncachedInputTokens) / 1_000_000 * price.inputPerMillion
            + Decimal(totals.cachedInputTokens) / 1_000_000 * price.cachedInputPerMillion
            + Decimal(totals.outputTokens) / 1_000_000 * price.outputPerMillion
    }
}
