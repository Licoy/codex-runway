import AppKit

@MainActor
extension StatusController {
    func installStatusBarView() {
        guard let button = statusItem.button else { return }
        button.title = ""
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(statusBarView)
        NSLayoutConstraint.activate([
            statusBarView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            statusBarView.topAnchor.constraint(equalTo: button.topAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        updateStatusBarView()
    }

    func updateStatusBarView() {
        statusBarView.update(
            style: settings.preferences.statusBarDisplayStyle,
            metersDetailStyle: settings.preferences.statusBarMetersDetailStyle,
            batteryScope: settings.preferences.statusBarBatteryScope,
            batteryDetailStyle: settings.preferences.statusBarBatteryDetailStyle,
            language: settings.l10n.language,
            text: model.statusText,
            meters: model.quotaMeters)
        statusItem.length = statusBarView.preferredWidth
        statusItem.button?.toolTip = "Codex Runway · \(model.statusText)"
    }
}
