import Foundation

enum HubItemActionPanelPage: Equatable {
    case commands
    case rename
    case groups
}

enum HubItemActionPanelEscapeResult: Equatable {
    case stayPresented
    case dismiss
}

struct HubItemActionPanelConfiguration: Equatable {
    let canOpenHost: Bool
    let hasGroups: Bool
    let isInvoking: Bool

    func visibleCommands(showsMore: Bool) -> [HubItemActionPanelCommand] {
        HubItemActionPanelCommand.visible(
            canOpenHost: canOpenHost,
            hasGroups: hasGroups,
            showsMore: showsMore
        )
    }
}

struct HubItemActionPanelState: Equatable {
    var isPresented: Bool
    private(set) var page: HubItemActionPanelPage = .commands
    var aliasDraft = ""
    private(set) var showsMoreActions = false

    init(isPresented: Bool = false) {
        self.isPresented = isPresented
    }

    mutating func present(alias: String?) {
        isPresented = true
        page = .commands
        aliasDraft = alias ?? ""
        showsMoreActions = false
    }

    mutating func dismiss() {
        isPresented = false
        page = .commands
        showsMoreActions = false
    }

    mutating func toggle(alias: String?) {
        if isPresented {
            dismiss()
        } else {
            present(alias: alias)
        }
    }

    mutating func applyExternalRequest(_ requested: Bool, alias: String?) {
        if requested {
            present(alias: alias)
        }
    }

    mutating func showRename() {
        page = .rename
        showsMoreActions = false
    }

    mutating func showGroups() {
        page = .groups
        showsMoreActions = false
    }

    mutating func showCommands() {
        page = .commands
    }

    mutating func toggleMoreActions() {
        page = .commands
        showsMoreActions.toggle()
    }

    mutating func handleEscape() -> HubItemActionPanelEscapeResult {
        if page != .commands {
            page = .commands
            return .stayPresented
        }
        if showsMoreActions {
            showsMoreActions = false
            return .stayPresented
        }
        return .dismiss
    }
}
