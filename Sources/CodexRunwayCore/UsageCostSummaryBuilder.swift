import Foundation

enum UsageCostSummaryBuilder {
    static func make(
        events: [UsageCostIndexedEvent],
        window: DateInterval,
        calculatedAt: Date,
        priceBook: UsageCostPriceBook,
        warnings: [String] = []
    ) -> ApiEquivalentSummary {
        let groups = group(events)
        let modelRows = modelRows(groups.byModel, priceBook: priceBook)
        let totals = groups.byDay.values.reduce(.zero, +)
        let unknownWarnings = groups.byModel.keys
            .filter { priceBook.priceForModel($0) == nil }
            .sorted()
            .map { "unknown-model:\($0)" }
        return ApiEquivalentSummary(
            source: totals.totalTokens > 0 ? .localSessions : .unavailable,
            confidence: totals.totalTokens > 0 ? .priced : .unavailable,
            window: window,
            estimatedUSD: modelRows.compactMap(\.estimatedUSD).reduce(Decimal(0), +),
            totals: totals,
            dailyRows: dailyRows(groups, priceBook: priceBook),
            modelRows: modelRows,
            projectRows: projectRows(groups.byProject, priceBook: priceBook),
            clientRows: [],
            rawCredits: 0,
            warnings: unknownWarnings + warnings,
            pricingVersion: priceBook.version,
            calculatedAt: calculatedAt)
    }

    private struct Groups {
        var byModel: [String: ApiEquivalentTotals] = [:]
        var byProject: [String: ApiEquivalentTotals] = [:]
        var byDay: [String: ApiEquivalentTotals] = [:]
        var byDayModel: [String: [String: ApiEquivalentTotals]] = [:]
    }

    private static func group(_ events: [UsageCostIndexedEvent]) -> Groups {
        events.reduce(into: Groups()) { result, event in
            let totals = ApiEquivalentTotals(
                totalTokens: event.uncachedInputTokens + event.cachedInputTokens + event.outputTokens,
                uncachedInputTokens: event.uncachedInputTokens,
                cachedInputTokens: event.cachedInputTokens,
                outputTokens: event.outputTokens,
                turns: event.turns,
                threads: 0)
            result.byModel[event.model, default: .zero] = result.byModel[event.model, default: .zero] + totals
            result.byProject[event.project, default: .zero] = result.byProject[event.project, default: .zero] + totals
            result.byDay[event.utcDay, default: .zero] = result.byDay[event.utcDay, default: .zero] + totals
            result.byDayModel[event.utcDay, default: [:]][event.model, default: .zero] =
                result.byDayModel[event.utcDay, default: [:]][event.model, default: .zero] + totals
        }
    }

    private static func modelRows(
        _ grouped: [String: ApiEquivalentTotals],
        priceBook: UsageCostPriceBook
    ) -> [ApiEquivalentBreakdownRow] {
        grouped.keys.sorted().map { model in
            let totals = grouped[model] ?? .zero
            return ApiEquivalentBreakdownRow(
                name: model,
                totals: totals,
                estimatedUSD: priceBook.cost(model: model, totals: totals)
                    ?? priceBook.equivalentCost(totals: totals),
                rawCredits: 0)
        }
    }

    private static func projectRows(
        _ grouped: [String: ApiEquivalentTotals],
        priceBook: UsageCostPriceBook
    ) -> [ApiEquivalentBreakdownRow] {
        grouped.keys.sorted { lhs, rhs in
            let left = grouped[lhs]?.totalTokens ?? 0
            let right = grouped[rhs]?.totalTokens ?? 0
            return left == right ? lhs < rhs : left > right
        }.map { project in
            let totals = grouped[project] ?? .zero
            return ApiEquivalentBreakdownRow(
                name: project,
                totals: totals,
                estimatedUSD: priceBook.equivalentCost(totals: totals),
                rawCredits: 0)
        }
    }

    private static func dailyRows(
        _ groups: Groups,
        priceBook: UsageCostPriceBook
    ) -> [ApiEquivalentDailyRow] {
        groups.byDay.keys.sorted().map { day in
            let totals = groups.byDay[day] ?? .zero
            return ApiEquivalentDailyRow(
                date: day,
                totals: totals,
                estimatedUSD: estimatedCost(
                    byModel: groups.byDayModel[day] ?? [:],
                    priceBook: priceBook),
                rawCredits: 0)
        }
    }

    private static func estimatedCost(
        byModel: [String: ApiEquivalentTotals],
        priceBook: UsageCostPriceBook
    ) -> Decimal {
        byModel.reduce(Decimal(0)) { result, item in
            result + (priceBook.cost(model: item.key, totals: item.value)
                ?? priceBook.equivalentCost(totals: item.value))
        }
    }
}
