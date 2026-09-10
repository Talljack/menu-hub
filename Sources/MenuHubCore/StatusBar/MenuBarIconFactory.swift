import AppKit

public enum MenuBarIconFactory {
    public static func makeImage(pointSize: CGFloat = HubPresentation.imagePointSize) -> NSImage {
        makeImage(presentation: .hidden, pointSize: pointSize)
    }

    public static func makeImage(
        presentation: UnreadBadgePresentation,
        pointSize: CGFloat = HubPresentation.imagePointSize
    ) -> NSImage {
        guard let label = presentation.label else { return makeBaseImage(pointSize: pointSize) }
        let normalizedLabel = label == "99+" ? label : String(min(max(Int(label) ?? 1, 1), 99))
        let capsuleWidth = 12 + CGFloat(max(0, normalizedLabel.count - 1)) * 5.5
        let spacing: CGFloat = 2
        let size = NSSize(width: pointSize + spacing + capsuleWidth, height: pointSize)
        let baseImage = makeBaseImage(pointSize: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            baseImage.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize))

            let capsuleRect = NSRect(
                x: pointSize + spacing,
                y: (rect.height - 13) / 2,
                width: capsuleWidth,
                height: 13
            )
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: capsuleRect,
                xRadius: capsuleRect.height / 2,
                yRadius: capsuleRect.height / 2
            ).fill()

            let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let text = NSAttributedString(string: normalizedLabel, attributes: attributes)
            let textSize = text.size()
            let textOrigin = NSPoint(
                x: capsuleRect.midX - textSize.width / 2,
                y: capsuleRect.midY - textSize.height / 2 + 0.5
            )
            let oldOperation = NSGraphicsContext.current?.compositingOperation
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            text.draw(at: textOrigin)
            if let oldOperation { NSGraphicsContext.current?.compositingOperation = oldOperation }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = HubPresentation.accessibilityLabel
        return image
    }

    private static func makeBaseImage(pointSize: CGFloat) -> NSImage {
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
