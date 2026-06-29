import Foundation

public struct CodexAuthStore: Sendable {
    public var authURL: URL

    public init(authURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")) {
        self.authURL = authURL
    }

    public func load() throws -> CodexAuth {
        let data = try Data(contentsOf: authURL)
        return try JSONDecoder().decode(CodexAuth.self, from: data)
    }

    public func save(_ auth: CodexAuth) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        let temporary = authURL.deletingLastPathComponent().appendingPathComponent(".auth.json.tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .completeFileProtectionUnlessOpen)
        _ = try FileManager.default.replaceItemAt(authURL, withItemAt: temporary)
    }
}
