import AppKit
import MenuHubCore

enum StatusItemIdentity {
    static let primaryAutosaveName: NSStatusItem.AutosaveName = "com.local.MenuHub.primary"
    static let spacerAutosaveName: NSStatusItem.AutosaveName = "com.local.MenuHub.spacer"
}

@MainActor
struct StatusItemBadgeRenderer {
    func apply(
        _ presentation: UnreadBadgePresentation,
        to item: NSStatusItem,
        button: NSStatusBarButton
    ) {
        let image = MenuBarIconFactory.makeImage(presentation: presentation)
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        item.length = presentation == .hidden ? NSStatusItem.squareLength : image.size.width + 6
    }
}
