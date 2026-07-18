import AppKit
import CodexRunwayCore
import SwiftUI

@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusBarView = StatusBarContentView(frame: .zero)
    private let popover = NSPopover()
    let settings = RunwaySettings()
    lazy var model = RunwayModel(settings: settings)
    private lazy var updaterService = UpdaterService(settings: settings)
    private var statusMenu: NSMenu?
    private var detailsWindow: NSWindow?
    private var controlPanelWindow: NSWindow?
    private var eventMonitor: Any?
    private var localPopoverCloseMonitor: Any?
    private var globalPopoverCloseMonitor: Any?
    private var resignActiveObserver: NSObjectProtocol?
    private var lastEventNumber: Int?
    private var lastQuotaResetRefresh: Date?
    private var refreshSchedule = RefreshSchedule()
    private var timer: Timer?

    func start() {
        let button = statusItem.button
        button?.toolTip = "Codex Runway"
        button?.target = self
        button?.action = #selector(handleStatusItemClick(_:))
        button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        installStatusBarView()
        model.onFullRefreshCompleted = { [weak self] in
            self?.fullRefreshCompleted()
        }
        settings.onChange = { [weak self] in
            self?.applyAppearance()
            self?.model.relabel()
            self?.updaterService.applyPreferences()
            self?.refreshIntervalChanged()
            self?.rebuildHostedViews()
            self?.updateStatusBarView()
        }
        updaterService.applyPreferences()
        applyAppearance()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 560)
        popover.contentViewController = NSHostingController(rootView: popoverView())
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
        installEventMonitor()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        beginFullRefresh(policy: .ifChanged)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true { return }
        handleStatusEvent(NSApp.currentEvent, relativeTo: sender)
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.eventHitsStatusButton(event) else { return event }
            if event.modifierFlags.contains(.command) { return event }
            self.handleStatusEvent(event, relativeTo: self.statusItem.button)
            return nil
        }
    }

    private func tick() {
        let now = Date()
        model.tick(now: now)
        updateStatusBarView()
        if let reset = model.nextDueQuotaReset(after: lastQuotaResetRefresh, now: now), !model.isRefreshing {
            lastQuotaResetRefresh = reset
            beginFullRefresh(policy: .ifChanged)
            return
        }
        if refreshSchedule.isDue(at: now), !model.isRefreshing {
            beginFullRefresh(policy: .ifChanged)
        }
    }

    private func beginFullRefresh(policy: UsageCostRefreshPolicy) {
        guard !model.isRefreshing else { return }
        refreshSchedule.refreshStarted()
        model.refresh(policy: policy)
    }

    private func fullRefreshCompleted(at completion: Date = Date()) {
        refreshSchedule.refreshCompleted(at: completion, interval: refreshInterval)
    }

    private func refreshIntervalChanged(now: Date = Date()) {
        refreshSchedule.intervalChanged(to: refreshInterval, now: now)
    }

    private var refreshInterval: TimeInterval {
        TimeInterval(settings.preferences.refreshIntervalSeconds)
    }

    private func applyAppearance() {
        let appearance: NSAppearance?
        switch settings.preferences.appearance {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
        popover.contentViewController?.view.window?.appearance = appearance
        detailsWindow?.appearance = appearance
        controlPanelWindow?.appearance = appearance
    }

    private func rebuildHostedViews() {
        popover.contentViewController = NSHostingController(rootView: popoverView())
        if let detailsWindow {
            detailsWindow.contentViewController = NSHostingController(rootView: popoverView())
            detailsWindow.title = "Codex Runway"
        }
        if let controlPanelWindow {
            controlPanelWindow.title = settings.l10n.text(.controlPanel)
        }
    }

    private func popoverView() -> RunwayPopoverView {
        RunwayPopoverView(
            model: model,
            settings: settings,
            checkForUpdates: { [weak self] in self?.updaterService.checkForUpdates() },
            openGitHub: { ExternalURLLauncher.open(ControlPanelView.githubURL) },
            openControlPanel: { [weak self] in self?.showControlPanel() })
    }

    private func eventHitsStatusButton(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button, event.window === button.window else { return false }
        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }

    private func handleStatusEvent(_ event: NSEvent?, relativeTo button: NSStatusBarButton?) {
        if let event, lastEventNumber == event.eventNumber { return }
        lastEventNumber = event?.eventNumber
        let mouseButton = Self.mouseButton(from: event)
        let panelShown = popover.isShown || (detailsWindow?.isVisible == true)
        switch StatusInteraction.route(mouseButton: mouseButton, isPopoverShown: panelShown) {
        case .showMenu:
            if let button { showMenu(relativeTo: button) }
        case .showPopover:
            showPopover()
        case .closePopover:
            closePopover()
            closeDetailsWindow()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if !popover.isShown {
            showDetailsWindow()
            return
        }
        applyAppearance()
        // Do not makeKeyAndOrderFront: that breaks NSPopover.transient auto-dismiss.
        popover.contentViewController?.view.window?.orderFront(nil)
        startPopoverCloseMonitors()
        refreshVisiblePopoverSections()
    }

    func popoverDidClose(_ notification: Notification) {
        stopPopoverCloseMonitors()
    }

    private func startPopoverCloseMonitors() {
        stopPopoverCloseMonitors()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localPopoverCloseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown) { [weak self] event in
            guard let self else { return event }
            if self.shouldClosePopover(for: event) {
                self.closePopover()
            }
            return event
        }
        // Global monitor covers clicks outside this process (desktop / other apps).
        // Accessory apps often do not resign active on empty desktop clicks.
        globalPopoverCloseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                if self.shouldClosePopover(for: event) {
                    self.closePopover()
                }
            }
        }
    }

    private func stopPopoverCloseMonitors() {
        if let localPopoverCloseMonitor {
            NSEvent.removeMonitor(localPopoverCloseMonitor)
            self.localPopoverCloseMonitor = nil
        }
        if let globalPopoverCloseMonitor {
            NSEvent.removeMonitor(globalPopoverCloseMonitor)
            self.globalPopoverCloseMonitor = nil
        }
    }

    private func shouldClosePopover(for event: NSEvent) -> Bool {
        guard popover.isShown else { return false }
        return StatusInteraction.shouldClosePopover(
            hitStatusButton: eventHitsStatusButton(event) || eventHitsStatusButtonScreen(event),
            hitPopover: eventHitsPopover(event))
    }

    private func eventHitsPopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = popover.contentViewController?.view.window else { return false }
        if event.window === popoverWindow { return true }
        // Global monitors may not attach event.window; fall back to screen coordinates.
        let screenPoint = NSEvent.mouseLocation
        return popoverWindow.frame.contains(screenPoint)
    }

    private func eventHitsStatusButtonScreen(_ event: NSEvent) -> Bool {
        guard let button = statusItem.button, let buttonWindow = button.window else { return false }
        if event.window === buttonWindow {
            return eventHitsStatusButton(event)
        }
        let screenPoint = NSEvent.mouseLocation
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        return screenRect.contains(screenPoint)
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        stopPopoverCloseMonitors()
    }

    private func showDetailsWindow() {
        let window = detailsWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Codex Runway"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: popoverView())
        detailsWindow = window
        applyAppearance()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        startDetailsWindowCloseMonitors()
        refreshVisiblePopoverSections()
    }

    private func startDetailsWindowCloseMonitors() {
        // Reuse the same monitors: close details window when clicking outside.
        stopPopoverCloseMonitors()
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        localPopoverCloseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown) { [weak self] event in
            guard let self else { return event }
            if self.shouldCloseDetailsWindow(for: event) {
                self.closeDetailsWindow()
            }
            return event
        }
        globalPopoverCloseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                if self.shouldCloseDetailsWindow(for: event) {
                    self.closeDetailsWindow()
                }
            }
        }
    }

    private func shouldCloseDetailsWindow(for event: NSEvent) -> Bool {
        guard let detailsWindow, detailsWindow.isVisible else { return false }
        if eventHitsStatusButton(event) || eventHitsStatusButtonScreen(event) { return false }
        if event.window === detailsWindow { return false }
        let screenPoint = NSEvent.mouseLocation
        if detailsWindow.frame.contains(screenPoint) { return false }
        return true
    }

    private func closeDetailsWindow() {
        detailsWindow?.orderOut(nil)
        stopPopoverCloseMonitors()
    }

    private func refreshVisiblePopoverSections() {
        if settings.preferences.showsCostSummary {
            model.refreshCost(policy: .ifChanged)
        }
        if settings.preferences.showsSessionRepairSummary {
            model.refreshSessionReport()
        }
        if settings.preferences.showsRecentSessions {
            model.refreshRecentSessions()
        }
    }

    private func showControlPanel() {
        let window = controlPanelWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 546, height: 662),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = settings.l10n.text(.controlPanel)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 546, height: 662))
        window.contentViewController = NSHostingController(rootView: ControlPanelView(
            settings: settings,
            model: model,
            checkForUpdates: { [weak self] in self?.updaterService.checkForUpdates() }))
        controlPanelWindow = window
        applyAppearance()
        NSApp.activate(ignoringOtherApps: true)
        centerControlPanel(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func centerControlPanel(_ window: NSWindow) {
        let visibleFrame = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2)
        window.setFrameOrigin(origin)
    }

    private func showMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        populateMenu(menu)
        statusMenu = menu
        closePopover()
        closeDetailsWindow()
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
        }
    }

    private static func mouseButton(from event: NSEvent?) -> StatusMouseButton {
        guard let event else { return .left }
        if event.type == .rightMouseDown || event.type == .rightMouseUp || event.buttonNumber == 1 {
            return .right
        }
        if event.modifierFlags.contains(.control) {
            return .right
        }
        return .left
    }

    @objc func showDetailsFromMenu() {
        showPopover()
    }

    @objc func openDetailsWindowFromMenu() {
        showDetailsWindow()
    }

    @objc func openControlPanelFromMenu() {
        showControlPanel()
    }

    @objc func refreshFromMenu() {
        beginFullRefresh(policy: .force)
        showPopover()
    }

    @objc func checkForUpdatesFromMenu() {
        updaterService.checkForUpdates()
    }

    @objc func repairFromMenu() {
        let alert = NSAlert()
        alert.messageText = settings.l10n.text(.repairConfirmTitle)
        alert.informativeText = model.repairWarning
        alert.addButton(withTitle: settings.l10n.text(.repair))
        alert.addButton(withTitle: settings.l10n.text(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.repairSessions()
        showPopover()
    }

    @objc func openCodexFolder() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
