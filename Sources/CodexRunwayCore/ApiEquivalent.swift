import Foundation

public enum ApiEquivalentSource: String, Codable, Sendable, Equatable {
    case localSessions
    case onlineAnalytics
    case unavailable
}

public enum ApiEquivalentConfidence: String, Codable, Sendable, Equatable {
    case priced
    case tokensOnly
    case unavailable
}

public struct ApiEquivalentTotals: Codable, Sendable, Equatable {
    public var totalTokens: Int
    public var uncachedInputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var turns: Int
    public var threads: Int

    public static let zero = ApiEquivalentTotals(
        totalTokens: 0,
        uncachedInputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
        turns: 0,
        threads: 0)

    public var hasTokenParts: Bool {
        uncachedInputTokens + cachedInputTokens + outputTokens > 0
    }

    public static func + (lhs: ApiEquivalentTotals, rhs: ApiEquivalentTotals) -> ApiEquivalentTotals {
        ApiEquivalentTotals(
            totalTokens: lhs.totalTokens + rhs.totalTokens,
            uncachedInputTokens: lhs.uncachedInputTokens + rhs.uncachedInputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            turns: lhs.turns + rhs.turns,
            threads: lhs.threads + rhs.threads)
    }
}

public struct ApiEquivalentDailyRow: Codable, Sendable, Equatable, Identifiable {
    public var id: String { date }
    public var date: String
    public var totals: ApiEquivalentTotals
    public var estimatedUSD: Decimal?
    public var rawCredits: Double
}

public struct ApiEquivalentBreakdownRow: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var totals: ApiEquivalentTotals
    public var estimatedUSD: Decimal?
    public var rawCredits: Double
}

public struct ApiEquivalentSummary: Codable, Sendable, Equatable {
    public var source: ApiEquivalentSource
    public var confidence: ApiEquivalentConfidence
    public var window: DateInterval
    public var estimatedUSD: Decimal?
    public var totals: ApiEquivalentTotals
    public var dailyRows: [ApiEquivalentDailyRow]
    public var modelRows: [ApiEquivalentBreakdownRow]
    public var clientRows: [ApiEquivalentBreakdownRow]
    public var rawCredits: Double
    public var warnings: [String]
    public var pricingVersion: String
    public var calculatedAt: Date

    public static func unavailable(window: DateInterval, warning: String? = nil, calculatedAt: Date = Date()) -> ApiEquivalentSummary {
        ApiEquivalentSummary(
            source: .unavailable,
            confidence: .unavailable,
            window: window,
            estimatedUSD: nil,
            totals: .zero,
            dailyRows: [],
            modelRows: [],
            clientRows: [],
            rawCredits: 0,
            warnings: warning.map { [$0] } ?? [],
            pricingVersion: PricingTable.version,
            calculatedAt: calculatedAt)
    }

    public static func decodeAnalytics(from data: Data, window: DateInterval, calculatedAt: Date = Date()) throws -> ApiEquivalentSummary {
        let response = try JSONDecoder().decode(ApiAnalyticsResponse.self, from: data)
        let start = apiDay(window.start)
        let end = apiDay(window.end)
        let items = response.data
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
        let rows = items.map { item -> ApiEquivalentDailyRow in
            let totals = item.totals?.apiTotals ?? .zero
            return ApiEquivalentDailyRow(
                date: item.date,
                totals: totals,
                estimatedUSD: totals.hasTokenParts ? PricingTable.equivalentCost(totals: totals) : nil,
                rawCredits: item.totals?.credits ?? 0)
        }
        let totals = rows.reduce(.zero) { $0 + $1.totals }
        let estimated = rows.compactMap(\.estimatedUSD).reduce(Decimal(0), +)
        return ApiEquivalentSummary(
            source: .onlineAnalytics,
            confidence: totals.hasTokenParts ? .priced : (totals.totalTokens > 0 ? .tokensOnly : .unavailable),
            window: window,
            estimatedUSD: totals.hasTokenParts ? estimated : nil,
            totals: totals,
            dailyRows: rows,
            modelRows: breakdown(items.flatMap(\.models)),
            clientRows: breakdown(items.flatMap(\.clients)),
            rawCredits: rows.reduce(0) { $0 + $1.rawCredits },
            warnings: totals.hasTokenParts ? [] : ["analytics-token-parts-missing"],
            pricingVersion: PricingTable.version,
            calculatedAt: calculatedAt)
    }

