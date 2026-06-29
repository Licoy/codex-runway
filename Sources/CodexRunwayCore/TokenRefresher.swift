import Foundation

public struct TokenRefresher {
    public var session: URLSession
    public var tokenURL: URL

    public init(
        session: URLSession = .shared,
        tokenURL: URL = URL(string: "https://auth.openai.com/oauth/token")!)
    {
        self.session = session
        self.tokenURL = tokenURL
    }

    public func refresh(_ auth: inout CodexAuth, store: CodexAuthStore? = nil) async throws {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(auth.tokens.refreshToken.urlFormEncoded)"
        request.httpBody = Data(body.utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.userAuthenticationRequired)
        }
        try auth.mergeRefreshResponse(data)
        try store?.save(auth)
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
