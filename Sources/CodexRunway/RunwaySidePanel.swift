import AppKit
import CodexRunwayCore
import Foundation
import SwiftUI

enum RunwaySidePanel: Equatable {
    case resetCredits
    case apiCost
}

struct SidePanelDisclosureRow: View {
    var title: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.callout)
                    .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius)
                    .strokeBorder(isHovered ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var rowBackground: Color {
        // Default fill is systemGray@0.16; hover must be clearly different in both light and dark mode.
        if isHovered {
            return Color.accentColor.opacity(0.18)
        }
        return RunwaySurface.fill
    }
}

struct DetailPageView: View {
    var page: RunwaySidePanel
    @ObservedObject var model: RunwayModel
    var l10n: L10n
    var apiCostInitialRange: ApiCostSummaryRange = .today

    var body: some View {
        switch page {
        case .resetCredits:
            PolishedScrollView(verticalPadding: 4) {
                ResetCreditsDetailView(
                    summary: model.resetCreditSummary,
                    details: model.resetCreditDetails,
                    l10n: l10n)
            }
        case .apiCost:
            ApiCostDetailView(model: model, l10n: l10n, initialRange: apiCostInitialRange)
        }
    }
}

private struct ResetCreditsDetailView: View {
    var summary: ResetCreditSummary?
    var details: [ResetCreditDetail]
    var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let summary {
                header(summary)
                statGrid(summary)
                ResetRiskCompositionView(summary: summary, l10n: l10n)
                creditTable
            } else {
                Text(l10n.text(.notLoaded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ summary: ResetCreditSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.text(.resetCreditDetails))
                    .font(.headline)
                Text("\(l10n.text(.lastUpdated)) \(ResetCreditDateFormatter.updatedAt(summary.updatedAt, language: l10n.language))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(summary.availableCount)/\(summary.totalCount)")
                .font(.title3.weight(.semibold))
        }
    }

    private func statGrid(_ summary: ResetCreditSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ResetMetricCard(title: l10n.text(.available), value: "\(summary.availableCount)", color: Color(nsColor: .systemGreen))
            ResetMetricCard(title: l10n.text(.expiringSoon), value: "\(summary.expiringCount)", color: Color(nsColor: .systemYellow))
            ResetMetricCard(title: l10n.text(.totalRemaining), value: duration(summary.totalRemainingDuration), color: Color(nsColor: .systemBlue))
            ResetMetricCard(title: l10n.text(.nextExpiry), value: summary.nextExpiryRemaining.map(duration) ?? "--", color: Color(nsColor: .systemOrange))
        }
    }

    @ViewBuilder
    private var creditTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.text(.resetCreditDetails))
                .font(.headline)
            if details.isEmpty {
                Text(l10n.text(.noAvailableResetCredits))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ResetCreditTableHeader(l10n: l10n)
                    ForEach(details) { credit in
                        ResetCreditTableRow(credit: credit, l10n: l10n)
                    }
                }
                .background(RunwaySurface.subtleFill, in: RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
            }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        DurationFormatter.localized(seconds, language: l10n.language, includeSeconds: false)
    }
}

private struct ResetMetricCard: View {
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

private struct ResetRiskCompositionView: View {
    var summary: ResetCreditSummary
    var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(l10n.text(.expiryRisk))
                .font(.headline)
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    segment(count: summary.stableAvailableCount, total: summary.totalCount, color: Color(nsColor: .systemGreen), width: proxy.size.width)
                    segment(count: summary.expiringCount, total: summary.totalCount, color: Color(nsColor: .systemYellow), width: proxy.size.width)
                    segment(count: summary.unavailableCount, total: summary.totalCount, color: Color(nsColor: .systemRed), width: proxy.size.width)
                }
            }
            .frame(height: 12)
            HStack(spacing: 10) {
                legend(l10n.text(.available), summary.stableAvailableCount, Color(nsColor: .systemGreen))
                legend(l10n.text(.expiringSoon), summary.expiringCount, Color(nsColor: .systemYellow))
                legend(l10n.text(.unavailableCredits), summary.unavailableCount, Color(nsColor: .systemRed))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func segment(count: Int, total: Int, color: Color, width: CGFloat) -> some View {
        if count > 0, total > 0 {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: max(8, width * CGFloat(count) / CGFloat(total)))
        }
    }

    private func legend(_ title: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title) \(count)")
        }
    }
}

private struct ResetCreditTableHeader: View {
    var l10n: L10n

    var body: some View {
        HStack {
            Text(l10n.text(.credit)).frame(width: 62, alignment: .leading)
            Text(l10n.text(.status)).frame(maxWidth: .infinity, alignment: .leading)
            Text(l10n.text(.expiresAt)).frame(maxWidth: .infinity, alignment: .trailing)
            Text(l10n.text(.left)).frame(width: 72, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

private struct ResetCreditTableRow: View {
    var credit: ResetCreditDetail
    var l10n: L10n

    var body: some View {
        HStack {
            Text(credit.title)
                .frame(width: 62, alignment: .leading)
            StatusPill(text: statusText, state: credit.state)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(expiryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(remainingText)
                .frame(width: 72, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator.opacity(0.25)).frame(height: 1)
        }
    }

    private var statusText: String {
        credit.state == .expiring ? l10n.text(.expiringSoon) : credit.statusText
    }

    private var expiryText: String {
        credit.expiresAt.map { ResetCreditDateFormatter.expiresAt($0, language: l10n.language) } ?? l10n.text(.noExpiry)
    }

    private var remainingText: String {
        credit.expiresAt == nil ? "--" : DurationFormatter.localized(credit.remainingDuration, language: l10n.language, includeSeconds: false)
    }
}

private struct StatusPill: View {
    var text: String
    var state: ResetCreditState

    var body: some View {
        RunwayTag(text, tone: tone, font: .caption.weight(.semibold))
    }

    private var tone: RunwayTagTone {
        switch state {
        case .available:
            return .green
        case .expiring:
            // Warning orange stays readable in light mode; pure yellow text does not.
            return .orange
        case .unavailable:
            return .red
        }
    }
}
