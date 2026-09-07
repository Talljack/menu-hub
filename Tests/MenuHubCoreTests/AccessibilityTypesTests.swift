import ApplicationServices
import XCTest
@testable import MenuHubCore

final class AccessibilityTypesTests: XCTestCase {
    func testMapsAXErrorsToStableDomainErrors() {
        XCTAssertEqual(AccessibilityDomainError(axError: .apiDisabled), .permissionDenied)
        XCTAssertEqual(AccessibilityDomainError(axError: .invalidUIElement), .staleElement)
        XCTAssertEqual(AccessibilityDomainError(axError: .actionUnsupported), .actionUnsupported)
        XCTAssertEqual(AccessibilityDomainError(axError: .cannotComplete), .targetUnresponsive)
        XCTAssertEqual(AccessibilityDomainError(axError: .noValue), .elementNotFound)
    }

    func testCapabilityUsesNamePressAndLaunchFallback() {
        XCTAssertEqual(ItemCapability.classify(hasName: true, actions: ["AXPress"], canLaunchHost: true), .full)
        XCTAssertEqual(ItemCapability.classify(hasName: false, actions: ["AXPress"], canLaunchHost: true), .actionable)
        XCTAssertEqual(ItemCapability.classify(hasName: true, actions: [], canLaunchHost: true), .launchOnly)
        XCTAssertEqual(ItemCapability.classify(hasName: true, actions: [], canLaunchHost: false), .unavailable)
    }

    func testDiagnosticSummaryIncludesGeometry() {
        let snapshot = AccessibilitySnapshot(
            processIdentifier: 42,
            processName: "Menu Hub",
            bundleIdentifier: "com.local.MenuHub",
            title: "MH",
            role: "AXMenuBarItem",
            subrole: nil,
            identifier: nil,
            positionX: 1200,
            positionY: 0,
            width: 28,
            height: 24,
            actions: ["AXPress"],
            accessibilityPath: [0]
        )

        XCTAssertTrue(snapshot.diagnosticSummary.contains("x=1200"))
        XCTAssertTrue(snapshot.diagnosticSummary.contains("width=28"))
    }
}
