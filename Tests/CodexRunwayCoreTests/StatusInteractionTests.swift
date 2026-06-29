import Testing
@testable import CodexRunwayCore

@Suite("Status interaction")
struct StatusInteractionTests {
    @Test("routes left click to popover and right click to menu")
    func routesMouseEvents() {
        #expect(StatusInteraction.route(mouseButton: .left, isPopoverShown: false) == .showPopover)
        #expect(StatusInteraction.route(mouseButton: .left, isPopoverShown: true) == .closePopover)
        #expect(StatusInteraction.route(mouseButton: .right, isPopoverShown: false) == .showMenu)
    }
}
