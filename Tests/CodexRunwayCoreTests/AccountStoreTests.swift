import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Multi-account store")
struct AccountStoreTests {
    @Test("upserts accounts, stores credentials with restricted permissions, and switches active")
    func upsertsAndSwitches() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-accounts-\(UUID().uuidString)", isDirectory: true)
        let official = root.appendingPathComponent("official-auth.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = AccountStore(rootURL: root.appendingPathComponent("accounts"), officialAuthURL: official)
        let authA = sampleAuth(accountId: "acct-a", email: "a@example.com", refresh: "refresh-a")
        let authB = sampleAuth(accountId: "acct-b", email: "b@example.com", refresh: "refresh-b")

        let accountA = try store.upsert(auth: authA, makeActive: true)
        let accountB = try store.upsert(auth: authB, makeActive: false)
        #expect(accountA.id == "acct-a" || accountA.accountId == "acct-a")
        #expect(accountB.email == "b@example.com")

        var index = try store.loadIndex()
        #expect(index.accounts.count == 2)
        #expect(index.activeAccountId == accountA.id)

        let credURL = store.credentialURL(id: accountA.id)
        let perms = try FileManager.default.attributesOfItem(atPath: credURL.path)[.posixPermissions] as? NSNumber
        #expect(perms?.uint16Value == 0o600)

        let loaded = try store.loadCredential(id: accountA.id)
        #expect(loaded.tokens.refreshToken.hasPrefix("refresh-a"))
        #expect(loaded.redactedDescription.contains("refresh-a") == false)

        try store.saveOfficialAuth(authB)
        try store.setActiveAccountId(accountB.id)
        index = try store.loadIndex()
        #expect(index.activeAccountId == accountB.id)

        let officialLoaded = try store.loadOfficialAuth()
        #expect(officialLoaded.tokens.accountId == "acct-b")
    }

    @Test("deduplicates by account identity on re-import")
    func deduplicates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-dedup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(
            rootURL: root.appendingPathComponent("accounts"),
            officialAuthURL: root.appendingPathComponent("auth.json"))

        let first = try store.upsert(
            auth: sampleAuth(accountId: "same", email: "same@example.com", refresh: "rt-1"),
            makeActive: true)
        let second = try store.upsert(
            auth: sampleAuth(accountId: "same", email: "same@example.com", refresh: "rt-2"),
            makeActive: false)

