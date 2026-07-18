import Testing
@testable import CodexRunwayCore

@Suite("Cost scan progress")
struct CostScanProgressTests {
    @Test("fraction is nil without totals and scales within completed units")
    func fractionScaling() {
        #expect(CostScanProgress.preparing.fraction == nil)
        #expect(CostScanProgress.refreshingIndex(completed: 0, total: 0).fraction == nil)
        #expect(CostScanProgress.refreshingIndex(completed: 2, total: 4).fraction == 0.5)
        #expect(CostScanProgress.refreshingIndex(completed: 9, total: 4).fraction == 1)
    }

    @Test("active phases cover scan work only")
    func activePhases() {
        #expect(CostScanProgress.preparing.isActive)
        #expect(CostScanProgress.refreshingIndex(completed: 1, total: 2).isActive)
        #expect(CostScanProgress.aggregating().isActive)
        #expect(CostScanProgress.fetchingOnline.isActive)
        #expect(!CostScanProgress.idle.isActive)
        #expect(!CostScanProgress.finished.isActive)
        #expect(!CostScanProgress.failed("x").isActive)
    }

    @Test("reporter throttles high-frequency index updates")
    func reporterThrottlesIndexUpdates() async {
        let reporter = CostScanProgressReporter(minimumInterval: 1)
        let box = ProgressBox()
        reporter.setHandler { progress in
            Task { await box.append(progress) }
        }

        reporter.report(.refreshingIndex(completed: 0, total: 10), force: true)
        reporter.report(.refreshingIndex(completed: 1, total: 10))
        reporter.report(.refreshingIndex(completed: 2, total: 10))
        reporter.report(.aggregating(completed: 1, total: 1), force: true)

        try? await Task.sleep(for: .milliseconds(20))
        let phases = await box.phases()
        #expect(phases.contains(.refreshingIndex))
        #expect(phases.contains(.aggregating))
        // Throttled intermediate index ticks should not all land.
        #expect(phases.filter { $0 == .refreshingIndex }.count == 1)
    }
}

private actor ProgressBox {
    private var values: [CostScanProgress] = []

    func append(_ progress: CostScanProgress) {
        values.append(progress)
    }

    func phases() -> [CostScanPhase] {
        values.map(\.phase)
    }
}
