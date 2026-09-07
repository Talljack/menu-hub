public enum ItemDefaultAction: Equatable, Sendable {
    case press
    case openHostApplication
    case unavailable
}

public enum ActionPolicy: Sendable {
    public static func defaultAction(for capability: ItemCapability) -> ItemDefaultAction {
        switch capability {
        case .full, .actionable:
            .press
        case .launchOnly:
            .openHostApplication
        case .unavailable:
            .unavailable
        }
    }

    public static func secondaryActions(for capability: ItemCapability) -> [ItemDefaultAction] {
        switch capability {
        case .full, .actionable:
            [.openHostApplication]
        case .launchOnly, .unavailable:
            []
        }
    }
}
