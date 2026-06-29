import CodexRunwayCore
import Foundation

enum SelfCheck {
    static func run() {
        let store = CodexAuthStore()
        do {
            let auth = try store.load()
            print(auth.redactedDescription)
            print(TokenInspector.isExpired(auth.tokens.accessToken) ? "token: expired" : "token: valid")
            print(sessionSummary())
        } catch {
            print("auth: unavailable (\(error.localizedDescription))")
        }
    }

    private static func sessionSummary() -> String {
        do {
            let report = try SessionRepairService().dryRun()
            return "sessions: \(report.plannedEntries), missing: \(report.missingIndexIDs.count), orphan: \(report.orphanIndexIDs.count)"
        } catch {
            return "sessions: unavailable"
        }
    }
}
