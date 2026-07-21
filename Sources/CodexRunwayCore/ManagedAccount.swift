import Foundation

public enum ManagedAuthMode: String, Codable, Sendable, Equatable {
    case oauth
    case apiKey
}

/// Cached quota fields for sidebar / multi-account list (no secrets).
public struct CachedAccountQuota: Codable, Sendable, Equatable {
    public var plan: String?
    public var primaryUsedPercent: Int
    public var primaryResetsAt: Date?
    public var secondaryUsedPercent: Int?
    public var secondaryResetsAt: Date?
    public var updatedAt: Date

    public init(
        plan: String? = nil,
        primaryUsedPercent: Int,
        primaryResetsAt: Date? = nil,
        secondaryUsedPercent: Int? = nil,
        secondaryResetsAt: Date? = nil,
        updatedAt: Date = Date())
    {
        self.plan = plan
        self.primaryUsedPercent = max(0, min(100, primaryUsedPercent))
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent.map { max(0, min(100, $0)) }
        self.secondaryResetsAt = secondaryResetsAt
        self.updatedAt = updatedAt
    }

    public static func make(from snapshot: QuotaSnapshot) -> CachedAccountQuota {
        CachedAccountQuota(
            plan: snapshot.plan,
            primaryUsedPercent: snapshot.primary.usedPercent,
            primaryResetsAt: snapshot.primary.resetsAt,
            secondaryUsedPercent: snapshot.secondary?.usedPercent,
            secondaryResetsAt: snapshot.secondary?.resetsAt,
            updatedAt: snapshot.updatedAt)
    }

    public var primaryRemainingPercent: Int {
        max(0, 100 - primaryUsedPercent)
    }

    public var secondaryRemainingPercent: Int? {
        secondaryUsedPercent.map { max(0, 100 - $0) }
    }
}

/// Non-secret metadata for a managed Codex account.
public struct ManagedAccount: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sortIndex: Int
    public var authMode: ManagedAuthMode
    public var email: String?
    public var username: String?
    public var accountId: String?
    public var displayName: String
    public var alias: String?
    public var note: String?
    public var planType: String?
    public var subscriptionExpiresAt: Date?
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var lastQuotaAt: Date?
    public var requiresReauth: Bool
    public var lastError: String?
    public var cachedQuota: CachedAccountQuota?

    public init(
        id: String,
        sortIndex: Int = 0,
        authMode: ManagedAuthMode = .oauth,
        email: String? = nil,
        username: String? = nil,
        accountId: String? = nil,
        displayName: String,
        alias: String? = nil,
        note: String? = nil,
        planType: String? = nil,
        subscriptionExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        lastQuotaAt: Date? = nil,
        requiresReauth: Bool = false,
        lastError: String? = nil,
        cachedQuota: CachedAccountQuota? = nil)
    {
        self.id = id
        self.sortIndex = sortIndex
        self.authMode = authMode
        self.email = email
        self.username = username
        self.accountId = accountId
        self.displayName = displayName
        self.alias = alias
        self.note = note
        self.planType = planType
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastQuotaAt = lastQuotaAt
        self.requiresReauth = requiresReauth
        self.lastError = lastError
        self.cachedQuota = cachedQuota
    }

    public var resolvedDisplayName: String {
        firstNonEmpty(alias, displayName, email, username, accountId.map { Self.shorten($0) }) ?? id
    }

    public var subscriptionTier: CodexSubscriptionTier {
        CodexSubscriptionTier.resolve(planType: planType ?? cachedQuota?.plan, fallbackPlanType: nil)
    }

    public static func make(
        id: String? = nil,
        auth: CodexAuth,
        sortIndex: Int = 0,
        alias: String? = nil,
        note: String? = nil,
        quotaPlan: String? = nil,
        now: Date = Date()) -> ManagedAccount
    {
        if auth.isAPIKeyAuth {
            let key = auth.openAIAPIKey ?? ""
            let fingerprint = AccountIdentity.apiKeyFingerprint(key)
            let accountId = "api-\(fingerprint)"
            return ManagedAccount(
                id: id ?? accountId,
                sortIndex: sortIndex,
                authMode: .apiKey,
                email: nil,
                username: nil,
                accountId: accountId,
                displayName: "API ···\(fingerprint.suffix(4))",
                alias: alias,
                note: note,
                planType: firstNonEmpty(quotaPlan, auth.planType, "api"),
                subscriptionExpiresAt: nil,
                createdAt: now,
                lastUsedAt: nil,
                lastQuotaAt: nil,
                requiresReauth: false,
                lastError: nil,
                cachedQuota: nil)
        }

        let display = CodexAccountDisplay.make(auth: auth, quotaPlan: quotaPlan, now: now)
        let idClaims = CodexIdentityClaims.decode(auth.tokens.idToken)
        let accessClaims = CodexIdentityClaims.decode(auth.tokens.accessToken)
        let stableId = id
            ?? firstNonEmpty(display.accountId, display.email, display.username)
            ?? AccountIdentity.oauthFingerprint(auth)
        // Prefer live quota plan, then JWT claims, then auth-file fields — never invent from nowhere.
        let resolvedPlan = firstNonEmpty(
            quotaPlan,
            idClaims?.planType,
            accessClaims?.planType,
            auth.authFilePlanType,
            auth.planType)
        return ManagedAccount(
            id: stableId,
            sortIndex: sortIndex,
            authMode: .oauth,
            email: display.email,
            username: display.username,
            accountId: display.accountId,
            displayName: display.displayName.isEmpty ? stableId : display.displayName,
            alias: alias,
            note: note,
            planType: resolvedPlan,
            subscriptionExpiresAt: display.subscriptionExpiresAt,
            createdAt: now,
            lastUsedAt: nil,
            lastQuotaAt: nil,
            requiresReauth: false,
            lastError: nil,
            cachedQuota: nil)
    }

    public func withIdentity(from auth: CodexAuth, quotaPlan: String? = nil, now: Date = Date()) -> ManagedAccount {
        var copy = self
        let rebuilt = ManagedAccount.make(
            id: id,
            auth: auth,
            sortIndex: sortIndex,
            alias: alias,
            note: note,
            quotaPlan: quotaPlan,
            now: now)
        copy.authMode = rebuilt.authMode
        copy.email = rebuilt.email
        copy.username = rebuilt.username
        copy.accountId = rebuilt.accountId
        if alias == nil {
            copy.displayName = rebuilt.displayName
        }
        // Fresh auth/JWT plan must beat stale metadata when no explicit quota plan is supplied.
        copy.planType = firstNonEmpty(quotaPlan, rebuilt.planType, planType)
        copy.subscriptionExpiresAt = rebuilt.subscriptionExpiresAt
        return copy
    }

    public func applying(quota: QuotaSnapshot) -> ManagedAccount {
        var copy = self
        copy.cachedQuota = CachedAccountQuota.make(from: quota)
        copy.lastQuotaAt = quota.updatedAt
        if let plan = firstNonEmpty(quota.plan) {
            copy.planType = plan
        }
        copy.requiresReauth = false
        copy.lastError = nil
        return copy
    }

    public func applying(error: String, requiresReauth: Bool) -> ManagedAccount {
        var copy = self
        copy.lastError = error
        copy.requiresReauth = requiresReauth
        return copy
    }

    private static func shorten(_ value: String) -> String {
        guard value.count > 9 else { return value }
        return "\(value.prefix(5))...\(value.suffix(4))"
    }
}

