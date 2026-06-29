import Foundation

public struct CodexAuth: Codable, Sendable, Equatable {
    public var authMode: String?
    public var tokens: Tokens
    public var lastRefresh: String?
    public var planType: String?
    public var authFilePlanType: String?

    public struct Tokens: Codable, Sendable, Equatable {
        public var idToken: String?
        public var accessToken: String
        public var refreshToken: String
        public var accountId: String?

        public init(idToken: String? = nil, accessToken: String, refreshToken: String, accountId: String?) {
            self.idToken = idToken
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.accountId = accountId
        }

        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case accountId = "account_id"
        }
    }

    public init(
        authMode: String?,
        tokens: Tokens,
        lastRefresh: String?,
        planType: String? = nil,
        authFilePlanType: String? = nil)
    {
        self.authMode = authMode
        self.tokens = tokens
        self.lastRefresh = lastRefresh
        self.planType = planType
        self.authFilePlanType = authFilePlanType
    }

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case tokens
        case lastRefresh = "last_refresh"
        case planType = "plan_type"
        case authFilePlanType = "auth_file_plan_type"
    }

    public var redactedDescription: String {
        "CodexAuth(authMode: \(authMode ?? "unknown"), accountId: \(tokens.accountId ?? "none"), idToken: <redacted>, accessToken: <redacted>, refreshToken: <redacted>)"
    }

    public mutating func mergeRefreshResponse(_ data: Data, now: Date = Date()) throws {
        let response = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
        if let idToken = response.idToken, !idToken.isEmpty {
            tokens.idToken = idToken
        }
        tokens.accessToken = response.accessToken
        if let refreshToken = response.refreshToken, !refreshToken.isEmpty {
            tokens.refreshToken = refreshToken
        }
        lastRefresh = RunwayDates.string(now)
    }
}

struct TokenRefreshResponse: Decodable {
    var idToken: String?
    var accessToken: String
    var refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

public enum TokenInspector {
    public static func isExpired(_ jwt: String, now: Date = Date(), skewSeconds: TimeInterval = 60) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2,
              let data = Data(base64URLEncoded: String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double
        else { return true }
        return Date(timeIntervalSince1970: exp).timeIntervalSince(now) <= skewSeconds
    }
}

public struct CodexIdentityClaims: Sendable, Equatable {
    public var email: String?
    public var username: String?
    public var subject: String?
    public var planType: String?
    public var accountId: String?

    public static func decode(_ jwt: String?) -> CodexIdentityClaims? {
        guard let jwt else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2,
              let data = Data(base64URLEncoded: String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let profile = object["https://api.openai.com/profile"] as? [String: Any]
        let auth = object["https://api.openai.com/auth"] as? [String: Any]
        return CodexIdentityClaims(
            email: firstNonEmpty(object["email"] as? String, profile?["email"] as? String),
            username: firstNonEmpty(object["preferred_username"] as? String, object["name"] as? String),
            subject: firstNonEmpty(object["sub"] as? String),
            planType: firstNonEmpty(auth?["chatgpt_plan_type"] as? String),
            accountId: firstNonEmpty(auth?["account_id"] as? String))
    }
}

public enum CodexSubscriptionTier: Sendable, Equatable {
    case free
    case plus
    case pro5x
    case pro20x
    case business
    case team
    case enterprise
    case edu
    case api
    case unknown

    public static func resolve(planType: String?, fallbackPlanType: String?) -> CodexSubscriptionTier {
        guard let raw = firstNonEmpty(planType, fallbackPlanType)?.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        else { return .unknown }

        if raw == "prolite" || raw == "pro-lite" || raw == "pro-5x" || raw == "codex-pro-5x" {
            return .pro5x
        }
        if raw == "promax" || raw == "pro-max" || raw == "pro-20x" || raw == "codex-pro-20x" {
            return .pro20x
        }
        if raw.contains("enterprise") { return .enterprise }
        if raw.contains("business") { return .business }
        if raw.contains("team") { return .team }
        if raw.contains("edu") { return .edu }
        if raw.contains("api") { return .api }
        if raw.contains("plus") { return .plus }
        if raw.contains("pro") { return .pro20x }
        if raw.contains("free") { return .free }
        return .unknown
    }
}

public struct CodexAccountDisplay: Sendable, Equatable {
    public var isAuthenticated: Bool
    public var displayName: String
    public var email: String?
    public var username: String?
    public var accountId: String?
    public var subscriptionTier: CodexSubscriptionTier