        #expect(first.id == second.id)
        let index = try store.loadIndex()
        #expect(index.accounts.count == 1)
        let cred = try store.loadCredential(id: first.id)
        #expect(cred.tokens.refreshToken.hasPrefix("rt-2"))
    }

    @Test("session access-token-only credentials are usable while JWT is valid")
    func sessionAccessTokenOnlyUsable() {
        let access = Self.jwt(payload: [
            "email": "session@example.com",
            "exp": 4_100_000_000,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "sess-1",
                "chatgpt_plan_type": "free",
            ],
        ])
        let auth = CodexAuth(
            authMode: "chatgpt",
            tokens: .init(idToken: access, accessToken: access, refreshToken: "", accountId: "sess-1"),
            lastRefresh: nil)
        #expect(auth.isAccessTokenOnly)
        #expect(auth.loginUsability == .usable)

        let expired = Self.jwt(payload: ["exp": 1_700_000_000, "email": "x@y.z"])
        let expiredAuth = CodexAuth(
            authMode: "chatgpt",
            tokens: .init(idToken: expired, accessToken: expired, refreshToken: "", accountId: "sess-1"),
            lastRefresh: nil)
        #expect(expiredAuth.loginUsability == .expiredAccessWithoutRefresh)
    }

    @Test("withIdentity prefers JWT plan over stale metadata when quota plan is omitted")
    func withIdentityPrefersLivePlan() {
        let proAuth = sampleAuth(accountId: "acct", email: "a@example.com", refresh: "r1", plan: "pro")
        var account = ManagedAccount.make(auth: proAuth, sortIndex: 0)
        #expect(account.subscriptionTier == .pro20x || account.planType?.contains("pro") == true)

        let freeAuth = sampleAuth(accountId: "acct", email: "a@example.com", refresh: "r2", plan: "free")
        account = account.withIdentity(from: freeAuth, quotaPlan: nil)
        #expect(account.planType?.lowercased().contains("free") == true)
        #expect(account.subscriptionTier == .free)
    }

    @Test("orders sidebar with active account first")
    func sidebarOrder() {
        var index = AccountIndex(activeAccountId: "b", accounts: [
            ManagedAccount(id: "a", sortIndex: 0, displayName: "A"),
            ManagedAccount(id: "b", sortIndex: 2, displayName: "B"),
            ManagedAccount(id: "c", sortIndex: 1, displayName: "C"),
        ])
        #expect(index.orderedForSidebar().map(\.id) == ["b", "a", "c"])
        index.reindexSortOrder(["c", "a", "b"])
        #expect(index.account(id: "c")?.sortIndex == 0)
        #expect(index.account(id: "a")?.sortIndex == 1)
    }

    @Test("imports API key accounts without oauth tokens")
    func apiKeyAccount() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-apikey-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(
            rootURL: root.appendingPathComponent("accounts"),
            officialAuthURL: root.appendingPathComponent("auth.json"))
        let importer = AccountImporter(store: store)
        let account = try importer.importAPIKey("sk-test-key-1234567890")
        #expect(account.authMode == .apiKey)
        #expect(account.subscriptionTier == .api)
        let auth = try store.loadCredential(id: account.id)
        #expect(auth.isAPIKeyAuth)
        #expect(auth.openAIAPIKey == "sk-test-key-1234567890")
        #expect(auth.redactedDescription.contains("sk-test") == false)
    }

    @Test("parses pasted auth json and bare refresh token shapes")
    func parsesPasteFormats() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-paste-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(
            rootURL: root.appendingPathComponent("accounts"),
            officialAuthURL: root.appendingPathComponent("auth.json"))

        // Avoid network: import via store decode path for full auth object.
        let authJSON = """
        {
          "auth_mode": "chatgpt",
          "tokens": {
            "access_token": "\(Self.jwt(exp: 4_100_000_000))",
            "refresh_token": "refresh-paste",
            "account_id": "paste-1",
            "id_token": "\(Self.jwt(payload: ["email": "paste@example.com", "https://api.openai.com/auth": ["chatgpt_account_id": "paste-1"]]))"
          }
        }
        """
        let importer = AccountImporter(store: store, tokenRefresher: TokenRefresher())
        let batch = await importer.importPastedText(authJSON)
        #expect(batch.successCount == 1)
        #expect(batch.succeeded.first?.email == "paste@example.com" || batch.succeeded.first?.accountId == "paste-1")
    }

    @Test("parses ChatGPT /auth/session JSON with camelCase accessToken")
    func parsesAuthSessionJSON() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(
            rootURL: root.appendingPathComponent("accounts"),
            officialAuthURL: root.appendingPathComponent("auth.json"))

        let access = Self.jwt(payload: [
            "email": "session@example.com",
            "exp": 4_100_000_000,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "sess-acct-1",
                "chatgpt_plan_type": "plus",
            ],
        ])
        let sessionJSON = """
        {
          "user": {
            "id": "user-1",
            "email": "session@example.com",
            "name": "Session User"
          },
          "expires": "2099-01-01T00:00:00.000Z",
          "account": {
            "id": "sess-acct-1",
            "planType": "plus",
            "structure": "personal"
          },
          "accessToken": "\(access)",
          "authProvider": "openai"
        }
        """
        let importer = AccountImporter(store: store, tokenRefresher: TokenRefresher())
        let batch = await importer.importPastedText(sessionJSON)
        #expect(batch.successCount == 1)
        #expect(batch.failures.isEmpty)
        #expect(batch.succeeded.first?.email == "session@example.com")
        #expect(batch.succeeded.first?.accountId == "sess-acct-1")
        let cred = try! store.loadCredential(id: batch.succeeded[0].id)
        #expect(cred.tokens.accessToken == access)
        #expect(cred.tokens.accountId == "sess-acct-1")
    }

    @Test("paste of unrecognized JSON reports no_credentials failure")
    func pasteUnrecognizedJSONFailsClearly() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-badpaste-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AccountStore(
            rootURL: root.appendingPathComponent("accounts"),
            officialAuthURL: root.appendingPathComponent("auth.json"))
        let importer = AccountImporter(store: store)
        let batch = await importer.importPastedText(#"{"hello":"world","foo":1}"#)
        #expect(batch.successCount == 0)
        #expect(batch.failures == ["no_credentials"])
    }

    @Test("syncs when official auth changes externally")
    func syncsOfficial() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let official = root.appendingPathComponent("auth.json")
        let store = AccountStore(rootURL: root.appendingPathComponent("accounts"), officialAuthURL: official)

        try store.saveOfficialAuth(sampleAuth(accountId: "one", email: "one@example.com", refresh: "r1"))
        _ = try store.importOfficialAuth(makeActive: true)
        try store.saveOfficialAuth(sampleAuth(accountId: "two", email: "two@example.com", refresh: "r2"))
        let index = try store.syncFromOfficialAuth()
        #expect(index.accounts.count == 2)
        #expect(index.activeAccountId != nil)
        let active = index.account(id: index.activeAccountId!)
        #expect(active?.accountId == "two" || active?.email == "two@example.com")
    }

    @Test("oauth session builds authorize url with pkce params")
    func oauthSession() throws {
        let session = try CodexOAuthLogin.startSession(port: 1455)
        #expect(session.authURL.absoluteString.contains("code_challenge="))
        #expect(session.authURL.absoluteString.contains("client_id="))
        #expect(session.redirectURI.contains("1455"))
        let callback = URL(string: "http://localhost:1455/auth/callback?code=abc&state=\(session.state)")!
        let code = try CodexOAuthLogin.authorizationCode(from: callback, expectedState: session.state)
        #expect(code == "abc")
    }

    private func sampleAuth(
        accountId: String,
        email: String,
        refresh: String,
        plan: String = "plus") -> CodexAuth
    {
        let idToken = Self.jwt(payload: [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountId,
                "chatgpt_plan_type": plan,
            ],
        ])
        // loginUsability requires a long refresh token so short fixtures pad out.
        let refreshToken = refresh.count >= 20 ? refresh : (refresh + String(repeating: "x", count: 24))
        return CodexAuth(
            authMode: "chatgpt",
            tokens: .init(
                idToken: idToken,
                accessToken: Self.jwt(exp: 4_100_000_000),
                refreshToken: refreshToken,
                accountId: accountId),
            lastRefresh: nil,
            planType: plan)
    }

    private static func jwt(exp: Int) -> String {
        jwt(payload: ["exp": exp])
    }

    private static func jwt(payload: [String: Any]) -> String {
        let header = #"{"alg":"none"}"#.data(using: .utf8)!
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return [header, payloadData, Data()]
            .map { $0.base64EncodedString().urlSafeBase64 }
            .joined(separator: ".")
    }
}

private extension String {
    var urlSafeBase64: String {
        replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
