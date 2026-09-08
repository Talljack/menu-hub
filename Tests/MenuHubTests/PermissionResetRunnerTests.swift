import Darwin
import XCTest
@testable import MenuHub

@MainActor
final class PermissionResetRunnerTests: XCTestCase {
    func testTimeoutSendsTermThenKillToSameVerifiedPIDAndReapsExactlyOnce() async {
        let process = FakeResetProcess(pid: 4242)
        let signals = SignalRecorder(process: process)
        let runner = AccessibilityResetProcessRunner(
            processFactory: { process }, timeoutTicks: 2, graceTicks: 1,
            sleep: {}, signal: { pid, signal in signals.send(pid: pid, signal: signal) }
        )
        var completions: [Bool] = []

        runner.start(arguments: ["reset", "Accessibility", "com.local.MenuHub"]) { completions.append($0) }
        await process.waitForReap()
        await waitForCompletion { !completions.isEmpty }

        XCTAssertEqual(signals.values.map(\.0), [4242, 4242])
        XCTAssertEqual(signals.values.map(\.1), [SIGTERM, SIGKILL])
        XCTAssertEqual(process.waitCount, 1)
        XCTAssertEqual(completions, [false])
    }

    func testSuccessfulExitCompletesOnMainActorExactlyOnce() async {
        let process = FakeResetProcess(pid: 123, running: false, status: 0)
        let runner = AccessibilityResetProcessRunner(
            processFactory: { process }, timeoutTicks: 1, graceTicks: 1,
            sleep: {}, signal: { _, _ in 0 }
        )
        var completions: [Bool] = []

        runner.start(arguments: ["reset", "Accessibility", "com.local.MenuHub"]) { completions.append($0) }
        await process.waitForReap()
        await waitForCompletion { !completions.isEmpty }

        XCTAssertEqual(process.waitCount, 1)
        XCTAssertEqual(completions, [true])
    }

    private func waitForCompletion(_ completed: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !completed(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }
}

private final class FakeResetProcess: AccessibilityResetProcess, @unchecked Sendable {
    let processIdentifier: Int32
    private let lock = NSLock()
    private var running: Bool
    private let status: Int32
    private(set) var waitCount = 0

    init(pid: Int32, running: Bool = true, status: Int32 = 0) {
        processIdentifier = pid
        self.running = running
        self.status = status
    }

    var isRunning: Bool { lock.withLock { running } }
    var terminationStatus: Int32 { status }
    func run(arguments: [String]) throws {}
    func markKilled() { lock.withLock { running = false } }
    func waitUntilExit() { lock.withLock { waitCount += 1; running = false } }
    func waitForReap() async {
        let deadline = ContinuousClock.now + .seconds(1)
        while lock.withLock({ waitCount == 0 }), ContinuousClock.now < deadline { await Task.yield() }
        if lock.withLock({ waitCount == 0 }) { XCTFail("process was not reaped") }
    }
}

private final class SignalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let process: FakeResetProcess
    private var storage: [(Int32, Int32)] = []
    init(process: FakeResetProcess) { self.process = process }
    var values: [(Int32, Int32)] { lock.withLock { storage } }
    func send(pid: Int32, signal: Int32) -> Int32 {
        lock.withLock { storage.append((pid, signal)) }
        if signal == SIGKILL { process.markKilled() }
        return 0
    }
}
