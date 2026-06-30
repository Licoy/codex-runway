import CodexRunwayCore
import SwiftUI

struct QuotaMetersView: View {
    var title: String
    var meters: [QuotaMeter]
    var l10n: L10n

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "speedometer")
                .font(.headline)
            if meters.isEmpty {
                Text(l10n.text(.notLoaded)).foregroundStyle(.secondary)
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
        }
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

struct ResetCreditsSummaryView: View {
    var summary: ResetCreditSummary?
    var l10n: L10n
    var onDetailsSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l10n.text(.resetCredits), systemImage: "clock.arrow.circlepath")
                .font(.headline)
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
                Text(l10n.text(.notLoaded)).foregroundStyle(.secondary)
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
    var onDetailsSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.text(.apiCost))
                        .font(.headline)
                    Text(text)
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
                Spacer(minLength: 0)
            }
            SidePanelDisclosureRow(title: l10n.text(.showDetails), action: onDetailsSelect)
        }
    }
}
