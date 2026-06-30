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
