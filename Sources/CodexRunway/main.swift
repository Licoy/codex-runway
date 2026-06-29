import AppKit
import CodexRunwayCore

if CommandLine.arguments.contains("--self-check") {
    SelfCheck.run()
    exit(0)
}

guard let instanceGuard = try? SingleInstanceGuard.acquire() else {
    exit(0)
}

private let delegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = delegate
withExtendedLifetime(instanceGuard) {
    app.run()
}
