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
