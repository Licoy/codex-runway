import Foundation
import Testing
@testable import CodexRunwayCore

@Suite("Usage cost scanner")
struct CostScannerTests {
    @Test("aggregates token_count events inside the selected window")
    func aggregatesTokenCounts() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let file = sessionDir.appending(path: "rollout-test.jsonl")
        try """
        {"timestamp":"2026-06-28T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":999,"cached_input_tokens":0,"output_tokens":999,"reasoning_output_tokens":0}}},"rate_limits":{"plan_type":"pro"}}
        {"timestamp":"2026-06-29T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":50,"reasoning_output_tokens":10}}},"turn_context":{"model":"gpt-5.5"}}
        {"timestamp":"2026-06-29T00:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":25,"reasoning_output_tokens":0}}},"turn_context":{"model":"unknown-model"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let summary = try UsageCostScanner(codexHome: root.url).scan(
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-29T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-06-29T01:00:00Z")!))

        #expect(summary.totals.inputTokens == 1_500)
        #expect(summary.totals.cachedInputTokens == 200)
        #expect(summary.totals.outputTokens == 85)
        #expect(summary.estimatedUSD > 0)
        #expect(summary.unknownModels == ["unknown-model"])
    }

    @Test("uses latest turn context model for following token count events")
    func usesTurnContextModel() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let file = sessionDir.appending(path: "rollout-context-model.jsonl")
        try """
        {"timestamp":"2026-06-29T00:00:00Z","type":"turn_context","payload":{"model":"gpt-5.5"}}
        {"timestamp":"2026-06-29T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0}}}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let summary = try UsageCostScanner(codexHome: root.url).scan(
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-29T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-06-29T01:00:00Z")!))

        #expect(summary.modelBreakdown.map(\.model) == ["gpt-5.5"])
        #expect(summary.unknownModels.isEmpty)
        #expect(summary.estimatedUSD > 0)
    }

