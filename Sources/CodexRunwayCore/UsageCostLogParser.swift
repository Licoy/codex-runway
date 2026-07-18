import Foundation

final class UsageCostLogParser {
    private let decoder = JSONDecoder()
    private let fractionalTimestamp: ISO8601DateFormatter
    private let plainTimestamp: ISO8601DateFormatter
    private let dayFormatter: DateFormatter

    init() {
        fractionalTimestamp = ISO8601DateFormatter()
        fractionalTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        plainTimestamp = ISO8601DateFormatter()
        plainTimestamp.formatOptions = [.withInternetDateTime]
        dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dayFormatter.dateFormat = "yyyy-MM-dd"
    }

    func parse(_ data: Data) throws -> UsageCostLogRecord {
        let encoded = try decoder.decode(EncodedUsageCostRecord.self, from: data)
        let timestamp = encoded.timestamp.flatMap(parseTimestamp) ?? .distantPast
        let payload = encoded.payload
        let turnContext = encoded.turnContext
        let contextModel = encoded.type == "turn_context"
            ? payload?.model
            : turnContext?.model
        return UsageCostLogRecord(
            timestamp: timestamp,
            model: turnContext?.model ?? payload?.model,
            contextModel: contextModel,
            sessionCWD: payload?.cwd ?? turnContext?.cwd,
            lastTokenUsage: payload?.info?.lastTokenUsage?.usage)
    }

    func utcDay(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func parseTimestamp(_ text: String) -> Date? {
        fractionalTimestamp.date(from: text) ?? plainTimestamp.date(from: text)
    }
}

private struct EncodedUsageCostRecord: Decodable {
    var timestamp: String?
    var type: String?
    var payload: EncodedUsagePayload?
    var turnContext: EncodedTurnContext?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case type
        case payload
        case turnContext = "turn_context"
    }
}

private struct EncodedTurnContext: Decodable {
    var model: String?
    var cwd: String?
}

private struct EncodedUsagePayload: Decodable {
    var model: String?
    var cwd: String?
    var info: EncodedUsageInfo?
}

private struct EncodedUsageInfo: Decodable {
    var lastTokenUsage: EncodedTokenUsage?

    enum CodingKeys: String, CodingKey {
        case lastTokenUsage = "last_token_usage"
    }
}

private struct EncodedTokenUsage: Decodable {
    var inputTokens: Int?
    var cachedInputTokens: Int?
    var outputTokens: Int?
    var reasoningOutputTokens: Int?

    var usage: TokenUsage {
        TokenUsage(
            inputTokens: inputTokens ?? 0,
            cachedInputTokens: cachedInputTokens ?? 0,
            outputTokens: (outputTokens ?? 0) + (reasoningOutputTokens ?? 0))
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
    }
}
