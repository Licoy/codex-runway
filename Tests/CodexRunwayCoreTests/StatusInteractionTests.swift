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

    @Test("outside clicks close the popover unless they hit the status button or panel")
    func outsideClickDismissRules() {
        #expect(StatusInteraction.shouldClosePopover(hitStatusButton: false, hitPopover: false))
        #expect(!StatusInteraction.shouldClosePopover(hitStatusButton: true, hitPopover: false))
        #expect(!StatusInteraction.shouldClosePopover(hitStatusButton: false, hitPopover: true))
        #expect(!StatusInteraction.shouldClosePopover(hitStatusButton: true, hitPopover: true))
    }

    @Test("presented sheets or modals block outside-click dismiss")
    func presentedModalBlocksDismiss() {
        #expect(
            !StatusInteraction.shouldClosePopover(
                hitStatusButton: false,
                hitPopover: false,
                hasPresentedModal: true))
        #expect(
            StatusInteraction.shouldClosePopover(
                hitStatusButton: false,
                hitPopover: false,
                hasPresentedModal: false))
    }
}
