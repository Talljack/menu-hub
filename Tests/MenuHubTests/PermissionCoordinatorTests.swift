import XCTest
@testable import MenuHub
@testable import MenuHubCore

@MainActor
final class PermissionCoordinatorTests: XCTestCase {
    func testDidBecomeActiveFalseTrueTrueAuthorizesAndScansOnlyOnce() async {
        let accessibility = CoordinatorAccessibility()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher()
        )
        let model = HubPanelModel(controller: controller, initialPermissionState: .unknown)
        let center = NotificationCenter()
        let trust = TrustValue(false)
        let coordinator = PermissionCoordinator(
            model: model, notificationCenter: center, trustProvider: { trust.value }
        )
        coordinator.start()

        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        trust.value = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await accessibility.waitForScanRequests(1)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()

        XCTAssertEqual(model.permissionState, .authorized)
        let scanCount = await accessibility.scanCount
        XCTAssertEqual(scanCount, 1)
        coordinator.stop()
    }

    func testStartRechecksTrustSoGrantBetweenInitializationAndObservationIsNotMissed() async {
        let accessibility = CoordinatorAccessibility()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: accessibility, launcher: FakeLauncher()
        )
        let model = HubPanelModel(controller: controller, initialPermissionState: .unknown)
        let trust = TrustValue(false)
        let coordinator = PermissionCoordinator(
            model: model, notificationCenter: NotificationCenter(), trustProvider: { trust.value }
        )

        trust.value = true
        coordinator.start()
        await accessibility.waitForScanRequests(1)

        XCTAssertEqual(model.permissionState, .authorized)
        let scanCount = await accessibility.scanCount
        XCTAssertEqual(scanCount, 1)
        coordinator.stop()
    }

    func testDefaultRepairConfirmationFailsClosed() {
        let handler = UnconfirmedRepairHandler()
        let controller = CatalogController(
            store: FakeCatalogStore(), accessibility: CoordinatorAccessibility(), launcher: FakeLauncher()
        )
        let model = HubPanelModel(
            controller: controller,
            initialPermissionState: .repairRequired(reason: .operationDenied),
            permissionEffectHandler: handler
        )

        model.confirmPermissionRepair()

        XCTAssertEqual(model.permissionState, .repairRequired(reason: .operationDenied))
        XCTAssertEqual(handler.resetRequests, 0)
    }
}

@MainActor
private final class TrustValue {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

@MainActor
private final class UnconfirmedRepairHandler: PermissionEffectHandling {
    private(set) var resetRequests = 0
    func requestSystemPrompt() {}
    func openAccessibilitySettings() {}
    func requestAccessibilityReset() -> Bool { resetRequests += 1; return true }
}

private actor CoordinatorAccessibility: AccessibilityServing {
    private(set) var scanCount = 0

    func scan() async -> AccessibilityScanResult {
        scanCount += 1
        return .init(snapshots: [], errors: [])
    }

    func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError> {
        .success(())
    }

    func waitForScanRequests(_ count: Int) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while scanCount < count, ContinuousClock.now < deadline { await Task.yield() }
        if scanCount < count { XCTFail("Timed out waiting for \(count) scan requests") }
    }
}
