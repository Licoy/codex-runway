import CodexRunwayCore
import SwiftUI

/// Confirmation sheet for real account switch, with optional Codex restart.
struct AccountSwitchConfirmSheet: View {
    var accountName: String
    var l10n: L10n
    @Binding var restartAfterSwitch: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(l10n.text(.accountsSwitchConfirmTitle))
                .font(.headline)
            Text(String(format: l10n.text(.accountsSwitchConfirmMessage), accountName))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $restartAfterSwitch) {
                Text(l10n.text(.accountsRestartCodexAfterSwitch))
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            HStack {
                Spacer()
                Button(l10n.text(.cancel), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(l10n.text(.accountsMakeCurrent), action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
