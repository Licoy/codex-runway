import Foundation

enum ResetCreditState: Sendable, Equatable {
    case available
    case expiring
    case unavailable
}

struct ResetCreditDetail: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var statusText: String
    var state: ResetCreditState
    var expiresAt: Date?
    var remainingDuration: TimeInterval
    var remainingProgress: Double
}
