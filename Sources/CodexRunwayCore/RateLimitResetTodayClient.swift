import Foundation

public struct RateLimitResetTodayClient: Sendable {
    public static let siteURL = URL(string: "https://hascodexratelimitreset.today/")!
    public static let statusURL = URL(string: "https://hascodexratelimitreset.today/api/status")!

    public var session: URLSession
    public var statusURL: URL

    public init(
        session: URLSession = .shared,
        statusURL: URL = RateLimitResetTodayClient.statusURL)
    {
        self.session = session
        self.statusURL = statusURL
    }

    public func fetchStatus(now: Date = Date()) async throws -> RateLimitResetTodaySnapshot {
        var request = URLRequest(url: statusURL)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try RateLimitResetTodaySnapshot.decode(from: data, fetchedAt: now)
    }
}
