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

    /// Next expected auto-reset, when `resetAt` + `autoResetHours` is still in the future.
    public var nextResetAt: Date? {
        guard let resetAt, let hours = autoResetHours, hours > 0 else { return nil }
        return resetAt.addingTimeInterval(TimeInterval(hours * 3_600))
    }

    public func nextResetRemaining(now: Date = Date()) -> TimeInterval? {
        guard let nextResetAt, nextResetAt > now else { return nil }
        return nextResetAt.timeIntervalSince(now)
    }

    /// Dev/preview fixture kinds for UI work without hitting the public API.
    public enum DevMockKind: String, Sendable, Equatable {
        case yes
        /// Today already reset, with a live countdown to the next auto-reset window.
        case yesCountdown = "yes-countdown"
        case no
        case unknown

        public var state: RateLimitResetTodayState {
            switch self {
            case .yes, .yesCountdown:
                return .yes
            case .no:
                return .no
            case .unknown:
                return .unknown
            }
        }

        public static func parse(_ raw: String) -> DevMockKind? {
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yes", "y", "1", "true":
                return .yes
            case "yes-countdown", "yes_countdown", "countdown":
                return .yesCountdown
            case "no", "n", "0", "false":
                return .no
            case "unknown":
                return .unknown
            default:
                return nil
            }
        }
    }

    /// Dev/preview fixture for UI work without hitting the public API.
    public static func devMock(
        state: RateLimitResetTodayState,
        now: Date = Date()) -> RateLimitResetTodaySnapshot
    {
        switch state {
        case .yes:
            return devMock(kind: .yes, now: now)
        case .no:
            return devMock(kind: .no, now: now)
        case .unknown:
            return devMock(kind: .unknown, now: now)
        }
    }

    public static func devMock(
        kind: DevMockKind,
        now: Date = Date()) -> RateLimitResetTodaySnapshot
    {
        switch kind {
        case .yes:
            // Reset far enough in the past that the next auto-window has already elapsed.
            return RateLimitResetTodaySnapshot(
                state: .yes,
                resetAt: now.addingTimeInterval(-25 * 3_600),
                updatedAt: now.addingTimeInterval(-15 * 60),
                autoResetHours: 20,
                yesSubtitles: ["Limits reset, go crazy", "You can just build things"],
                noSubtitles: [],
                confidence: 0.97,
                tweetURL: URL(string: "https://x.com/thsottiaux/status/2079433708986319143"),
                tweetText: "Rate limits are fully reset — go build something great today.",
                model: "gpt-5.4",
                latestCheckedAt: now.addingTimeInterval(-12 * 60),
                latestVerdict: "reset",
                latestUsage: RateLimitResetTodayUsage(inputTokens: 412, outputTokens: 88, reasoningTokens: 30),
                lastResetCheckedAt: now.addingTimeInterval(-25 * 3_600),
                lastResetVerdict: "reset",
                fetchedAt: now.addingTimeInterval(-90))
        case .yesCountdown:
            // Reset ~2h ago with a 20h auto window → ~18h countdown remaining.
            return RateLimitResetTodaySnapshot(
                state: .yes,
                resetAt: now.addingTimeInterval(-2 * 3_600 - 17 * 60),
                updatedAt: now.addingTimeInterval(-8 * 60),
                autoResetHours: 20,
                yesSubtitles: ["Limits reset, go crazy", "You can just build things"],
                noSubtitles: [],
                confidence: 0.98,
                tweetURL: URL(string: "https://x.com/thsottiaux/status/2079433708986319143"),
                tweetText: "Limits are clear again. Clock is already ticking on the next window.",
                model: "gpt-5.4",
                latestCheckedAt: now.addingTimeInterval(-5 * 60),
                latestVerdict: "reset",
                latestUsage: RateLimitResetTodayUsage(inputTokens: 390, outputTokens: 74, reasoningTokens: 28),
                lastResetCheckedAt: now.addingTimeInterval(-2 * 3_600 - 17 * 60),
                lastResetVerdict: "reset",
                fetchedAt: now.addingTimeInterval(-45))
        case .no:
            return RateLimitResetTodaySnapshot(
                state: .no,
                resetAt: nil,
                updatedAt: now.addingTimeInterval(-6 * 3_600),
                autoResetHours: 20,
                yesSubtitles: [],
                noSubtitles: ["Back to your local model peasant"],
                confidence: 0.99,
                tweetURL: URL(string: "https://x.com/thsottiaux/status/2079433708986319143"),
                tweetText: "@Kappaemme1926 We are being very subtle. Use \"Approve for me\" instead.",
                model: "gpt-5.4",
                latestCheckedAt: now.addingTimeInterval(-6 * 3_600),
                latestVerdict: "not_reset",
                latestUsage: RateLimitResetTodayUsage(inputTokens: 371, outputTokens: 69, reasoningTokens: 25),
                lastResetCheckedAt: nil,
                lastResetVerdict: nil,
                fetchedAt: now.addingTimeInterval(-180))
        case .unknown:
            return RateLimitResetTodaySnapshot(
                state: .unknown,
                updatedAt: now,
                fetchedAt: now)
        }
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
