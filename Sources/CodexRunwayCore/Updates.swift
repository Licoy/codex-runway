import Foundation

public struct AppVersion: Comparable, Sendable {
    public let rawValue: String
    private let parts: [Int]

    public init?(_ value: String) {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") {
            cleaned = String(cleaned.dropFirst())
        }
        let parts = cleaned.split(separator: ".").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        self.rawValue = cleaned
        self.parts = parts.compactMap(Int.init)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let htmlURL: URL?
    public let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    public func asset(named name: String) -> GitHubReleaseAsset? {
        assets.first { $0.name == name }
    }
}

public struct GitHubReleaseAsset: Decodable, Sendable {
    public let name: String
    public let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case updateAvailable(String)
    case failed(String)

    public static func fromHTTP(statusCode: Int, data: Data, currentVersion: String) -> UpdateCheckResult {
        if statusCode == 404 { return .upToDate }
        guard (200..<300).contains(statusCode) else {
            return .failed("HTTP \(statusCode)")
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let latest = AppVersion(release.tagName),
              let current = AppVersion(currentVersion)
        else {
            return .upToDate
        }
        return latest > current ? .updateAvailable(release.tagName) : .upToDate
    }
}

public enum UpdateInstallReadiness: Equatable, Sendable {
    case ready
    case developmentMode
    case signingKeyMissing
}

public struct UpdateInstallEnvironment: Sendable {
    public let bundlePathExtension: String
    public let sparklePublicKey: String?
    public let hasUpdater: Bool

    public init(bundlePathExtension: String, sparklePublicKey: String?, hasUpdater: Bool) {
        self.bundlePathExtension = bundlePathExtension
        self.sparklePublicKey = sparklePublicKey
        self.hasUpdater = hasUpdater
    }

    public var readiness: UpdateInstallReadiness {
        guard bundlePathExtension.lowercased() == "app" else { return .developmentMode }
        guard Self.hasValidSparklePublicKey(sparklePublicKey), hasUpdater else { return .signingKeyMissing }
        return .ready
    }

    public static func hasValidSparklePublicKey(_ key: String?) -> Bool {
        guard let key else { return false }
        return !key.isEmpty && !key.contains("__")
    }
}
