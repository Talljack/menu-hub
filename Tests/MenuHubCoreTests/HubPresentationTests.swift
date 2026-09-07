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
}
