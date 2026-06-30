import CodexRunwayCore
import Foundation
@preconcurrency import UserNotifications

struct RunwayNotificationService {
    func deliver(_ alerts: [RunwayAlert], l10n: L10n) {
        guard !alerts.isEmpty else { return }
        let requests = alerts.map { alert in
            let content = UNMutableNotificationContent()
            content.title = title(for: alert, l10n: l10n)
            content.body = body(for: alert, l10n: l10n)
            content.sound = .default
            return UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for request in requests {
                UNUserNotificationCenter.current().add(request)
            }
        }
    }

    private func title(for alert: RunwayAlert, l10n: L10n) -> String {
        switch alert.kind {
        case .quota:
            return l10n.text(.quotaAlertTitle)
        case .resetCredit:
            return l10n.text(.resetCreditAlertTitle)
        }
    }

    private func body(for alert: RunwayAlert, l10n: L10n) -> String {
        switch alert.kind {
        case .quota:
            return String(
                format: l10n.text(.quotaAlertBody),
                displayName(for: alert.name, l10n: l10n),
                alert.threshold.map { "\($0)%" } ?? "--")
        case .resetCredit:
            return l10n.text(.resetCreditAlertBody)
        }
    }

    private func displayName(for name: String, l10n: L10n) -> String {
        if name == "5-hour" { return l10n.text(.fiveHourUsage) }
        if name == "Weekly" { return l10n.text(.weeklyUsage) }
        return name
    }
}
