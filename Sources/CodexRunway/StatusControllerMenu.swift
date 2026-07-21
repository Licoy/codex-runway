import AppKit

extension StatusController {
    func populateMenu(_ menu: NSMenu) {
        let l10n = settings.l10n
        menu.removeAllItems()
        menu.addItem(disabledMenuItem("Codex Runway · \(model.statusText)"))
        addSection(l10n.text(.quota), text: model.quotaText, lines: model.quotaLines, to: menu)
        if settings.preferences.showsRateLimitResetToday {
            addSection(
                l10n.text(.rateLimitResetToday),
                text: model.rateLimitResetTodayText,
                lines: model.rateLimitResetTodayLines,
                to: menu)
        }
        addSection(l10n.text(.resetCredits), text: model.resetCreditsText, lines: model.resetCreditLines, to: menu)
        addSection(l10n.text(.apiCost), text: model.costText, lines: model.costLines, to: menu)
        addSection(l10n.text(.sessionRepair), text: model.sessionText, lines: model.sessionLines, to: menu)
        addSection(l10n.text(.recentSessions), text: "\(model.recentSessions.count)", lines: model.recentSessionLines, to: menu)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(l10n.text(.showDetails), action: #selector(showDetailsFromMenu)))
        menu.addItem(menuItem(l10n.text(.openDetailsWindow), action: #selector(openDetailsWindowFromMenu)))
        menu.addItem(menuItem(l10n.text(.openControlPanel), action: #selector(openControlPanelFromMenu)))
        menu.addItem(menuItem(l10n.text(.refresh), action: #selector(refreshFromMenu)))
        menu.addItem(menuItem(l10n.text(.checkForUpdates), action: #selector(checkForUpdatesFromMenu)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(l10n.text(.repairIndex), action: #selector(repairFromMenu)))
        menu.addItem(menuItem(l10n.text(.codexFolder), action: #selector(openCodexFolder)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(l10n.text(.quit), action: #selector(quit)))
    }

    private func addSection(_ title: String, text: String, lines: [RunwayModel.DetailLine], to menu: NSMenu) {
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledMenuItem("\(title): \(text)"))
        for line in lines.prefix(8) {
            menu.addItem(disabledMenuItem("  \(line.title): \(line.value)"))
        }
    }

    private func disabledMenuItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: Self.menuTitle(title), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func menuTitle(_ value: String) -> String {
        value.count > 96 ? String(value.prefix(93)) + "..." : value
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
