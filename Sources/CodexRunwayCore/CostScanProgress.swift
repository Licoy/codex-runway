import Foundation

/// Lightweight phases for local/online API-equivalent cost scans.
/// Payload stays small (counts + short labels) so MainActor updates stay cheap.
public enum CostScanPhase: String, Sendable, Equatable, Hashable {
    case idle
    case preparing
    case refreshingIndex
    case aggregating
    case fetchingOnline
    case finished
    case failed
}

public struct CostScanProgress: Sendable, Equatable, Hashable {
    public var phase: CostScanPhase
    public var completedUnits: Int
    public var totalUnits: Int?
    public var detail: String?
    public var message: String?

    public init(
        phase: CostScanPhase = .idle,
        completedUnits: Int = 0,
        totalUnits: Int? = nil,
        detail: String? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.detail = detail
        self.message = message
    }

    public var fraction: Double? {
        guard let totalUnits, totalUnits > 0 else { return nil }
        return min(1, max(0, Double(completedUnits) / Double(totalUnits)))
    }

    public var isActive: Bool {
        switch phase {
        case .preparing, .refreshingIndex, .aggregating, .fetchingOnline:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }

    public static let idle = CostScanProgress(phase: .idle)
    public static let preparing = CostScanProgress(phase: .preparing)

    public static func refreshingIndex(
        completed: Int,
        total: Int,
        currentFile: String? = nil
    ) -> CostScanProgress {
        CostScanProgress(
            phase: .refreshingIndex,
            completedUnits: completed,
            totalUnits: total,
            detail: currentFile)
    }

    public static func aggregating(completed: Int = 0, total: Int? = nil) -> CostScanProgress {
        CostScanProgress(phase: .aggregating, completedUnits: completed, totalUnits: total)
    }

    public static let fetchingOnline = CostScanProgress(phase: .fetchingOnline)
    public static let finished = CostScanProgress(phase: .finished)

    public static func failed(_ message: String? = nil) -> CostScanProgress {
        CostScanProgress(phase: .failed, message: message)
    }
}

/// Thread-safe progress sink used by the cost repository worker.
public final class CostScanProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (CostScanProgress) -> Void)?
    private var lastPublishedAt: Date = .distantPast
    private let minimumInterval: TimeInterval

    public init(
        minimumInterval: TimeInterval = 0.1,
        onProgress: (@Sendable (CostScanProgress) -> Void)? = nil
    ) {
        self.minimumInterval = minimumInterval
        self.handler = onProgress
    }

    public func setHandler(_ onProgress: (@Sendable (CostScanProgress) -> Void)?) {
        lock.lock()
        handler = onProgress
        lock.unlock()
    }

    public func report(_ progress: CostScanProgress, force: Bool = false) {
        lock.lock()
        let handler = self.handler
        let now = Date()
        let shouldPublish: Bool
        if force || !progress.isActive || progress.phase != .refreshingIndex {
            shouldPublish = true
        } else {
            shouldPublish = now.timeIntervalSince(lastPublishedAt) >= minimumInterval
        }
        if shouldPublish {
            lastPublishedAt = now
        }
        lock.unlock()
        guard shouldPublish, let handler else { return }
        handler(progress)
    }
}
