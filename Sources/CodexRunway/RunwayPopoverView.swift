import AppKit
import CodexRunwayCore
import SwiftUI

struct RunwayPopoverView: View {
    @ObservedObject var model: RunwayModel
    @ObservedObject var settings: RunwaySettings
    var checkForUpdates: () -> Void
    var openGitHub: () -> Void
    var openControlPanel: () -> Void

    @State private var confirmRepair = false
    @State private var detailPage: RunwaySidePanel?
    private var l10n: L10n { settings.l10n }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            detailPage == nil ? AnyView(header) : AnyView(detailHeader)
            Divider()
            if let detailPage {
                DetailPageView(page: detailPage, model: model, l10n: l10n)
            } else {
                mainContent
                if let error = model.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                footer
            }
        }
        .padding(16)
        .frame(width: 390, height: 560, alignment: .topLeading)
        .preferredColorScheme(settings.colorScheme)
        .alert(l10n.text(.repairConfirmTitle), isPresented: $confirmRepair) {
            Button(l10n.text(.repair), role: .destructive) { model.repairSessions() }
            Button(l10n.text(.cancel), role: .cancel) {}
        } message: {
            Text(model.repairWarning)
        }
    }

    private var mainContent: some View {
        PolishedScrollView(verticalPadding: 4) {
            VStack(alignment: .leading, spacing: 14) {
                QuotaMetersView(title: l10n.text(.quota), meters: model.quotaMeters, l10n: l10n)
                ResetCreditsSummaryView(
                    summary: model.resetCreditSummary,
                    l10n: l10n,
                    onDetailsSelect: { detailPage = .resetCredits })
                if settings.preferences.showsCostSummary {
                    CostSummaryView(
                        text: model.costText,
                        subtitle: model.costSubtitle,
                        l10n: l10n,
                    onDetailsSelect: { detailPage = .apiCost })
                }
                if settings.preferences.showsSessionRepairSummary {
                    sessionSummary
                }
                RecentSessionsView(sessions: model.recentSessions, l10n: l10n)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Runway").font(.title3.bold())
                HStack(spacing: 8) {
                    SubscriptionBadge(tier: model.accountDisplay.subscriptionTier, l10n: l10n)
                    Text(accountDisplayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                HeaderActionButton(title: l10n.text(.checkForUpdates), action: checkForUpdates) {
                    BootstrapIconImage(.cloudArrowDown)
                }
                HeaderActionButton(title: "GitHub", action: openGitHub) {
                    BootstrapIconImage(.github)
                }
                HeaderActionButton(title: l10n.text(.refresh)) {
                    model.refresh()
                } icon: {
                    Image(systemName: model.isRefreshing ? "hourglass" : "arrow.clockwise")
                }
            }
        }
    }

    private var accountDisplayName: String {
        if !model.accountDisplay.displayName.isEmpty {
            return model.accountDisplay.displayName
        }
        return model.accountDisplay.isAuthenticated ? l10n.text(.unknownAccount) : l10n.text(.notLoggedIn)
    }

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detailTitle(detailPage))
                    .font(.title3.bold())
                Text("Codex Runway")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                detailPage = nil
            } label: {
                Label(l10n.text(.back), systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
        }
    }

    private func detailTitle(_ page: RunwaySidePanel?) -> String {
        switch page {
        case .resetCredits:
            return l10n.text(.resetCreditDetails)
        case .apiCost:
            return l10n.text(.apiCost)
        case nil:
            return ""
        }
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            SummaryRow(systemImage: "wrench.and.screwdriver", title: l10n.text(.sessionRepair), value: model.sessionText)
            Button { confirmRepair = true } label: {
                HStack {
                    Label(l10n.text(.repairIndex), systemImage: "cross.case")
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(RunwaySurface.fill, in: RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: RunwaySurface.cornerRadius))
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack {
            Button(action: openControlPanel) {
                Label(l10n.text(.settings), systemImage: "slider.horizontal.3")
            }
            .help(l10n.text(.openControlPanel))
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(l10n.text(.quit), systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
    }
}

private struct SubscriptionBadge: View {
    var tier: CodexSubscriptionTier
    var l10n: L10n

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 0.7))
            .lineLimit(1)
    }

    private var color: Color {
        switch tier {
        case .free:
            return Color(nsColor: .systemGray)
        case .plus:
            return Color(nsColor: .systemBlue)
        case .pro5x:
            return Color(nsColor: .systemPurple)
        case .pro20x:
            return Color(nsColor: .systemOrange)
        case .business:
            return Color(nsColor: .systemTeal)
        case .team:
            return Color(nsColor: .systemIndigo)
        case .enterprise:
            return Color(nsColor: .systemRed)
        case .edu:
            return Color(nsColor: .systemGreen)
        case .api:
            return Color(nsColor: .systemCyan)
        case .unknown:
            return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var label: String {
        switch tier {
        case .free:
            return l10n.text(.planFree)
        case .plus:
            return l10n.text(.planPlus)
        case .pro5x:
            return l10n.text(.planPro5x)
        case .pro20x:
            return l10n.text(.planPro20x)
        case .business:
            return l10n.text(.planBusiness)
        case .team:
            return l10n.text(.planTeam)
        case .enterprise:
            return l10n.text(.planEnterprise)
        case .edu:
            return l10n.text(.planEdu)
        case .api:
            return l10n.text(.planAPI)
        case .unknown:
            return l10n.text(.planUnknown)
        }
    }
}

private struct HeaderActionButton<Icon: View>: View {
    var title: String
    var action: () -> Void
    @ViewBuilder var icon: Icon

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon.frame(width: 14, height: 14)
            .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
            .frame(width: 28, height: 24)
            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovered = $0 }
    }
}