public enum AccountIdentity {
    public static func apiKeyFingerprint(_ apiKey: String) -> String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return stableHash(trimmed)
    }

    public static func oauthFingerprint(_ auth: CodexAuth) -> String {
        if !auth.tokens.refreshToken.isEmpty {
            return "rt-\(stableHash(auth.tokens.refreshToken))"
        }
        if !auth.tokens.accessToken.isEmpty {
            return "at-\(stableHash(auth.tokens.accessToken))"
        }
        return "unknown-\(stableHash(UUID().uuidString))"
    }

    public static func matchKey(for account: ManagedAccount) -> String {
        if let accountId = firstNonEmpty(account.accountId) {
            return "id:\(accountId.lowercased())"
        }
        if let email = firstNonEmpty(account.email) {
            return "email:\(email.lowercased())"
        }
        return "row:\(account.id)"
    }

    public static func matchKey(for auth: CodexAuth) -> String {
        let display = CodexAccountDisplay.make(auth: auth, quotaPlan: nil)
        if let accountId = firstNonEmpty(display.accountId, auth.tokens.accountId) {
            return "id:\(accountId.lowercased())"
        }
        if let email = firstNonEmpty(display.email) {
            return "email:\(email.lowercased())"
        }
        if auth.isAPIKeyAuth, let key = auth.openAIAPIKey {
            return "id:api-\(apiKeyFingerprint(key))"
        }
        return "rt:\(oauthFingerprint(auth))"
    }

    /// Stable short hex hash (not cryptographic; for ids/dedup only).
    public static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5_381
        for byte in value.utf8 {
            hash = 127 &* hash &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}

public struct AccountIndex: Codable, Sendable, Equatable {
    public var version: Int
    public var activeAccountId: String?
    public var accounts: [ManagedAccount]

    public static let currentVersion = 1

    public init(version: Int = AccountIndex.currentVersion, activeAccountId: String? = nil, accounts: [ManagedAccount] = []) {
        self.version = version
        self.activeAccountId = activeAccountId
        self.accounts = accounts
    }

    /// Active first, then user sortIndex, then display name.
    public func orderedForSidebar() -> [ManagedAccount] {
        let active = activeAccountId
        return accounts.sorted { lhs, rhs in
            let lActive = lhs.id == active
            let rActive = rhs.id == active
            if lActive != rActive { return lActive && !rActive }
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.resolvedDisplayName.localizedCaseInsensitiveCompare(rhs.resolvedDisplayName) == .orderedAscending
        }
    }

    public func account(id: String) -> ManagedAccount? {
        accounts.first { $0.id == id }
    }

    public mutating func upsert(_ account: ManagedAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }

    public mutating func remove(id: String) {
        accounts.removeAll { $0.id == id }
        if activeAccountId == id {
            activeAccountId = accounts.sorted { $0.sortIndex < $1.sortIndex }.first?.id
        }
    }

    public mutating func reindexSortOrder(_ orderedIds: [String]) {
        var next = 0
        for id in orderedIds {
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { continue }
            accounts[index].sortIndex = next
            next += 1
        }
        for index in accounts.indices where !orderedIds.contains(accounts[index].id) {
            accounts[index].sortIndex = next
            next += 1
        }
    }
}
