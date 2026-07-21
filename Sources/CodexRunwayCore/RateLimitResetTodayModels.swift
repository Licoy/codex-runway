import Foundation

/// Whether Codex rate limits have reset today, per the public tracker site.
public enum RateLimitResetTodayState: String, Sendable, Equatable {
    case yes
    case no
    case unknown

    public init(raw: String?) {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "yes":
            self = .yes
        case "no":
            self = .no
        default:
            self = .unknown
        }
    }
}

public struct RateLimitResetTodayUsage: Sendable, Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var reasoningTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, reasoningTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
    }

    public var isEmpty: Bool {
        inputTokens == 0 && outputTokens == 0 && reasoningTokens == 0
    }
}

public struct RateLimitResetTodaySnapshot: Sendable, Equatable {
    public var state: RateLimitResetTodayState
    public var resetAt: Date?
    public var updatedAt: Date?
    public var autoResetHours: Int?
    public var yesSubtitles: [String]
    public var noSubtitles: [String]
    public var confidence: Double?
    public var tweetURL: URL?
    public var tweetText: String?
    public var model: String?
    public var latestCheckedAt: Date?
    public var latestVerdict: String?
    public var latestUsage: RateLimitResetTodayUsage?
    public var lastResetCheckedAt: Date?
    public var lastResetVerdict: String?
    public var fetchedAt: Date

    public init(
        state: RateLimitResetTodayState,
        resetAt: Date? = nil,
        updatedAt: Date? = nil,
        autoResetHours: Int? = nil,
        yesSubtitles: [String] = [],
        noSubtitles: [String] = [],
        confidence: Double? = nil,
        tweetURL: URL? = nil,
        tweetText: String? = nil,
        model: String? = nil,
        latestCheckedAt: Date? = nil,
        latestVerdict: String? = nil,
        latestUsage: RateLimitResetTodayUsage? = nil,
        lastResetCheckedAt: Date? = nil,
        lastResetVerdict: String? = nil,
        fetchedAt: Date = Date())
    {
        self.state = state
        self.resetAt = resetAt
        self.updatedAt = updatedAt
        self.autoResetHours = autoResetHours
        self.yesSubtitles = yesSubtitles
        self.noSubtitles = noSubtitles
        self.confidence = confidence
        self.tweetURL = tweetURL
        self.tweetText = tweetText
        self.model = model
        self.latestCheckedAt = latestCheckedAt
        self.latestVerdict = latestVerdict
        self.latestUsage = latestUsage
        self.lastResetCheckedAt = lastResetCheckedAt
        self.lastResetVerdict = lastResetVerdict
        self.fetchedAt = fetchedAt
    }

