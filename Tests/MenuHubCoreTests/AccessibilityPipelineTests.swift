import XCTest
import ApplicationServices
@testable import MenuHubCore

final class AccessibilityPipelineTests: XCTestCase {
    func testApplicationInspectionExcludesTheScannerProcessItself() {
        let appURL = URL(fileURLWithPath: "/Applications/Menu Hub.app")

        XCTAssertFalse(AccessibilityClient.shouldInspect(
            processIdentifier: 42,
            currentProcessIdentifier: 42,
            bundleURL: appURL
        ))
        XCTAssertTrue(AccessibilityClient.shouldInspect(
            processIdentifier: 43,
            currentProcessIdentifier: 42,
            bundleURL: appURL
        ))
    }

    func testAXReadIssueClassificationTreatsExpectedAbsenceAsNormal() {
        XCTAssertNil(AccessibilityScanIssue.issue(
            for: .noValue,
            processIdentifier: 42,
            process: "Status App"
        ))
        XCTAssertNil(AccessibilityScanIssue.issue(
            for: .attributeUnsupported,
            processIdentifier: 42,
            process: "Status App"
        ))
    }

    func testAXReadIssueClassificationPreservesPermissionRevocation() {
        XCTAssertEqual(
            AccessibilityScanIssue.issue(for: .apiDisabled, processIdentifier: 42, process: "Status App"),
            .permissionDenied
        )
    }

    func testAXReadIssueClassificationPreservesProcessFailure() {
        XCTAssertEqual(
            AccessibilityScanIssue.issue(for: .cannotComplete, processIdentifier: 42, process: "Status App"),
            .processFailure(
                processIdentifier: 42,
                process: "Status App",
                error: .targetUnresponsive
            )
        )
    }

    func testResolvedElementWithDifferentAXIdentifierIsRejected() {
        XCTAssertFalse(AccessibilityClient.matchesResolvedIdentity(
            snapshot: snapshot(),
            resolvedIdentifier: "different-item",
            resolvedTitle: "Sync",
            resolvedRole: "AXMenuBarItem",
            resolvedSubrole: nil
        ))
    }

    func testFallbackElementWithDifferentRoleOrSubroleIsRejected() {
        let fallback = snapshot(identifier: nil, path: [1])
        XCTAssertFalse(AccessibilityClient.matchesResolvedIdentity(
            snapshot: fallback,
            resolvedIdentifier: nil,
            resolvedTitle: "Sync",
            resolvedRole: "AXButton",
            resolvedSubrole: nil
        ))
        XCTAssertFalse(AccessibilityClient.matchesResolvedIdentity(
            snapshot: AccessibilitySnapshot(
                processIdentifier: fallback.processIdentifier,
                processName: fallback.processName,
                bundleIdentifier: fallback.bundleIdentifier,
                title: fallback.title,
                role: fallback.role,
                subrole: "AXMenuExtra",
                identifier: nil,
                positionX: fallback.positionX,
                positionY: fallback.positionY,
                width: fallback.width,
                height: fallback.height,
                actions: fallback.actions,
                accessibilityPath: fallback.accessibilityPath
            ),
            resolvedIdentifier: nil,
            resolvedTitle: "Sync",
            resolvedRole: "AXMenuBarItem",
            resolvedSubrole: "AXOther"
        ))
    }

