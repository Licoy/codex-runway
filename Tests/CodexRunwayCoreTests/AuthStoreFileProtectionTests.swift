import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Auth store file protection")
struct AuthStoreFileProtectionTests {
    @Test("auth store writes credentials that remain readable")
    func authStoreWritesReadableCredentials() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-auth-\(UUID().uuidString)", isDirectory: true)
        let authURL = root.appendingPathComponent("auth.json")
        defer { Self.removeTemporaryDirectory(root) }

        let store = CodexAuthStore(authURL: authURL)
        try store.save(Self.storedAuth(accountId: "account-readable"))

        let loaded = try store.load()
        let attributes = try FileManager.default.attributesOfItem(atPath: authURL.path)

        #expect(loaded.tokens.accountId == "account-readable")
        #expect(
            attributes[.protectionKey] as? FileProtectionType
                == .completeUntilFirstUserAuthentication)
    }

    @Test("auth store replaces legacy protected credentials with readable data")
    func authStoreReplacesLegacyProtectedCredentials() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-auth-legacy-\(UUID().uuidString)", isDirectory: true)
        let authURL = root.appendingPathComponent("auth.json")
        defer { Self.removeTemporaryDirectory(root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: authURL, options: .completeFileProtectionUnlessOpen)

        let replacement = try Self.storedAuth(accountId: "account-recovered")
        let store = CodexAuthStore(authURL: authURL)
        try store.saveRawJSONData(JSONEncoder().encode(replacement))

        let loaded = try store.load()
        let attributes = try FileManager.default.attributesOfItem(atPath: authURL.path)

        #expect(loaded.tokens.accountId == "account-recovered")
        #expect(
            attributes[.protectionKey] as? FileProtectionType
                == .completeUntilFirstUserAuthentication)
    }

    @Test("account store keeps its index readable and restricted")
    func accountStoreKeepsIndexReadableAndRestricted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-runway-index-\(UUID().uuidString)", isDirectory: true)
        let accounts = root.appendingPathComponent("accounts", isDirectory: true)
        defer { Self.removeTemporaryDirectory(root) }

        let store = AccountStore(
            rootURL: accounts,
            officialAuthURL: root.appendingPathComponent("auth.json"))
        try store.saveIndex(AccountIndex())

        let loaded = try store.loadIndex()
        let rootAttributes = try FileManager.default.attributesOfItem(atPath: accounts.path)
        let indexAttributes = try FileManager.default.attributesOfItem(atPath: store.indexURL.path)

        #expect(loaded.accounts.isEmpty)
        #expect((rootAttributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o700)
        #expect((indexAttributes[.posixPermissions] as? NSNumber)?.uint16Value == 0o600)
        #expect(
            indexAttributes[.protectionKey] as? FileProtectionType
                == .completeUntilFirstUserAuthentication)
    }

    private static func storedAuth(accountId: String) throws -> CodexAuth {
        CodexAuth(
            authMode: "chatgpt",
            tokens: .init(
                idToken: try jwt(payload: ["account_id": accountId]),
                accessToken: try jwt(payload: ["exp": 4_100_000_000]),
                refreshToken: "refresh-token-not-for-production-use",
                accountId: accountId),
            lastRefresh: nil)
    }

    private static func jwt(payload: [String: Any]) throws -> String {
        let header = #"{"alg":"none"}"#.data(using: .utf8)!
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return [header, payloadData, Data()]
            .map(Self.urlSafeBase64)
            .joined(separator: ".")
    }

    private static func urlSafeBase64(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func removeTemporaryDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Issue.record("Failed to remove test directory: \(error.localizedDescription)")
        }
    }
}