    static func apiDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func breakdown(_ items: [ApiAnalyticsBreakdownItem]) -> [ApiEquivalentBreakdownRow] {
        let grouped = Dictionary(grouping: items) { $0.displayName }
        return grouped.map { name, values in
            let totals = values.map(\.apiTotals).reduce(.zero, +)
            return ApiEquivalentBreakdownRow(
                name: name,
                totals: totals,
                estimatedUSD: totals.hasTokenParts ? PricingTable.equivalentCost(totals: totals) : nil,
                rawCredits: values.reduce(0) { $0 + $1.credits })
        }
        .filter { $0.totals.totalTokens > 0 || $0.totals.turns > 0 || $0.rawCredits > 0 }
        .sorted { $0.totals.totalTokens > $1.totals.totalTokens }
    }
}

private struct ApiAnalyticsResponse: Decodable {
    var data: [ApiAnalyticsDay]
}

private struct ApiAnalyticsDay: Decodable {
    var date: String
    var totals: ApiAnalyticsTotals?
    var models: [ApiAnalyticsBreakdownItem]
    var clients: [ApiAnalyticsBreakdownItem]

    enum CodingKeys: String, CodingKey {
        case date
        case totals
        case models
        case clients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? container.decode(String.self, forKey: .date)) ?? ""
        totals = try? container.decodeIfPresent(ApiAnalyticsTotals.self, forKey: .totals)
        models = (try? container.decodeIfPresent([ApiAnalyticsBreakdownItem].self, forKey: .models)) ?? []
        clients = (try? container.decodeIfPresent([ApiAnalyticsBreakdownItem].self, forKey: .clients)) ?? []
    }
}

private struct ApiAnalyticsBreakdownItem: Decodable {
    var clientID: String?
    var model: String?
    var name: String?
    var id: String?
    var totals: ApiAnalyticsTotals

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case model
        case name
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try? container.decodeIfPresent(String.self, forKey: .clientID)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        totals = try ApiAnalyticsTotals(from: decoder)
    }

    var displayName: String {
        firstNonEmpty(clientID, model, name, id) ?? "UNKNOWN"
    }

    var apiTotals: ApiEquivalentTotals { totals.apiTotals }
    var credits: Double { totals.credits }
}

private struct ApiAnalyticsTotals: Decodable {
    var credits: Double
    var turns: Int
    var threads: Int
    var textTotalTokens: Int
    var cachedTextInputTokens: Int
    var uncachedTextInputTokens: Int
    var textOutputTokens: Int

    enum CodingKeys: String, CodingKey {
        case credits
        case turns
        case threads
        case textTotalTokens = "text_total_tokens"
        case cachedTextInputTokens = "cached_text_input_tokens"
        case uncachedTextInputTokens = "uncached_text_input_tokens"
        case textOutputTokens = "text_output_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        credits = container.flexibleDouble(.credits)
        turns = container.flexibleInt(.turns)
        threads = container.flexibleInt(.threads)
        textTotalTokens = container.flexibleInt(.textTotalTokens)
        cachedTextInputTokens = container.flexibleInt(.cachedTextInputTokens)
        uncachedTextInputTokens = container.flexibleInt(.uncachedTextInputTokens)
        textOutputTokens = container.flexibleInt(.textOutputTokens)
    }

    var apiTotals: ApiEquivalentTotals {
        let parts = uncachedTextInputTokens + cachedTextInputTokens + textOutputTokens
        return ApiEquivalentTotals(
            totalTokens: textTotalTokens > 0 ? textTotalTokens : parts,
            uncachedInputTokens: uncachedTextInputTokens,
            cachedInputTokens: cachedTextInputTokens,
            outputTokens: textOutputTokens,
            turns: turns,
            threads: threads)
    }
}

private extension KeyedDecodingContainer where Key == ApiAnalyticsTotals.CodingKeys {
    func flexibleInt(_ key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) ?? 0 }
        return 0
    }

    func flexibleDouble(_ key: Key) -> Double {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) ?? 0 }
        return 0
    }
}
