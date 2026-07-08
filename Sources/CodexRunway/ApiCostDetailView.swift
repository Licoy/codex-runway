import CodexRunwayCore
import MijickCalendarView
import SwiftUI

struct ApiCostDetailView: View {
    @ObservedObject var model: RunwayModel
    var l10n: L10n

    @State private var selectedRange: ApiCostRangeMode = .today
    @State private var customDateRange: MDateRange? = .init(startDate: Date(), endDate: Date())
    @State private var showsCustomCalendar = false
    @State private var isLoading = false
    @State private var transientDetail: ApiEquivalentSummary?
    @State private var transientRange: ApiCostRangeMode?
    @State private var queryError: String?
    @State private var didQueryInitialRange = false

    init(model: RunwayModel, l10n: L10n, initialRange: ApiCostSummaryRange = .today) {
        self.model = model
        self.l10n = l10n
        _selectedRange = State(initialValue: ApiCostRangeMode(initialRange))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            rangeControls
            if isLoading {
                loadingState
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    detailContent
                }
            }
        }
        .padding(.top, 2)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard !didQueryInitialRange else { return }
            didQueryInitialRange = true
            rangeChanged(selectedRange)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let detail = activeDetail, detail.confidence != .unavailable {
                header(detail)
                scanNoteText
                statGrid(detail)
                tokenParts(detail.totals)
                usageRows(detail.dailyRows, title: activeRangeTitle)
                breakdown(l10n.text(.projectBreakdown), rows: detail.projectRows)
                breakdown(l10n.text(.modelBreakdown), rows: detail.modelRows)
                breakdown(l10n.text(.apiCostSource), rows: detail.clientRows)
                rawReference(detail)
            } else {
                Text(l10n.text(.usageAnalyticsUnavailable))
                    .foregroundStyle(.secondary)
                scanNoteText
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeDetail: ApiEquivalentSummary? {
        if selectedRange == .current { return model.costDetail }
        guard transientRange == selectedRange else { return nil }
        return transientDetail
    }

    private var activeRangeTitle: String {
        if selectedRange == .current { return l10n.text(.currentCycle) }
        return selectedRange.title(l10n)
    }

    @ViewBuilder
    private var rangeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            rangePicker

            if selectedRange == .custom, !isLoading {
                customControls
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 1) {
            ForEach(ApiCostRangeMode.allCases) { range in
                Button {
                    selectedRange = range
                    rangeChanged(range)
                } label: {
                    Text(range.title(l10n))
                        .font(.callout.weight(selectedRange == range ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedRange == range ? .white : .primary)
                .background(selectedRange == range ? Color.accentColor : Color.clear)
            }
        }
        .background(RunwaySurface.fill, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .disabled(isLoading)
        .frame(maxWidth: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text(l10n.text(.calculating))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var customControls: some View {
        HStack(spacing: 8) {
            Button {
                showsCustomCalendar = true
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text(customRangeText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .popover(isPresented: $showsCustomCalendar) {
                CustomDateRangePopover(
                    selectedRange: $customDateRange,
                    minimumDate: minimumCustomDate,
                    maximumDate: Date())
            }

            Button {
                calculateCustomRange()
            } label: {
                Text(isLoading ? l10n.text(.calculating) : l10n.text(.calculate))
            }
            .disabled(isLoading)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customRangeText: String {
        guard let range = customDateRange?.getRange() else {
            return "\(l10n.text(.startDate)) - \(l10n.text(.endDate))"
        }
        let start = dateText(range.lowerBound)
        let end = dateText(range.upperBound)
        return start == end ? start : "\(start) - \(end)"
    }

    private var minimumCustomDate: Date {
        Calendar.autoupdatingCurrent.date(byAdding: .month, value: -24, to: Date()) ?? Date()
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
        if let scanNote = activeScanNote {
            Text("\(l10n.text(.costScanFailed)): \(scanNote)")
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
        }
    }

    private var activeScanNote: String? {
        selectedRange == .current ? model.costScanNote : queryError
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

    private func usageRows(_ rows: [ApiEquivalentDailyRow], title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
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

    private func rangeChanged(_ range: ApiCostRangeMode) {
        queryError = nil
        switch range {
        case .today:
            queryCost(ApiCostRange.today(), mode: range)
        case .current:
            break
        case .previous:
            guard let costRange = model.previousCycleCostRange() else {
                queryError = l10n.text(.usageAnalyticsUnavailable)
                return
            }
            queryCost(costRange, mode: range)
        case .thisMonth:
            queryCost(ApiCostRange.thisMonth(), mode: range)
        case .custom:
            prepareCustomDates()
        }
    }

    private func prepareCustomDates() {
        guard let detail = model.costDetail else { return }
        customDateRange = MDateRange(startDate: detail.window.start, endDate: min(Date(), detail.window.end))
    }

    private func calculateCustomRange() {
        guard let selected = customDateRange?.getRange(),
              let range = ApiCostRange.custom(start: selected.lowerBound, end: selected.upperBound)
        else {
            queryError = l10n.text(.invalidDateRange)
            return
        }
        queryCost(range, mode: .custom)
    }

    private func queryCost(_ range: ApiCostRange, mode: ApiCostRangeMode) {
        isLoading = true
        queryError = nil
        transientDetail = nil
        transientRange = nil
        Task { @MainActor in
            defer { isLoading = false }
            do {
                transientDetail = try await model.queryCost(range: range)
                transientRange = mode
            } catch {
                queryError = error is CostRangeQueryError ? l10n.text(.usageAnalyticsUnavailable) : error.localizedDescription
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

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: l10n.language == .simplifiedChinese ? "zh_Hans_CN" : "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.2fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

private enum ApiCostRangeMode: String, CaseIterable, Identifiable {
    case today
    case current
    case previous
    case thisMonth
    case custom

    var id: String { rawValue }

    init(_ range: ApiCostSummaryRange) {
        switch range {
        case .today:
            self = .today
        case .current:
            self = .current
        case .previous:
            self = .previous
        case .thisMonth:
            self = .thisMonth
        }
    }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .today:
            return l10n.text(.today)
        case .current:
            return l10n.text(.currentCycle)
        case .previous:
            return l10n.text(.previousCycle)
        case .thisMonth:
            return l10n.text(.thisMonth)
        case .custom:
            return l10n.text(.customRange)
        }
    }
}

private struct CustomDateRangePopover: View {
    @Binding var selectedRange: MDateRange?
    var minimumDate: Date
    var maximumDate: Date

    var body: some View {
        MCalendarView(selectedDate: nil, selectedRange: $selectedRange) {
            $0
                .startMonth(minimumDate)
                .endMonth(maximumDate)
                .scrollTo(date: selectedRange?.getRange()?.lowerBound ?? maximumDate)
                .monthsTopPadding(6)
                .monthsBottomPadding(10)
                .monthsSpacing(18)
                .monthLabelToDaysDistance(8)
                .daysVerticalSpacing(2)
                .daysHorizontalSpacing(0)
                .weekdaysView(RunwayCalendarWeekdaysView.init)
                .monthLabel(RunwayCalendarMonthLabel.init)
                .dayView(RunwayCalendarDayView.init)
        }
        .padding(12)
        .frame(width: 340, height: 360)
        .background(.regularMaterial)
    }
}

private struct RunwayCalendarWeekdaysView: WeekdaysView {
    func createWeekdayLabel(_ weekday: MWeekday) -> AnyWeekdayLabel {
        RunwayCalendarWeekdayLabel(weekday: weekday).erased()
    }
}

private struct RunwayCalendarWeekdayLabel: WeekdayLabel {
    let weekday: MWeekday

    func createContent() -> AnyView {
        Text(getString(with: .veryShort))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .erased()
    }
}

private struct RunwayCalendarMonthLabel: MonthLabel {
    let month: Date

    func createContent() -> AnyView {
        Text(getString(format: "LLLL yyyy"))
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .erased()
    }
}

private struct RunwayCalendarDayView: DayView {
    let date: Date
    let isCurrentMonth: Bool
    let selectedDate: Binding<Date?>?
    let selectedRange: Binding<MDateRange?>?

    func createContent() -> AnyView {
        ZStack {
            if isWithinRange() {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.16))
            }
            if isSelected() {
                Circle()
                    .fill(Color.accentColor)
                    .padding(2)
            }
            Text(getStringFromDay(format: "d"))
                .font(.caption.weight(.medium))
                .foregroundStyle(labelColor)
        }
        .opacity(isFuture ? 0.35 : 1)
        .erased()
    }

    func onSelection() {
        guard !isFuture else { return }
        var range = selectedRange?.wrappedValue ?? MDateRange()
        range.addToRange(date)
        selectedRange?.wrappedValue = range
    }

    private var labelColor: Color {
        if isSelected() { return .white }
        return .primary
    }

    private var isFuture: Bool {
        Calendar.autoupdatingCurrent.startOfDay(for: date) > Calendar.autoupdatingCurrent.startOfDay(for: Date())
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
