import CodexRunwayCore
import SwiftUI

struct ApiCostDetailView: View {
    var detail: ApiEquivalentSummary?
    var scanNote: String?
    var l10n: L10n

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let detail, detail.confidence != .unavailable {
                VStack(alignment: .leading, spacing: 14) {
                    header(detail)
                    scanNoteText
                    statGrid(detail)
                    tokenParts(detail.totals)
                    usageRows(detail.dailyRows)
                    breakdown(l10n.text(.modelBreakdown), rows: detail.modelRows)
                    breakdown(l10n.text(.apiCostSource), rows: detail.clientRows)
                    rawReference(detail)
                }
                .padding(.top, 2)
                .padding(.trailing, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.text(.usageAnalyticsUnavailable))
                        .foregroundStyle(.secondary)
                    scanNoteText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func header(_ detail: ApiEquivalentSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.text(.apiCost))
                    .font(.headline)
                Text("\(l10n.text(.calculatedAt)) \(calculatedText(detail.calculatedAt)) · \(detail.pricingVersion) · \(sourceText(detail.source))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(detail.estimatedUSD.map(DurationFormatter.money) ?? l10n.text(.tokensOnly))
                .font(.title3.weight(.semibold))
        }
    }

    @ViewBuilder
    private var scanNoteText: some View {
        if let scanNote {
            Text("\(l10n.text(.costScanFailed)): \(scanNote)")
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    private func statGrid(_ detail: ApiEquivalentSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            UsageStatCard(title: l10n.text(.estimatedAPICost), value: detail.estimatedUSD.map(DurationFormatter.money) ?? "--", color: .green)
            UsageStatCard(title: l10n.text(.tokens), value: Self.tokenText(detail.totals.totalTokens), color: .blue)
            UsageStatCard(title: l10n.text(.inputCachedOutput), value: "\(Self.tokenText(detail.totals.uncachedInputTokens)) / \(Self.tokenText(detail.totals.cachedInputTokens)) / \(Self.tokenText(detail.totals.outputTokens))", color: .teal)
            UsageStatCard(title: l10n.text(.turns), value: "\(detail.totals.turns)", color: .orange)
        }
    }

    private func tokenParts(_ totals: ApiEquivalentTotals) -> some View {
        HStack(spacing: 8) {
            UsageStatCard(title: l10n.text(.nonCachedInput), value: Self.tokenText(totals.uncachedInputTokens), color: .blue)
            UsageStatCard(title: l10n.text(.cachedInput), value: Self.tokenText(totals.cachedInputTokens), color: .green)
            UsageStatCard(title: l10n.text(.outputTokens), value: Self.tokenText(totals.outputTokens), color: .orange)
        }
    }

    private func usageRows(_ rows: [ApiEquivalentDailyRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.text(.currentCycle))
                .font(.headline)
            if rows.isEmpty {
                Text(l10n.text(.notLoaded))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    UsageTableHeader(l10n: l10n)
                    ForEach(rows.reversed()) { row in
                        UsageTableRow(row: row)
                    }
                }
                .background(RunwaySurface.subtleFill, in: RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
            }
        }
    }

    @ViewBuilder
    private func breakdown(_ title: String, rows: [ApiEquivalentBreakdownRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                VStack(spacing: 0) {
                    ForEach(rows.prefix(8)) { row in
                        BreakdownRow(row: row)
                    }
                }
                .background(RunwaySurface.subtleFill, in: RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
            }
        }
    }

    @ViewBuilder
    private func rawReference(_ detail: ApiEquivalentSummary) -> some View {
        if detail.source == .onlineAnalytics {
            Text("\(l10n.text(.rawAnalyticsCredits)): \(String(format: "%.3f", detail.rawCredits))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sourceText(_ source: ApiEquivalentSource) -> String {
        switch source {
        case .localSessions:
            return l10n.text(.sourceLocalSessions)
        case .onlineAnalytics:
            return l10n.text(.sourceOnlineSupplement)
        case .unavailable:
            return l10n.text(.usageAnalyticsUnavailable)
        }
    }

    private func calculatedText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: l10n.language == .simplifiedChinese ? "zh_Hans_CN" : "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.2fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

private struct UsageStatCard: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RunwaySurface.fill, in: RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
    }
}

private struct UsageTableHeader: View {
    var l10n: L10n

    var body: some View {
        HStack {
            Text(l10n.text(.date)).frame(width: 78, alignment: .leading)
            Text(l10n.text(.tokens)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(l10n.text(.estimatedAPICost)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(l10n.text(.turns)).frame(width: 42, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

private struct UsageTableRow: View {
    var row: ApiEquivalentDailyRow

    var body: some View {
        HStack {
            Text(row.date).frame(width: 78, alignment: .leading)
            Text(Self.tokenText(row.totals.totalTokens)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.estimatedUSD.map(DurationFormatter.money) ?? "--").frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(row.totals.turns)").frame(width: 42, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator.opacity(0.25)).frame(height: 1)
        }
    }

    private static func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.2fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

private struct BreakdownRow: View {
    var row: ApiEquivalentBreakdownRow

    var body: some View {
        HStack {
            Text(row.name)
                .lineLimit(1)
            Spacer()
            Text(Self.tokenText(row.totals.totalTokens))
                .foregroundStyle(.secondary)
            Text(row.estimatedUSD.map(DurationFormatter.money) ?? "--")
                .frame(width: 82, alignment: .trailing)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator.opacity(0.25)).frame(height: 1)
        }
    }

    private static func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.2fK", Double(value) / 1_000) }
        return "\(value)"
    }
}
