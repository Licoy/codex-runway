public enum StatusMouseButton: Sendable, Equatable {
    case left
    case right
}

public enum StatusAction: Sendable, Equatable {
    case showPopover
    case closePopover
    case showMenu
}

public enum StatusInteraction {
    public static func route(mouseButton: StatusMouseButton, isPopoverShown: Bool) -> StatusAction {
        switch mouseButton {
        case .right:
            return .showMenu
        case .left:
            return isPopoverShown ? .closePopover : .showPopover
        }
    }
}