    /// One-line tweet preview for the UI (empty text falls back to host).
    public var displayTweetLine: String? {
        if let tweetText {
            let cleaned = tweetText
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        if tweetURL != nil {
            return nil
        }
        return nil
    }

    public static func decode(from data: Data, fetchedAt: Date = Date()) throws -> RateLimitResetTodaySnapshot {
        let dto = try JSONDecoder().decode(RateLimitResetTodayResponse.self, from: data)
        let summary = dto.automationSummary
        let latest = dto.latest ?? summary?.latest ?? summary.map(\.asCheck)
        let lastReset = dto.lastReset ?? summary?.lastReset
        let model = dto.model ?? summary?.model
        let usageDTO = latest?.usage
        let usage = usageDTO.map {
            RateLimitResetTodayUsage(
                inputTokens: $0.inputTokens ?? 0,
                outputTokens: $0.outputTokens ?? 0,
                reasoningTokens: $0.reasoningTokens ?? 0)
        }
        let tweetText = latest?.tweetText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTweet = (tweetText?.isEmpty == false) ? tweetText : nil

        return RateLimitResetTodaySnapshot(
            state: RateLimitResetTodayState(raw: dto.state),
            resetAt: Self.date(fromEpoch: dto.resetAt),
            updatedAt: Self.date(fromEpoch: dto.updatedAt) ?? fetchedAt,
            autoResetHours: dto.autoResetHours,
            yesSubtitles: dto.yesSubtitles ?? [],
            noSubtitles: dto.noSubtitles ?? [],
            confidence: latest?.confidence,
            tweetURL: Self.url(from: latest?.tweetUrl),
            tweetText: normalizedTweet,
            model: model,
            latestCheckedAt: Self.date(fromEpoch: latest?.checkedAt),
            latestVerdict: latest?.verdict,
            latestUsage: usage,
            lastResetCheckedAt: Self.date(fromEpoch: lastReset?.checkedAt),
            lastResetVerdict: lastReset?.verdict,
            fetchedAt: fetchedAt)
    }

    /// API uses millisecond epochs; tolerate seconds.
    public static func date(fromEpoch value: Double?) -> Date? {
        guard let value else { return nil }
        if value <= 0 { return nil }
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        return Date(timeIntervalSince1970: value)
    }

    private static func url(from string: String?) -> URL? {
        guard let string, let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}

// MARK: - Private DTO

private struct RateLimitResetTodayResponse: Decodable {
    var state: String?
    var resetAt: Double?
    var updatedAt: Double?
    var autoResetHours: Int?
    var yesSubtitles: [String]?
    var noSubtitles: [String]?
    var model: String?
    var latest: RateLimitResetTodayCheckDTO?
    var lastReset: RateLimitResetTodayCheckDTO?
    var automationSummary: RateLimitResetTodayAutomationDTO?

    private enum CodingKeys: String, CodingKey {
        case state
        case resetAt
        case updatedAt
        case autoResetHours
        case yesSubtitles
        case noSubtitles
        case model
        case latest
        case lastReset
        case automationSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        resetAt = try Self.decodeEpoch(container, forKey: .resetAt)
        updatedAt = try Self.decodeEpoch(container, forKey: .updatedAt)
        autoResetHours = try container.decodeIfPresent(Int.self, forKey: .autoResetHours)
        yesSubtitles = try container.decodeIfPresent([String].self, forKey: .yesSubtitles)
        noSubtitles = try container.decodeIfPresent([String].self, forKey: .noSubtitles)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        latest = try container.decodeIfPresent(RateLimitResetTodayCheckDTO.self, forKey: .latest)
        lastReset = try container.decodeIfPresent(RateLimitResetTodayCheckDTO.self, forKey: .lastReset)
        automationSummary = try container.decodeIfPresent(RateLimitResetTodayAutomationDTO.self, forKey: .automationSummary)
    }

    private static func decodeEpoch(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys) throws -> Double?
    {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}

private struct RateLimitResetTodayUsageDTO: Decodable {
    var inputTokens: Int?
    var outputTokens: Int?
    var reasoningTokens: Int?
}

/// Leaf check payload (no nested latest/lastReset).
private struct RateLimitResetTodayCheckDTO: Decodable {
    var confidence: Double?
    var tweetUrl: String?
    var tweetText: String?
    var checkedAt: Double?
    var verdict: String?
    var usage: RateLimitResetTodayUsageDTO?

    private enum CodingKeys: String, CodingKey {
        case confidence
        case tweetUrl
        case tweetText
        case checkedAt
        case verdict
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decodeIfPresent(Double.self, forKey: .confidence) {
            confidence = value
        } else if let value = try? container.decodeIfPresent(Int.self, forKey: .confidence) {
            confidence = Double(value)
        } else {
            confidence = nil
        }
        tweetUrl = try container.decodeIfPresent(String.self, forKey: .tweetUrl)
        tweetText = try container.decodeIfPresent(String.self, forKey: .tweetText)
        if let value = try? container.decodeIfPresent(Double.self, forKey: .checkedAt) {
            checkedAt = value
        } else if let value = try? container.decodeIfPresent(Int64.self, forKey: .checkedAt) {
            checkedAt = Double(value)
        } else {
            checkedAt = nil
        }
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        usage = try container.decodeIfPresent(RateLimitResetTodayUsageDTO.self, forKey: .usage)
    }

    init(
        confidence: Double?,
        tweetUrl: String?,
        tweetText: String?,
        checkedAt: Double?,
        verdict: String?,
        usage: RateLimitResetTodayUsageDTO?)
    {
        self.confidence = confidence
        self.tweetUrl = tweetUrl
        self.tweetText = tweetText
        self.checkedAt = checkedAt
        self.verdict = verdict
        self.usage = usage
    }
}

/// automationSummary may itself look like a check and also nest latest/lastReset.
private struct RateLimitResetTodayAutomationDTO: Decodable {
    var confidence: Double?
    var tweetUrl: String?
    var tweetText: String?
    var checkedAt: Double?
    var verdict: String?
    var usage: RateLimitResetTodayUsageDTO?
    var model: String?
    var latest: RateLimitResetTodayCheckDTO?
    var lastReset: RateLimitResetTodayCheckDTO?

    private enum CodingKeys: String, CodingKey {
        case confidence
        case tweetUrl
        case tweetText
        case checkedAt
        case verdict
        case usage
        case model
        case latest
        case lastReset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decodeIfPresent(Double.self, forKey: .confidence) {
            confidence = value
        } else if let value = try? container.decodeIfPresent(Int.self, forKey: .confidence) {
            confidence = Double(value)
        } else {
            confidence = nil
        }
        tweetUrl = try container.decodeIfPresent(String.self, forKey: .tweetUrl)
        tweetText = try container.decodeIfPresent(String.self, forKey: .tweetText)
        if let value = try? container.decodeIfPresent(Double.self, forKey: .checkedAt) {
            checkedAt = value
        } else if let value = try? container.decodeIfPresent(Int64.self, forKey: .checkedAt) {
            checkedAt = Double(value)
        } else {
            checkedAt = nil
        }
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        usage = try container.decodeIfPresent(RateLimitResetTodayUsageDTO.self, forKey: .usage)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        latest = try container.decodeIfPresent(RateLimitResetTodayCheckDTO.self, forKey: .latest)
        lastReset = try container.decodeIfPresent(RateLimitResetTodayCheckDTO.self, forKey: .lastReset)
    }

    var asCheck: RateLimitResetTodayCheckDTO {
        RateLimitResetTodayCheckDTO(
            confidence: confidence,
            tweetUrl: tweetUrl,
            tweetText: tweetText,
            checkedAt: checkedAt,
            verdict: verdict,
            usage: usage)
    }
}
