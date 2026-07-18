import AppKit
import CodexRunwayCore
import SwiftUI

struct QuotaMetersView: View {
    var title: String
    var meters: [QuotaMeter]
    var l10n: L10n
    var isRefreshing: Bool
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RefreshableSectionHeader(
                title: title,
                systemImage: "speedometer",
                l10n: l10n,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh)
            if meters.isEmpty {
                Text(l10n.text(isRefreshing ? .calculating : .notLoaded)).foregroundStyle(.secondary)
            } else {
                ForEach(meters) { meter in
                    quotaRow(meter)
                }
            }
        }
    }

    private func quotaRow(_ meter: QuotaMeter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meter.title).font(.headline)
            RunwayProgressBar(meter: meter).frame(height: 12)
            HStack(alignment: .firstTextBaseline) {
                Text("\(meter.remainingPercent)% \(l10n.text(.left))")
                Spacer()
                if let resetsAt = meter.resetsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(resetText(until: resetsAt, now: context.date))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
            if let projection = meter.projection {
                Text(projectionText(projection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func projectionText(_ projection: QuotaBurnProjection) -> String {
        if let exhaustsAt = projection.exhaustsAt {
            return "\(l10n.text(.burnRate)): \(l10n.text(.exhaustsIn)) \(duration(exhaustsAt.timeIntervalSince(Date())))"
        }
        return "\(l10n.text(.burnRate)): \(l10n.text(.projectedAtReset)) \(projection.projectedUsedPercentAtReset)%"
    }

    private func resetText(until date: Date, now: Date) -> String {
        "\(l10n.text(.nextResetIn))\(duration(date.timeIntervalSince(now)))"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        DurationFormatter.localized(seconds, language: l10n.language)
    }
}

struct RunwayProgressBar: View {
    var meter: QuotaMeter

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(RunwaySurface.subtleFill)
                Capsule()
                    .fill(color)
                    .frame(width: max(6, proxy.size.width * CGFloat(meter.remainingPercent) / 100))
                ForEach(meter.markerPercents, id: \.self) { marker in
                    let x = min(max(1, proxy.size.width * CGFloat(marker) / 100), proxy.size.width - 2)
                    Capsule()
                        .fill(Color(nsColor: .separatorColor).opacity(0.28))
                        .frame(width: 1.5, height: 6)
                        .offset(x: x)
                }
            }
        }
        .accessibilityLabel("\(meter.title) \(meter.remainingPercent)%")
    }

    var color: Color {
        switch meter.health {
        case .green:
            return Color(nsColor: .systemGreen)
        case .yellow:
            return Color(nsColor: .systemYellow)
        case .red:
            return Color(nsColor: .systemRed)
        }
    }
}

struct RecentSessionsView: View {
    var sessions: [SessionActivityItem]
    var l10n: L10n
    var isRefreshing: Bool
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RefreshableSectionHeader(
                title: l10n.text(.recentSessions),
                systemImage: "terminal",
                l10n: l10n,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh)
            if sessions.isEmpty {
                Text(l10n.text(isRefreshing ? .calculating : .notLoaded)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(sessions.prefix(5)) { session in
                        row(session)
                    }
                }
                .background(RunwaySurface.subtleFill, in: RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
            }
        }
    }

    private func row(_ session: SessionActivityItem) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(for: session.state))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(session.projectName) · \(stateText(session.state)) · \(tokenText(session.totals.totalTokens)) \(l10n.text(.tokens))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(session.estimatedUSD.map(DurationFormatter.money) ?? "--")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            Rectangle().fill(.separator.opacity(0.25)).frame(height: 1)
        }
    }

    private func stateText(_ state: SessionActivityState) -> String {
        switch state {
        case .recent:
            return l10n.text(.recent)
        case .needsAttention:
            return l10n.text(.needsAttention)
        case .failed:
            return l10n.text(.failed)
        }
    }

    private func color(for state: SessionActivityState) -> Color {
        switch state {
        case .recent:
            return Color(nsColor: .systemGreen)
        case .needsAttention:
            return Color(nsColor: .systemOrange)
        case .failed:
            return Color(nsColor: .systemRed)
        }
    }

    private func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.2fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

struct ResetCreditsSummaryView: View {
    var summary: ResetCreditSummary?
    var l10n: L10n
    var isRefreshing: Bool
    var onRefresh: () -> Void
    var onDetailsSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RefreshableSectionHeader(
                title: l10n.text(.resetCredits),
                systemImage: "clock.arrow.circlepath",
                l10n: l10n,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh)
            if let summary {
                Text("\(summary.availableCount) \(l10n.text(.available)) / \(summary.totalCount) \(l10n.text(.total))")
                    .font(.title3)
                HStack {
                    Text("\(l10n.text(.totalRemaining)): \(duration(summary.totalRemainingDuration))")
                    Spacer()
                    if let remaining = summary.nextExpiryRemaining {
                        Text("\(l10n.text(.left)) \(duration(remaining))")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                SidePanelDisclosureRow(
                    title: "\(summary.availableCount) \(l10n.text(.availableResets))",
                    action: onDetailsSelect)
            } else {
                Text(l10n.text(isRefreshing ? .calculating : .notLoaded)).foregroundStyle(.secondary)
            }
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        DurationFormatter.localized(seconds, language: l10n.language)
    }
}

struct CostSummaryView: View {
    var text: String
    var subtitle: String
    var l10n: L10n
    var isRefreshing: Bool
    var onRefresh: () -> Void
    var onDetailsSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RefreshableSectionHeader(
                title: l10n.text(.apiCost),
                systemImage: "dollarsign.circle",
                l10n: l10n,
                isRefreshing: isRefreshing,
                onRefresh: onRefresh)
            VStack(alignment: .leading, spacing: 3) {
                Text(isRefreshing && subtitle.isEmpty ? l10n.text(.calculating) : text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            SidePanelDisclosureRow(title: l10n.text(.showDetails), action: onDetailsSelect)
        }
    }
}

struct RefreshableSectionHeader: View {
    var title: String
    var systemImage: String
    var l10n: L10n
    var isRefreshing: Bool
    var onRefresh: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Spacer(minLength: 0)
            Button(action: onRefresh) {
                Group {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .foregroundStyle(isHovered && !isRefreshing ? Color.accentColor : Color.primary)
                .frame(width: 24, height: 24)
                .background(
                    isHovered && !isRefreshing ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .help(l10n.text(.refresh))
            .accessibilityLabel(l10n.text(.refresh))
            .onHover { hovering in
                isHovered = hovering
                if hovering, !isRefreshing {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}
