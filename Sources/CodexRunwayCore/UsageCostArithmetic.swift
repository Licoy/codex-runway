import Foundation

enum UsageCostArithmeticError: Error, Equatable {
    case integerOverflow(field: String)
    case invalidValue(field: String)
}

func checkedAdd(_ lhs: Int, _ rhs: Int, field: String) throws -> Int {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw UsageCostArithmeticError.integerOverflow(field: field) }
    return result
}

func checkedFiniteSum<S: Sequence>(_ values: S, field: String) throws -> Double
    where S.Element == Double
{
    try values.reduce(0) { result, value in
        guard result.isFinite, value.isFinite else {
            throw UsageCostArithmeticError.invalidValue(field: field)
        }
        let sum = result + value
        guard sum.isFinite else { throw UsageCostArithmeticError.invalidValue(field: field) }
        return sum
    }
}

extension TokenUsage {
    func adding(_ other: TokenUsage) throws -> TokenUsage {
        TokenUsage(
            inputTokens: try checkedAdd(inputTokens, other.inputTokens, field: "input tokens"),
            cachedInputTokens: try checkedAdd(
                cachedInputTokens,
                other.cachedInputTokens,
                field: "cached input tokens"),
            outputTokens: try checkedAdd(outputTokens, other.outputTokens, field: "output tokens"))
    }

    static func sum<S: Sequence>(_ values: S) throws -> TokenUsage where S.Element == TokenUsage {
        try values.reduce(.zero) { try $0.adding($1) }
    }
}

extension ApiEquivalentTotals {
    func adding(_ other: ApiEquivalentTotals) throws -> ApiEquivalentTotals {
        ApiEquivalentTotals(
            totalTokens: try checkedAdd(totalTokens, other.totalTokens, field: "total tokens"),
            uncachedInputTokens: try checkedAdd(
                uncachedInputTokens,
                other.uncachedInputTokens,
                field: "uncached input tokens"),
            cachedInputTokens: try checkedAdd(
                cachedInputTokens,
                other.cachedInputTokens,
                field: "cached input tokens"),
            outputTokens: try checkedAdd(outputTokens, other.outputTokens, field: "output tokens"),
            turns: try checkedAdd(turns, other.turns, field: "turns"),
            threads: try checkedAdd(threads, other.threads, field: "threads"))
    }

    static func sum<S: Sequence>(_ values: S) throws -> ApiEquivalentTotals
        where S.Element == ApiEquivalentTotals
    {
        try values.reduce(.zero) { try $0.adding($1) }
    }
}
