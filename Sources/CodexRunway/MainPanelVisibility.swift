import SwiftUI

/// Tracks whether the status-item main panel (popover or details window) is on screen.
/// Used to pause expensive TimelineView work while the panel is hidden.
@MainActor
final class MainPanelVisibility: ObservableObject {
    @Published var isVisible = false
}

private struct RunwayPanelVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// When false, progress shimmer and similar panel-only animations should pause.
    var runwayPanelVisible: Bool {
        get { self[RunwayPanelVisibleKey.self] }
        set { self[RunwayPanelVisibleKey.self] = newValue }
    }
}
