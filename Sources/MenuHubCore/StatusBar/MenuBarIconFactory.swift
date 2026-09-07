import AppKit

public enum MenuBarIconFactory {
    public static func makeImage(pointSize: CGFloat = HubPresentation.imagePointSize) -> NSImage {
        if let symbol = NSImage(
            systemSymbolName: HubPresentation.systemSymbolName,
            accessibilityDescription: HubPresentation.accessibilityLabel
        )?.withSymbolConfiguration(.init(pointSize: pointSize - 2, weight: .semibold)) {
            symbol.size = NSSize(width: pointSize, height: pointSize)
            symbol.isTemplate = true
            return symbol
        }

        // Only used if the system symbol is unexpectedly unavailable.
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSColor.black.setFill()

            let scale = rect.width / 18
            let centers = [
                NSPoint(x: 9, y: 4.3),
                NSPoint(x: 13.7, y: 9),
                NSPoint(x: 9, y: 13.7),
                NSPoint(x: 4.3, y: 9),
            ]

            for center in centers {
                let center = NSPoint(x: center.x * scale, y: center.y * scale)
                let side = 5.7 * scale
                let tileRect = NSRect(
                    x: center.x - side / 2,
                    y: center.y - side / 2,
                    width: side,
                    height: side
                )
                let path = NSBezierPath(
                    roundedRect: tileRect,
                    xRadius: 1.6 * scale,
                    yRadius: 1.6 * scale
                )
                var transform = AffineTransform()
                transform.translate(x: center.x, y: center.y)
                transform.rotate(byDegrees: 45)
                transform.translate(x: -center.x, y: -center.y)
                path.transform(using: transform)
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = HubPresentation.accessibilityLabel
        return image
    }
}