    func testPermissionDeniedDoesNotRescanOrRetry() async {
        let accessibility = FakeAccessibility(pressResults: [.failure(.permissionDenied)])
        let launcher = FakeLauncher(result: true)
        let outcome = await makeExecutor(accessibility, launcher).execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .failed(.accessibility(.permissionDenied)))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 1)
        XCTAssertEqual(counts.scan, 0)
    }

    func testMismatchedRecordAndSnapshotNeverPresses() async {
        let accessibility = FakeAccessibility()
        let mismatchedSnapshot = snapshot(identifier: "another-item")

        let outcome = await makeExecutor(accessibility, FakeLauncher(result: true))
            .execute(item(), snapshot: mismatchedSnapshot)

        XCTAssertEqual(outcome, .failed(.accessibility(.staleElement)))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 0)
        XCTAssertEqual(counts.scan, 0)
    }

    func testStaleElementRescansAndRetriesUniqueResolvedSnapshotOnce() async {
        let refreshed = snapshot(path: [9])
        let accessibility = FakeAccessibility(
            scans: [.init(snapshots: [refreshed], errors: ["one app could not be inspected"])],
            pressResults: [.failure(.staleElement), .success(())]
        )
        let launcher = FakeLauncher(result: true)

        let outcome = await makeExecutor(accessibility, launcher).execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .pressed)
        let state = await accessibility.state
        XCTAssertEqual(state.scan, 1)
        XCTAssertEqual(state.pressed, [snapshot(), refreshed])
    }

    func testStaleElementWithNoResolvedSnapshotFailsWithoutSecondPress() async {
        let accessibility = FakeAccessibility(
            scans: [.init(snapshots: [], errors: [])],
            pressResults: [.failure(.staleElement)]
        )

        let outcome = await makeExecutor(accessibility, FakeLauncher(result: true))
            .execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .failed(.accessibility(.elementNotFound)))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 1)
        XCTAssertEqual(counts.scan, 1)
    }

    func testAmbiguousRefreshNeverPressesEitherMatch() async {
        let accessibility = FakeAccessibility(
            scans: [.init(snapshots: [snapshot(path: [4]), snapshot(path: [8])], errors: [])],
            pressResults: [.failure(.elementNotFound)]
        )

        let outcome = await makeExecutor(accessibility, FakeLauncher(result: true))
            .execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .failed(.accessibility(.ambiguousMatch)))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 1)
        XCTAssertEqual(counts.scan, 1)
    }

    func testPermissionIssueDuringRefreshTakesPriorityOverNoMatch() async {
        let accessibility = FakeAccessibility(
            scans: [.init(snapshots: [], issues: [.permissionDenied])],
            pressResults: [.failure(.staleElement)]
        )

        let outcome = await makeExecutor(accessibility, FakeLauncher(result: true))
            .execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .failed(.accessibility(.permissionDenied)))
    }

    func testIncompleteRefreshTakesPriorityOverAmbiguousMatch() async {
        let accessibility = FakeAccessibility(
            scans: [.init(
                snapshots: [snapshot(path: [4]), snapshot(path: [8])],
                issues: [.traversalLimit(process: "Status App")]
            )],
            pressResults: [.failure(.elementNotFound)]
        )

        let outcome = await makeExecutor(accessibility, FakeLauncher(result: true))
            .execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .failed(.accessibility(.targetUnresponsive)))
    }

    func testBlankIdentifierFallbackRetriesOnlySamePathMatch() async {
        let original = snapshot(identifier: " ", path: [1])
        let refreshed = snapshot(identifier: nil, path: [1])
        let accessibility = FakeAccessibility(
            scans: [.init(snapshots: [refreshed], issues: [])],
            pressResults: [.failure(.staleElement), .success(())]
        )

        let outcome = await makeExecutor(accessibility, FakeLauncher(result: true))
            .execute(item(identifier: nil), snapshot: original)

        XCTAssertEqual(outcome, .pressed)
        let state = await accessibility.state
        XCTAssertEqual(state.pressed, [original, refreshed])
    }

    func testFallbackPathChangeDoesNotRetryPress() async {
        let accessibility = FakeAccessibility(
            scans: [.init(snapshots: [snapshot(identifier: nil, path: [9])], issues: [])],
            pressResults: [.failure(.staleElement)]
        )

        let outcome = await makeExecutor(accessibility, FakeLauncher(result: true))
            .execute(item(identifier: nil), snapshot: snapshot(identifier: nil, path: [1]))

        XCTAssertEqual(outcome, .failed(.accessibility(.elementNotFound)))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 1)
    }

    func testLaunchOnlyReportsSuccessAndFailure() async {
        let accessibility = FakeAccessibility()
        let successLauncher = FakeLauncher(result: true)
        let failureLauncher = FakeLauncher(result: false)
        let launchItem = item(capability: .launchOnly)

        let successOutcome = await makeExecutor(accessibility, successLauncher)
            .execute(launchItem, snapshot: snapshot())
        let failureOutcome = await makeExecutor(accessibility, failureLauncher)
            .execute(launchItem, snapshot: snapshot())
        let successCalls = await successLauncher.calls
        let failureCalls = await failureLauncher.calls
        XCTAssertEqual(successOutcome, .openedHost)
        XCTAssertEqual(failureOutcome, .failed(.launchFailed(bundleIdentifier: "com.example.status")))
        XCTAssertEqual(successCalls, ["com.example.status"])
        XCTAssertEqual(failureCalls, ["com.example.status"])
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 0)
        XCTAssertEqual(counts.scan, 0)
    }

    func testUnavailablePerformsNoCalls() async {
        let accessibility = FakeAccessibility()
        let launcher = FakeLauncher(result: true)

        let outcome = await makeExecutor(accessibility, launcher)
            .execute(item(capability: .unavailable), snapshot: snapshot())

        XCTAssertEqual(outcome, .unavailable)
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 0)
        XCTAssertEqual(counts.scan, 0)
        let launchCalls = await launcher.calls
        XCTAssertEqual(launchCalls, [])
    }

    func testPressTimeoutIsBoundedAndDoesNotRescan() async {
        let accessibility = FakeAccessibility(pressDelay: .milliseconds(80))
        let executor = ActionExecutor(
            accessibility: accessibility,
            launcher: FakeLauncher(result: true),
            scanTimeout: .milliseconds(30),
            pressTimeout: .milliseconds(30)
        )
        let clock = ContinuousClock()
        let start = clock.now

        let outcome = await executor.execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .failed(.accessibility(.targetUnresponsive)))
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(500))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 1)
        XCTAssertEqual(counts.scan, 0)
        try? await Task.sleep(for: .milliseconds(120))
        let lateCounts = await accessibility.counts
        XCTAssertEqual(lateCounts.scan, 0)
    }

    func testDefaultPressAllowsSlowButResponsiveTarget() async {
        let accessibility = FakeAccessibility(pressDelay: .milliseconds(700))
        let outcome = await ActionExecutor(
            accessibility: accessibility,
            launcher: FakeLauncher(result: true)
        ).execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .pressed)
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 1)
        XCTAssertEqual(counts.scan, 0)
    }

    func testRefreshScanTimeoutDoesNotPerformRetryPress() async {
        let accessibility = FakeAccessibility(
            scans: [.init(snapshots: [snapshot(path: [9])], errors: [])],
            pressResults: [.failure(.staleElement)],
            scanDelay: .milliseconds(80)
        )
        let executor = ActionExecutor(
            accessibility: accessibility,
            launcher: FakeLauncher(result: true),
            scanTimeout: .milliseconds(30),
            pressTimeout: .milliseconds(30)
        )

        let outcome = await executor.execute(item(), snapshot: snapshot())

        XCTAssertEqual(outcome, .failed(.accessibility(.targetUnresponsive)))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 1)
        XCTAssertEqual(counts.scan, 1)
        try? await Task.sleep(for: .milliseconds(120))
        let completed = await accessibility.completedCounts
        // A scan can finish at the same instant the timeout wins. Its late result
        // must be discarded; the safety invariant is that it never triggers a retry press.
        XCTAssertEqual(completed.press, 1)
    }

    func testOuterTaskCancellationCancelsInFlightPress() async {
        let accessibility = FakeAccessibility(pressDelay: .milliseconds(200))
        let executor = ActionExecutor(
            accessibility: accessibility,
            launcher: FakeLauncher(result: true),
            pressTimeout: .seconds(1)
        )
        let record = item()
        let initialSnapshot = snapshot()
        let task = Task { await executor.execute(record, snapshot: initialSnapshot) }
        try? await Task.sleep(for: .milliseconds(20))

        task.cancel()
        let outcome = await task.value
        try? await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(outcome, .failed(.accessibility(.targetUnresponsive)))
        let completed = await accessibility.completedCounts
        XCTAssertEqual(completed.press, 0)
    }

    func testAlreadyCancelledParentNeverStartsPressOperation() async {
        let accessibility = FakeAccessibility()
        let executor = makeExecutor(accessibility, FakeLauncher(result: true))
        let record = item()
        let initialSnapshot = snapshot()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await executor.execute(record, snapshot: initialSnapshot)
        }

        let outcome = await task.value
        XCTAssertEqual(outcome, .failed(.accessibility(.targetUnresponsive)))
        try? await Task.sleep(for: .milliseconds(30))
        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 0)
    }

    func testImmediateCancellationStressNeverStartsPressOperation() async {
        let accessibility = FakeAccessibility()
        let executor = makeExecutor(accessibility, FakeLauncher(result: true))
        let record = item()
        let initialSnapshot = snapshot()
        var tasks: [Task<ActionOutcome, Never>] = []

        for _ in 0..<200 {
            let task = Task { await executor.execute(record, snapshot: initialSnapshot) }
            task.cancel()
            tasks.append(task)
        }
        for task in tasks { _ = await task.value }
        try? await Task.sleep(for: .milliseconds(30))

        let counts = await accessibility.counts
        XCTAssertEqual(counts.press, 0)
    }

    private func makeExecutor(
        _ accessibility: FakeAccessibility,
        _ launcher: FakeLauncher
    ) -> ActionExecutor {
        ActionExecutor(accessibility: accessibility, launcher: launcher)
    }

    private func snapshot(
        identifier: String? = "sync-item",
        path: [Int] = [1]
    ) -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            processIdentifier: 42,
            processName: "Status App",
            bundleIdentifier: "com.example.status",
            title: "Sync",
            role: "AXMenuBarItem",
            subrole: nil,
            identifier: identifier,
            positionX: 10,
            positionY: 2,
            width: 20,
            height: 20,
            actions: ["AXPress"],
            accessibilityPath: path
        )
    }

    private func item(
        capability: ItemCapability = .full,
        identifier: String? = "sync-item"
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            identity: MenuBarItemIdentity(
                processIdentifier: 42,
                bundleIdentifier: "com.example.status",
                originalName: "Sync",
                axIdentifier: identifier,
                path: [1]
            ),
            hostName: "Status App",
            capability: capability,
            lastSeenAt: .distantPast
        )
    }
}