    public static func make(auth: CodexAuth?, quotaPlan: String?) -> CodexAccountDisplay {
        guard let auth else {
            return CodexAccountDisplay(isAuthenticated: false, displayName: "", email: nil, username: nil, accountId: nil, subscriptionTier: .unknown)
        }
        let idClaims = CodexIdentityClaims.decode(auth.tokens.idToken)
        let accessClaims = CodexIdentityClaims.decode(auth.tokens.accessToken)
        let email = firstNonEmpty(idClaims?.email, accessClaims?.email)
        let username = firstNonEmpty(idClaims?.username, accessClaims?.username, idClaims?.subject, accessClaims?.subject)
        let accountId = firstNonEmpty(idClaims?.accountId, accessClaims?.accountId, auth.tokens.accountId)
        let plan = firstNonEmpty(quotaPlan, idClaims?.planType, accessClaims?.planType, auth.authFilePlanType, auth.planType)
        return CodexAccountDisplay(
            isAuthenticated: true,
            displayName: firstNonEmpty(email, username, shortenedAccountId(accountId)) ?? "",
            email: email,
            username: username,
            accountId: accountId,
            subscriptionTier: CodexSubscriptionTier.resolve(planType: plan, fallbackPlanType: nil))
    }

    private static func shortenedAccountId(_ value: String?) -> String? {
        guard let value = firstNonEmpty(value) else { return nil }
        guard value.count > 9 else { return value }
        return "\(value.prefix(5))...\(value.suffix(4))"
    }
}

public struct RateWindow: Sendable, Equatable {
    public var usedPercent: Int
    public var windowMinutes: Int?
    public var resetsAt: Date?
}

public struct NamedRateWindow: Sendable, Equatable {
    public var name: String
    public var window: RateWindow
}

public struct QuotaSnapshot: Sendable, Equatable {
    public var plan: String?
    public var primary: RateWindow
    public var secondary: RateWindow?
    public var additionalWindows: [NamedRateWindow]
    public var creditsBalance: Double?
    public var updatedAt: Date

    public var menuBarText: String {
        menuBarText(now: updatedAt)
    }

    public func menuBarText(now: Date, waitPrefix: String = "wait") -> String {
        guard let reset = primary.resetsAt else { return primary.usedPercent >= 100 ? waitPrefix : "\(primary.usedPercent)%" }
        let prefix = primary.usedPercent >= 100 ? "\(waitPrefix) " : ""
        return prefix + DurationFormatter.localized(reset.timeIntervalSince(now), language: .english, includeSeconds: false)
    }

    public func nextDueReset(after triggeredReset: Date?, now: Date) -> Date? {
        let resets = ([primary.resetsAt, secondary?.resetsAt] + additionalWindows.map { $0.window.resetsAt })
            .compactMap(\.self)
        let triggeredReset = triggeredReset ?? .distantPast
        return resets
            .filter { $0 > triggeredReset && now.timeIntervalSince($0) >= 1 }
            .sorted()
            .first
    }

    public static func decode(from data: Data, now: Date = Date()) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(QuotaResponse.self, from: data)
        return QuotaSnapshot(
            plan: response.planType,
            primary: response.rateLimit.primaryWindow.rateWindow,
            secondary: response.rateLimit.secondaryWindow?.rateWindow,
            additionalWindows: response.additionalRateLimits.compactMap(\.namedWindow),
            creditsBalance: response.credits?.balance,
            updatedAt: now)
    }
}

public struct ResetCredit: Sendable, Equatable {
    public var id: String?
    public var status: String
    public var createdAt: Date?
    public var expiresAt: Date?
    public var remainingSeconds: TimeInterval
}

public struct ResetCreditsSnapshot: Sendable, Equatable {
    public var availableCount: Int
    public var credits: [ResetCredit]
    public var updatedAt: Date

    public static func decode(from data: Data, now: Date = Date()) throws -> ResetCreditsSnapshot {
        let response = try JSONDecoder().decode(ResetCreditsResponse.self, from: data)
        let credits = response.credits.map { item in
            ResetCredit(
                id: item.id,
                status: item.status ?? "unknown",
                createdAt: item.createdAt,
                expiresAt: item.expiresAt,
                remainingSeconds: max(0, item.expiresAt?.timeIntervalSince(now) ?? 0))
        }
        return ResetCreditsSnapshot(
            availableCount: response.availableCount ?? credits.filter { $0.status == "available" }.count,
            credits: credits,
            updatedAt: now)
    }
}

public struct TokenUsage: Sendable, Equatable {
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int

    public static let zero = TokenUsage(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0)

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens)
    }
}

public struct ModelCostBreakdown: Sendable, Equatable {
    public var model: String
    public var usage: TokenUsage
    public var estimatedUSD: Decimal
}

public struct UsageCostSummary: Sendable, Equatable {
    public var window: DateInterval
    public var totals: TokenUsage
    public var modelBreakdown: [ModelCostBreakdown]
    public var estimatedUSD: Decimal
    public var pricingVersion: String
    public var unknownModels: [String]
}

public struct SessionRepairReport: Sendable, Equatable {
    public var missingIndexIDs: [String]
    public var orphanIndexIDs: [String]
    public var duplicateIndexIDs: [String]
    public var staleTitleIDs: [String]
    public var backupPath: URL?
    public var plannedEntries: Int
}

extension Data {
    init?(base64URLEncoded value: String) {
        var text = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - text.count % 4) % 4
        text += String(repeating: "=", count: padding)
        self.init(base64Encoded: text)
    }
}
