import AppKit

@MainActor
final class MenuHubApplication: NSApplication {
    var favoriteKeyHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, favoriteKeyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

MainActor.assumeIsolated {
    let application = MenuHubApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
