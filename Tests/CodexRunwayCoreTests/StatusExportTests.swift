import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Runway status export")
struct StatusExportTests {
    @Test("status export writes derived state without auth secrets")
    func statusExportOmitsAuthSecrets() throws {
        let root = try TemporaryDirectory()
        let url = root.url.appending(path: "status.json")
        let now = ISO8601DateFormatter().date(from: "2026-06-30T10:00:00Z")!
        let totals = ApiEquivalentTotals(
            totalTokens: 1_000,
            uncachedInputTokens: 700,
            cachedInputTokens: 200,
            outputTokens: 100,
            turns: 3,
            threads: 1)
        let cost = ApiEquivalentSummary(
            source: .localSessions,
            confidence: .priced,
            window: DateInterval(start: now.addingTimeInterval(-3_600), end: now),
            estimatedUSD: 1.25,
            totals: totals,
            dailyRows: [],
            modelRows: [],
            projectRows: [
                ApiEquivalentBreakdownRow(name: "codex-runway", totals: totals, estimatedUSD: 1.25, rawCredits: 0),
            ],
            clientRows: [],
            rawCredits: 0,
            warnings: [],
            pricingVersion: "test",
            calculatedAt: now)
        let sessions = SessionActivitySummary(items: [
            SessionActivityItem(
                id: "s1",
                title: "Fix status",
                projectName: "codex-runway",
                cwd: "/Users/me/dev/codex-runway",
                updatedAt: now,
                state: .recent,
                totals: totals,
                estimatedUSD: 1.25),
        ])
        let snapshot = RunwayStatusSnapshot(
            generatedAt: now,
            quota: nil,
            cost: cost,
            sessions: sessions)

        try RunwayStatusExporter(statusURL: url).save(snapshot)
        let text = try String(contentsOf: url)

        #expect(text.contains("codex-runway"))
        #expect(text.contains("projectRows"))
        #expect(text.contains("access_token") == false)
        #expect(text.contains("refresh_token") == false)
        #expect(text.contains("id_token") == false)
    }
}

private struct TemporaryDirectory {
    let url: URL

    init() throws {
        self.url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