    @Test("detects relevant session files from dated paths")
    func detectsRelevantDatedPaths() {
        let scanner = UsageCostScanner(codexHome: URL(fileURLWithPath: "/tmp/.codex"))
        let window = DateInterval(
            start: ISO8601DateFormatter().date(from: "2026-06-29T00:00:00Z")!,
            end: ISO8601DateFormatter().date(from: "2026-06-29T05:00:00Z")!)

        #expect(scanner.isLikelyRelevant(
            URL(fileURLWithPath: "/tmp/.codex/sessions/2026/06/29/rollout-a.jsonl"),
            window: window))
        #expect(scanner.isLikelyRelevant(
            URL(fileURLWithPath: "/tmp/.codex/sessions/2026/03/29/rollout-a.jsonl"),
            window: window) == false)
    }

    @Test("local API equivalent scans the weekly window and falls back for unknown models")
    func localAPIEquivalentUsesWeeklyWindow() throws {
        let root = try TemporaryDirectory()
        let calculatedAt = ISO8601DateFormatter().date(from: "2026-06-30T10:00:00Z")!
        let sessionDir = root.url.appending(path: "sessions/2026/06/25", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let file = sessionDir.appending(path: "rollout-weekly.jsonl")
        try """
        {"timestamp":"2026-06-25T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":50,"reasoning_output_tokens":10}}},"turn_context":{"model":"gpt-5.3-codex"}}
        {"timestamp":"2026-06-29T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":25,"reasoning_output_tokens":0}}},"turn_context":{"model":"unknown-model"}}
        """.write(to: file, atomically: true, encoding: .utf8)

        let summary = try UsageCostScanner(codexHome: root.url).scanAPIEquivalent(
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-24T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!),
            calculatedAt: calculatedAt)

        #expect(summary.calculatedAt == calculatedAt)
        #expect(summary.source == .localSessions)
        #expect(summary.confidence == .priced)
        #expect(summary.totals.uncachedInputTokens == 1_300)
        #expect(summary.totals.cachedInputTokens == 200)
        #expect(summary.totals.outputTokens == 85)
        #expect(summary.totals.turns == 2)
        #expect(summary.dailyRows.map(\.date) == ["2026-06-25", "2026-06-29"])
        #expect(summary.dailyRows[0].estimatedUSD != summary.estimatedUSD)
        #expect(summary.modelRows.map(\.name) == ["gpt-5.3-codex", "unknown-model"])
        #expect(summary.estimatedUSD ?? 0 > 0)
        #expect(summary.warnings.isEmpty == false)
    }

    @Test("local API equivalent groups usage by project cwd")
    func localAPIEquivalentGroupsProjects() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-06-29T00:00:00Z","type":"session_meta","payload":{"id":"s1","cwd":"/Users/me/dev/codex-runway"}}
        {"timestamp":"2026-06-29T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":0}}},"turn_context":{"model":"gpt-5.5"}}
        """.write(to: sessionDir.appending(path: "rollout-project.jsonl"), atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-06-29T00:02:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":25,"reasoning_output_tokens":0}}},"turn_context":{"model":"gpt-5.5"}}
        """.write(to: sessionDir.appending(path: "rollout-unknown.jsonl"), atomically: true, encoding: .utf8)

        let summary = try UsageCostScanner(codexHome: root.url).scanAPIEquivalent(
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-29T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-06-30T00:00:00Z")!))

        #expect(summary.projectRows.map(\.name) == ["codex-runway", "Unknown project"])
        #expect(summary.projectRows[0].totals.totalTokens == 1_050)
        #expect(summary.projectRows[1].totals.totalTokens == 525)
    }

    @Test("project cwd before selected window still groups in-window tokens")
    func projectCWDCanPrecedeWindow() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-06-28T23:59:00Z","type":"session_meta","payload":{"id":"s1","cwd":"/Users/me/dev/codex-runway"}}
        {"timestamp":"2026-06-29T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0}}},"turn_context":{"model":"gpt-5.5"}}
        """.write(to: sessionDir.appending(path: "rollout-project-before-window.jsonl"), atomically: true, encoding: .utf8)

        let summary = try UsageCostScanner(codexHome: root.url).scanAPIEquivalent(
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-29T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-06-30T00:00:00Z")!))

        #expect(summary.projectRows.map(\.name) == ["codex-runway"])
    }

    @Test("turn context cwd groups API equivalent projects")
    func turnContextCWDGroupsProjects() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        try """
        {"timestamp":"2026-06-29T00:00:00Z","type":"turn_context","payload":{"cwd":"/Users/me/dev/codex-runway","model":"gpt-5.5"}}
        {"timestamp":"2026-06-29T00:01:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0}}}}
        """.write(to: sessionDir.appending(path: "rollout-codex-runway.jsonl"), atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-06-29T00:02:00Z","type":"turn_context","payload":{"cwd":"/Users/me/dev/aqbot","model":"gpt-5.5"}}
        {"timestamp":"2026-06-29T00:03:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0}}}}
        """.write(to: sessionDir.appending(path: "rollout-aqbot.jsonl"), atomically: true, encoding: .utf8)

        let summary = try UsageCostScanner(codexHome: root.url).scanAPIEquivalent(
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-29T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-06-30T00:00:00Z")!))

        #expect(summary.projectRows.map(\.name) == ["codex-runway", "aqbot"])
        #expect(summary.projectRows.map(\.totals.totalTokens) == [1_020, 510])
    }

    @Test("session activity scanner summarizes recent Codex sessions")
    func sessionActivitySummarizesRecentSessions() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let sessionID = "019f17a5-436d-73b2-a93d-7af3e78cc827"
        try """
        {"id":"\(sessionID)","thread_name":"Status bar quota fix","updated_at":"2026-06-29T00:04:00Z"}
        """.write(to: root.url.appending(path: "session_index.jsonl"), atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-06-29T00:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","cwd":"/Users/me/dev/codex-runway"}}
        {"timestamp":"2026-06-29T00:01:00Z","type":"event_msg","payload":{"type":"message","role":"user","content":"Fix the status bar"}}
        {"timestamp":"2026-06-29T00:02:00Z","type":"event_msg","payload":{"type":"approval_request"}}
        {"timestamp":"2026-06-29T00:03:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":50,"reasoning_output_tokens":0}}},"turn_context":{"model":"gpt-5.5"}}
        """.write(to: sessionDir.appending(path: "rollout-\(sessionID).jsonl"), atomically: true, encoding: .utf8)

        let summary = try SessionActivityScanner(codexHome: root.url).scan(limit: 5)
        let session = try #require(summary.items.first)

        #expect(session.title == "Status bar quota fix")
        #expect(session.projectName == "codex-runway")
        #expect(session.state == .needsAttention)
        #expect(session.totals.totalTokens == 1_050)
        #expect(session.estimatedUSD ?? 0 > 0)
    }

    @Test("session activity scanner uses index titles but sorts by file activity")
    func sessionActivityUsesIndexTitlesButSortsByFileActivity() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let firstID = "11111111-1111-4111-8111-111111111111"
        let secondID = "22222222-2222-4222-8222-222222222222"
        try """
        {"id":"\(firstID)","thread_name":"Index newest","updated_at":"2026-06-30T00:00:00Z"}
        {"id":"\(secondID)","thread_name":"File newest","updated_at":"2026-06-29T00:00:00Z"}
        """.write(to: root.url.appending(path: "session_index.jsonl"), atomically: true, encoding: .utf8)
        try sessionFile(id: firstID, timestamp: "2026-06-28T00:00:00Z", title: "Old file title")
            .write(to: sessionDir.appending(path: "rollout-\(firstID).jsonl"), atomically: true, encoding: .utf8)
        try sessionFile(id: secondID, timestamp: "2026-06-29T00:00:00Z", title: "New file title")
            .write(to: sessionDir.appending(path: "rollout-\(secondID).jsonl"), atomically: true, encoding: .utf8)

        let summary = try SessionActivityScanner(codexHome: root.url).scan(limit: 2)

        #expect(summary.items.map(\.id) == [secondID, firstID])
        #expect(summary.items.map(\.title) == ["File newest", "Index newest"])
    }

    @Test("session activity scanner includes newer unindexed sessions")
    func sessionActivityIncludesNewerUnindexedSessions() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let indexedID = "33333333-3333-4333-8333-333333333333"
        let unindexedID = "44444444-4444-4444-8444-444444444444"
        try """
        {"id":"\(indexedID)","thread_name":"Indexed session","updated_at":"2026-06-29T00:00:00Z"}
        """.write(to: root.url.appending(path: "session_index.jsonl"), atomically: true, encoding: .utf8)
        try sessionFile(id: indexedID, timestamp: "2026-06-29T00:00:00Z", title: "Indexed file")
            .write(to: sessionDir.appending(path: "rollout-\(indexedID).jsonl"), atomically: true, encoding: .utf8)
        try sessionFile(id: unindexedID, timestamp: "2026-07-01T00:00:00Z", title: "Unindexed newer file")
            .write(to: sessionDir.appending(path: "rollout-\(unindexedID).jsonl"), atomically: true, encoding: .utf8)

        let summary = try SessionActivityScanner(codexHome: root.url).scan(limit: 5)

        #expect(summary.items.map(\.id) == [unindexedID, indexedID])
        #expect(summary.items.map(\.title) == ["Unindexed newer file", "Indexed session"])
    }

    @Test("session activity scanner falls back to recent files without index")
    func sessionActivityFallsBackToRecentFilesWithoutIndex() throws {
        let root = try TemporaryDirectory()
        let sessionDir = root.url.appending(path: "sessions/2026/06/29", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        let oldID = "55555555-5555-4555-8555-555555555555"
        let newID = "66666666-6666-4666-8666-666666666666"
        let oldFile = sessionDir.appending(path: "rollout-\(oldID).jsonl")
        let newFile = sessionDir.appending(path: "rollout-\(newID).jsonl")
        try sessionFile(id: oldID, timestamp: "2026-06-29T00:00:00Z", title: "Old fallback")
            .write(to: oldFile, atomically: true, encoding: .utf8)
        try sessionFile(id: newID, timestamp: "2026-06-29T00:01:00Z", title: "New fallback")
            .write(to: newFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: ISO8601DateFormatter().date(from: "2026-06-29T00:00:00Z")!],
            ofItemAtPath: oldFile.path)
        try FileManager.default.setAttributes(
            [.modificationDate: ISO8601DateFormatter().date(from: "2026-06-29T00:10:00Z")!],
            ofItemAtPath: newFile.path)

        let summary = try SessionActivityScanner(codexHome: root.url).scan(limit: 1)

        #expect(summary.items.map(\.id) == [newID])
        #expect(summary.items.first?.title == "New fallback")
    }

    @Test("online analytics estimates dollars from token parts even when credits are zero")
    func analyticsCreditsZeroStillPricesTokenParts() throws {
        let calculatedAt = ISO8601DateFormatter().date(from: "2026-06-30T10:00:00Z")!
        let data = """
        {"data":[{"date":"2026-06-29","totals":{"credits":0,"turns":26,"threads":4,"cached_text_input_tokens":1000000,"uncached_text_input_tokens":2000000,"text_output_tokens":300000}}]}
        """.data(using: .utf8)!

        let summary = try ApiEquivalentSummary.decodeAnalytics(
            from: data,
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-24T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!),
            calculatedAt: calculatedAt)

        #expect(summary.calculatedAt == calculatedAt)
        #expect(summary.source == .onlineAnalytics)
        #expect(summary.confidence == .priced)
        #expect(summary.rawCredits == 0)
        #expect(summary.totals.totalTokens == 3_300_000)
        #expect(summary.totals.turns == 26)
        #expect(summary.estimatedUSD ?? 0 > 0)
    }

    @Test("online analytics with only total tokens is tokens only")
    func analyticsTotalOnlyIsTokensOnly() throws {
        let data = #"{"data":[{"date":"2026-06-29","totals":{"credits":0,"turns":1,"text_total_tokens":12000}}]}"#
            .data(using: .utf8)!

        let summary = try ApiEquivalentSummary.decodeAnalytics(
            from: data,
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-24T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!))

        #expect(summary.confidence == .tokensOnly)
        #expect(summary.totals.totalTokens == 12_000)
        #expect(summary.estimatedUSD == nil)
    }

    @Test("displayable cost excludes unavailable zero token analytics")
    func displayableCostExcludesUnavailableZeroTokenAnalytics() throws {
        let window = DateInterval(
            start: ISO8601DateFormatter().date(from: "2026-06-24T00:00:00Z")!,
            end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!)
        let unavailable = try ApiEquivalentSummary.decodeAnalytics(
            from: #"{"data":[{"date":"2026-06-29","totals":{"credits":0,"turns":0,"text_total_tokens":0}}]}"#.data(using: .utf8)!,
            window: window)
        let tokensOnly = try ApiEquivalentSummary.decodeAnalytics(
            from: #"{"data":[{"date":"2026-06-29","totals":{"credits":0,"turns":1,"text_total_tokens":12000}}]}"#.data(using: .utf8)!,
            window: window)
        let priced = try ApiEquivalentSummary.decodeAnalytics(
            from: #"{"data":[{"date":"2026-06-29","totals":{"credits":0,"turns":1,"uncached_text_input_tokens":1000,"text_output_tokens":100}}]}"#.data(using: .utf8)!,
            window: window)

        #expect(unavailable.isDisplayableCost == false)
        #expect(tokensOnly.isDisplayableCost)
        #expect(priced.isDisplayableCost)
    }

    @Test("cost detail splits token classes and hides unknown models")
    func costDetailSplitsTokenClasses() {
        let summary = UsageCostSummary(
            window: DateInterval(start: .now, duration: 60),
            totals: TokenUsage(inputTokens: 1_000, cachedInputTokens: 300, outputTokens: 200),
            modelBreakdown: [
                ModelCostBreakdown(model: "gpt-5.5", usage: TokenUsage(inputTokens: 700, cachedInputTokens: 200, outputTokens: 100), estimatedUSD: 2),
                ModelCostBreakdown(model: "unknown-model", usage: TokenUsage(inputTokens: 300, cachedInputTokens: 100, outputTokens: 100), estimatedUSD: 0),
            ],
            estimatedUSD: 2,
            pricingVersion: "test",
            unknownModels: ["unknown-model"])

        let detail = UsageCostDetail(summary: summary)

        #expect(detail.uncachedInputTokens == 700)
        #expect(detail.cachedInputTokens == 300)
        #expect(detail.outputTokens == 200)
        #expect(detail.totalTokens == 1_200)
        #expect(detail.models.map(\.model) == ["gpt-5.5"])
        #expect(detail.models.first?.costShare == 1)
    }

    @Test("zero cost detail uses zero model share")
    func zeroCostDetailUsesZeroShare() {
        let summary = UsageCostSummary(
            window: DateInterval(start: .now, duration: 60),
            totals: TokenUsage(inputTokens: 1, cachedInputTokens: 0, outputTokens: 1),
            modelBreakdown: [
                ModelCostBreakdown(model: "gpt-5.5", usage: TokenUsage(inputTokens: 1, cachedInputTokens: 0, outputTokens: 1), estimatedUSD: 0),
            ],
            estimatedUSD: 0,
            pricingVersion: "test",
            unknownModels: [])

        #expect(UsageCostDetail(summary: summary).models.first?.costShare == 0)
    }

    @Test("cost cache stores and loads the calculated summary")
    func costCacheStoresSummary() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appending(path: "api-equivalent-cost.json")
        let calculatedAt = ISO8601DateFormatter().date(from: "2026-06-30T10:00:00Z")!
        let summary = ApiEquivalentSummary(
            source: .localSessions,
            confidence: .priced,
            window: DateInterval(
                start: ISO8601DateFormatter().date(from: "2026-06-24T00:00:00Z")!,
                end: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!),
            estimatedUSD: 1.25,
            totals: ApiEquivalentTotals(
                totalTokens: 1_000,
                uncachedInputTokens: 700,
                cachedInputTokens: 200,
                outputTokens: 100,
                turns: 3,
                threads: 1),
            dailyRows: [
                ApiEquivalentDailyRow(
                    date: "2026-06-29",
                    totals: ApiEquivalentTotals(
                        totalTokens: 1_000,
                        uncachedInputTokens: 700,
                        cachedInputTokens: 200,
                        outputTokens: 100,
                        turns: 3,
                        threads: 1),
                    estimatedUSD: 1.25,
                    rawCredits: 0),
            ],
            modelRows: [
                ApiEquivalentBreakdownRow(
                    name: "gpt-5.5",
                    totals: ApiEquivalentTotals(
                        totalTokens: 1_000,
                        uncachedInputTokens: 700,
                        cachedInputTokens: 200,
                        outputTokens: 100,
                        turns: 3,
                        threads: 1),
                    estimatedUSD: 1.25,
                    rawCredits: 0),
            ],
            projectRows: [
                ApiEquivalentBreakdownRow(
                    name: "codex-runway",
                    totals: ApiEquivalentTotals(
                        totalTokens: 1_000,
                        uncachedInputTokens: 700,
                        cachedInputTokens: 200,
                        outputTokens: 100,
                        turns: 3,
                        threads: 1),
                    estimatedUSD: 1.25,
                    rawCredits: 0),
            ],
            clientRows: [],
            rawCredits: 0,
            warnings: [],
            pricingVersion: "test",
            calculatedAt: calculatedAt)
        let store = UsageCostCacheStore(cacheURL: cacheURL)

        try store.save(summary)
        let loaded = try #require(store.load())

        #expect(loaded == summary)
    }

    @Test("cost cache ignores missing or corrupt files")
    func costCacheIgnoresMissingOrCorruptFiles() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appending(path: "api-equivalent-cost.json")
        let store = UsageCostCacheStore(cacheURL: cacheURL)

        #expect(store.load() == nil)
        try "not-json".write(to: cacheURL, atomically: true, encoding: .utf8)

        #expect(store.load() == nil)
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

private func sessionFile(id: String, timestamp: String, title: String) -> String {
    """
    {"timestamp":"\(timestamp)","type":"session_meta","payload":{"id":"\(id)","cwd":"/Users/me/dev/codex-runway"}}
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"message","role":"user","content":"\(title)"}}
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}}},"turn_context":{"model":"gpt-5.5"}}
    """
}
