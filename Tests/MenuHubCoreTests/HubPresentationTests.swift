import XCTest
import AppKit
@testable import MenuHubCore

final class HubPresentationTests: XCTestCase {
    func testMenuBarEntryUsesBrandedTemplateImage() {
        XCTAssertEqual(HubPresentation.imageName, "MenuBarIcon")
        XCTAssertEqual(HubPresentation.systemSymbolName, "square.grid.2x2.fill")
        XCTAssertEqual(HubPresentation.fallbackTitle, "MH")
        XCTAssertEqual(HubPresentation.accessibilityLabel, "Menu Hub")
        XCTAssertEqual(HubPresentation.toolTip, "Menu Hub")
        XCTAssertEqual(HubPresentation.imagePointSize, 18)
    }

    func testSetupMarkerUsesConcreteWidthInsteadOfStatusItemSentinel() {
        XCTAssertEqual(SpacerPresentation.minimumMarkerWidth, 28)
    }

    func testVectorMenuBarIconIsAVisibleTemplateAtStatusBarSize() throws {
        let image = MenuBarIconFactory.makeImage()

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)

        let representation = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        var visiblePixelCount = 0
        for y in 0..<representation.pixelsHigh {
            for x in 0..<representation.pixelsWide where (representation.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                visiblePixelCount += 1
            }
        }
        XCTAssertGreaterThan(visiblePixelCount, 50)
    }

    func testUnreadTemplateKeepsAConstantStatusItemFootprint() {
        let hidden = MenuBarIconFactory.makeImage(presentation: .hidden)
        let one = MenuBarIconFactory.makeImage(presentation: .count(7))
        let two = MenuBarIconFactory.makeImage(presentation: .count(42))
        let overflow = MenuBarIconFactory.makeImage(presentation: .overflow)

        XCTAssertTrue([hidden, one, two, overflow].allSatisfy(\.isTemplate))
        XCTAssertEqual(one.size, hidden.size)
        XCTAssertEqual(two.size, hidden.size)
        XCTAssertEqual(overflow.size, hidden.size)
        XCTAssertTrue([hidden, one, two, overflow].allSatisfy { $0.size.height == 18 })
        for image in [one, two, overflow] {
            let representation = try? XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            let visiblePixels = representation.map { bitmap in
                (0..<bitmap.pixelsHigh).reduce(into: 0) { total, y in
                    total += (0..<bitmap.pixelsWide).filter {
                        (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.35
                    }.count
                }
            } ?? 0
            XCTAssertGreaterThan(visiblePixels, 50)
        }
    }

    func testUnreadCountIsClampedToSupportedCapsuleRange() {
        XCTAssertEqual(
            MenuBarIconFactory.makeImage(presentation: .count(123)).size,
            MenuBarIconFactory.makeImage(presentation: .count(99)).size
        )
        XCTAssertEqual(
            MenuBarIconFactory.makeImage(presentation: .count(0)).size,
            MenuBarIconFactory.makeImage(presentation: .count(1)).size
        )
    }
}
