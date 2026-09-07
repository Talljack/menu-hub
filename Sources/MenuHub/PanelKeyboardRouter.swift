import AppKit

enum PanelKeyboardModifier: Hashable { case command, option, control, shift }

struct PanelKeyboardEventContext {
    let keyCode: UInt16
    let characters: String?
    let modifiers: Set<PanelKeyboardModifier>
    let hasMarkedText: Bool
}

enum PanelKeyboardCommand: Equatable {
    case upArrow
    case downArrow
    case returnKey
    case commandReturn
    case commandK
    case commandF
    case commandDigit(Int)
    case escape
}

enum PanelKeyboardAction: Equatable {
    case selectPrevious
    case selectNext
    case invokeSelection
    case openHost
    case openActionMenu
    case focusSearch
    case invokeFavorite(Int)
    case clearSearch
    case closePanel
}

struct PanelKeyboardRouter {
    func action(for command: PanelKeyboardCommand, hasSearchText: Bool) -> PanelKeyboardAction {
        switch command {
        case .upArrow: return .selectPrevious
        case .downArrow: return .selectNext
        case .returnKey: return .invokeSelection
        case .commandReturn: return .openHost
        case .commandK: return .openActionMenu
        case .commandF: return .focusSearch
        case .commandDigit(let digit): return .invokeFavorite(digit - 1)
        case .escape: return hasSearchText ? .clearSearch : .closePanel
        }
    }

    @MainActor
    func command(for event: NSEvent) -> PanelKeyboardCommand? {
        var modifiers = Set<PanelKeyboardModifier>()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        let marked = (event.window?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
        return command(for: .init(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
            modifiers: modifiers, hasMarkedText: marked
        ))
    }

    func command(for context: PanelKeyboardEventContext) -> PanelKeyboardCommand? {
        guard !context.hasMarkedText else { return nil }
        let plain = context.modifiers.isEmpty
        let commandOnly = context.modifiers == [.command]
        switch context.keyCode {
        case 126 where plain: return .upArrow
        case 125 where plain: return .downArrow
        case 36 where plain, 76 where plain: return .returnKey
        case 36 where commandOnly, 76 where commandOnly: return .commandReturn
        case 53 where plain: return .escape
        case 3 where commandOnly: return .commandF
        case 40 where commandOnly: return .commandK
        default:
            guard commandOnly, let value = Int(context.characters ?? ""), (1...9).contains(value) else { return nil }
            return .commandDigit(value)
        }
    }
}

struct HubItemPresentationID: RawRepresentable, Hashable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(sectionID: String, itemID: String) { rawValue = "\(sectionID):\(itemID)" }
    static func canonical(itemID: String) -> Self { .init(sectionID: "all", itemID: itemID) }
}

enum HubPanelPresentationContext {
    static func canonicalSectionID(query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "all" : "search"
    }

    static func canonicalPresentationID(itemID: String, query: String) -> HubItemPresentationID {
        HubItemPresentationID(sectionID: canonicalSectionID(query: query), itemID: itemID)
    }
}

struct ScrollEdgeState: Equatable {
    let canScrollUp: Bool
    let canScrollDown: Bool
    static let none = Self(canScrollUp: false, canScrollDown: false)

    static func resolve(contentHeight: CGFloat, viewportHeight: CGFloat, contentOffset: CGFloat) -> Self {
        guard contentHeight > viewportHeight + 1 else { return .none }
        return Self(
            canScrollUp: contentOffset < -1,
            canScrollDown: contentHeight + contentOffset > viewportHeight + 1
        )
    }
}
