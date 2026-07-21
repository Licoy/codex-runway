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
        // Install a Codex-compatible auth.json: encode known fields, preserve any
        // non-conflicting keys that already exist (some Codex builds keep extras).
        var object: [String: Any] = [:]
        if let existing = try? Data(contentsOf: authURL),
           let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any]
        {
            object = parsed
        }

        let encoded = try auth.officialAuthJSONObject()
        for (key, value) in encoded {
            object[key] = value
        }
        // Strip runway-only metadata that can confuse Codex file watchers / parsers.
        object.removeValue(forKey: "plan_type")
        object.removeValue(forKey: "auth_file_plan_type")

        // Codex expects a refresh_token key even for session-style access tokens (may be "").
        if var tokens = object["tokens"] as? [String: Any] {
            if tokens["refresh_token"] == nil {
                tokens["refresh_token"] = ""
            }
            if let id = tokens["id_token"] as? String, id.isEmpty {
                tokens.removeValue(forKey: "id_token")
            }
            if let account = tokens["account_id"] as? String, account.isEmpty {
                tokens.removeValue(forKey: "account_id")
            }
            object["tokens"] = tokens
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try atomicWrite(data, to: authURL)
    }

    /// Install an already-encoded auth.json payload (preferred for account switch).
    public func saveRawJSONData(_ data: Data) throws {
        // Validate before installing.
        _ = try JSONDecoder().decode(CodexAuth.self, from: data)
        try atomicWrite(data, to: authURL)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".auth.json.tmp-\(UUID().uuidString)")
        try data.write(to: temporary, options: .completeFileProtectionUnlessOpen)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
