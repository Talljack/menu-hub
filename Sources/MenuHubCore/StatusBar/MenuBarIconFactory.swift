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
        let size = NSSize(width: pointSize, height: pointSize)
        let baseImage = makeBaseImage(pointSize: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            baseImage.draw(in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize))

            let capsuleWidth: CGFloat = switch normalizedLabel.count {
            case 1: 10
            case 2: 13.5
            default: 18
            }
            let capsuleRect = NSRect(
                x: rect.maxX - capsuleWidth,
                y: rect.maxY - 10,
                width: capsuleWidth,
                height: 10
            )
            let capsulePath = NSBezierPath(
                roundedRect: capsuleRect,
                xRadius: capsuleRect.height / 2,
                yRadius: capsuleRect.height / 2
            )

            // A transparent keyline keeps the badge distinct from the template
            // mark in both light and dark menu bars without introducing color.
            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(
                roundedRect: capsuleRect.insetBy(dx: -0.75, dy: -0.75),
                xRadius: (capsuleRect.height + 1.5) / 2,
                yRadius: (capsuleRect.height + 1.5) / 2
            ).fill()
            NSGraphicsContext.current?.restoreGraphicsState()

            NSColor.black.setFill()
            capsulePath.fill()

            let fontSize: CGFloat = normalizedLabel.count > 2 ? 6.2 : 7.3
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let text = NSAttributedString(string: normalizedLabel, attributes: attributes)
            let textSize = text.size()
            let textOrigin = NSPoint(
                x: capsuleRect.midX - textSize.width / 2,
                y: capsuleRect.midY - textSize.height / 2 + 0.25
            )
            NSGraphicsContext.current?.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            text.draw(at: textOrigin)
            NSGraphicsContext.current?.restoreGraphicsState()
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