private actor FakeAccessibility: AccessibilityServing {
    private var scans: [AccessibilityScanResult]
    private var pressResults: [Result<Void, AccessibilityDomainError>]
    private let scanDelay: Duration?
    private let pressDelay: Duration?
    private(set) var scanCount = 0
    private(set) var pressed: [AccessibilitySnapshot] = []
    private(set) var completedScanCount = 0
    private(set) var completedPressCount = 0

    init(
        scans: [AccessibilityScanResult] = [],
        pressResults: [Result<Void, AccessibilityDomainError>] = [.success(())],
        scanDelay: Duration? = nil,
        pressDelay: Duration? = nil
    ) {
        self.scans = scans
        self.pressResults = pressResults
        self.scanDelay = scanDelay
        self.pressDelay = pressDelay
    }

    func scan() async -> AccessibilityScanResult {
        scanCount += 1
        if let scanDelay {
            do { try await Task.sleep(for: scanDelay) }
            catch { return .init(snapshots: [], issues: [.targetUnresponsive(process: nil)]) }
        }
        completedScanCount += 1
        return scans.isEmpty ? .init(snapshots: [], errors: []) : scans.removeFirst()
    }

    func press(_ snapshot: AccessibilitySnapshot) async -> Result<Void, AccessibilityDomainError> {
        pressed.append(snapshot)
        if let pressDelay {
            do { try await Task.sleep(for: pressDelay) }
            catch { return .failure(.targetUnresponsive) }
        }
        completedPressCount += 1
        return pressResults.isEmpty ? .success(()) : pressResults.removeFirst()
    }

    var counts: (scan: Int, press: Int) { (scanCount, pressed.count) }
    var state: (scan: Int, pressed: [AccessibilitySnapshot]) { (scanCount, pressed) }
    var completedCounts: (scan: Int, press: Int) { (completedScanCount, completedPressCount) }
}

private actor FakeLauncher: ApplicationLaunching {
    private let result: Bool
    private(set) var calls: [String] = []

    init(result: Bool) { self.result = result }

    func launch(bundleIdentifier: String) async -> Bool {
        calls.append(bundleIdentifier)
        return result
    }
}
