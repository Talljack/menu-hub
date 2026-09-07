import AppKit
import Darwin
import MenuHubCore

protocol AccessibilityResetProcess: AnyObject, Sendable {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    var terminationStatus: Int32 { get }
    func run(arguments: [String]) throws
    func waitUntilExit()
}

private final class FoundationAccessibilityResetProcess: AccessibilityResetProcess, @unchecked Sendable {
    private let process = Process()
    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }
    var terminationStatus: Int32 { process.terminationStatus }
    func run(arguments: [String]) throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments
        try process.run()
    }
    func waitUntilExit() { process.waitUntilExit() }
}

@MainActor
final class AccessibilityResetProcessRunner {
    typealias Sleep = @Sendable () async throws -> Void
    typealias Signal = @Sendable (Int32, Int32) -> Int32

    private let processFactory: @Sendable () -> any AccessibilityResetProcess
    private let timeoutTicks: Int
    private let graceTicks: Int
    private let sleep: Sleep
    private let signal: Signal
    private var task: Task<Void, Never>?

    init(
        processFactory: @escaping @Sendable () -> any AccessibilityResetProcess = { FoundationAccessibilityResetProcess() },
        timeoutTicks: Int = 200,
        graceTicks: Int = 20,
        sleep: @escaping Sleep = { try await Task.sleep(for: .milliseconds(25)) },
        signal: @escaping Signal = { pid, value in Darwin.kill(pid, value) }
    ) {
        self.processFactory = processFactory
        self.timeoutTicks = max(1, timeoutTicks)
        self.graceTicks = max(1, graceTicks)
        self.sleep = sleep
        self.signal = signal
    }

    func start(arguments: [String], completion: @escaping @MainActor (Bool) -> Void) {
        task?.cancel()
        let processFactory = processFactory
        let timeoutTicks = timeoutTicks
        let graceTicks = graceTicks
        let sleep = sleep
        let signal = signal
        task = Task.detached(priority: .userInitiated) {
            let process = processFactory()
            let result = await Self.execute(
                process: process, arguments: arguments, timeoutTicks: timeoutTicks,
                graceTicks: graceTicks, sleep: sleep, signal: signal
            )
            await completion(result)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private nonisolated static func execute(
        process: any AccessibilityResetProcess,
        arguments: [String],
        timeoutTicks: Int,
        graceTicks: Int,
        sleep: Sleep,
        signal: Signal
    ) async -> Bool {
        do { try process.run(arguments: arguments) }
        catch { return false }

        let verifiedPID = process.processIdentifier
        var timedOutOrCancelled = false
        for _ in 0..<timeoutTicks where process.isRunning {
            do { try await sleep() }
            catch { timedOutOrCancelled = true; break }
        }
        if !process.isRunning {
            process.waitUntilExit()
            return !timedOutOrCancelled && process.terminationStatus == 0
        }

        guard verifiedPID > 1, process.processIdentifier == verifiedPID else { return false }
        _ = signal(verifiedPID, SIGTERM)
        for _ in 0..<graceTicks where process.isRunning {
            do { try await sleep() } catch { break }
        }
        if process.isRunning, process.processIdentifier == verifiedPID {
            _ = signal(verifiedPID, SIGKILL)
        }
        process.waitUntilExit()
        return false
    }
}

@MainActor
final class PermissionCoordinator: NSObject {
    private weak var model: HubPanelModel?
    private let notificationCenter: NotificationCenter
    private let trustProvider: @MainActor () -> Bool
    private var lastObservedTrust: Bool?
    private var isObserving = false

    init(
        model: HubPanelModel,
        notificationCenter: NotificationCenter = .default,
        trustProvider: @escaping @MainActor () -> Bool = { AccessibilityClient.isTrusted() }
    ) {
        self.model = model
        self.notificationCenter = notificationCenter
        self.trustProvider = trustProvider
        lastObservedTrust = nil
        super.init()
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        recheckPermission()
    }

    func stop() {
        guard isObserving else { return }
        notificationCenter.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        isObserving = false
    }

    @objc private func applicationDidBecomeActive() {
        recheckPermission()
    }

    func recheckPermission() {
        let trusted = trustProvider()
        let changed = lastObservedTrust != trusted
        lastObservedTrust = trusted
        guard let model else { return }
        // A false result still has meaning while awaiting a System Settings
        // round-trip. Other unchanged observations are intentionally ignored.
        if changed || model.permissionState == .awaitingSystemChange {
            model.applicationBecameActive(isTrusted: trusted)
        }
    }
}

@MainActor
final class SystemPermissionEffectHandler: PermissionEffectHandling {
    private let resetRunner = AccessibilityResetProcessRunner()
    func requestSystemPrompt() {
        _ = AccessibilityClient.isTrusted(prompt: true)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func confirmAccessibilityReset() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("permission.repairTitle")
        alert.informativeText = L("permission.repairBody")
        alert.addButton(withTitle: L("permission.resetAndAuthorize"))
        alert.addButton(withTitle: L("common.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    func requestAccessibilityReset() -> Bool {
        false
    }

    func requestAccessibilityReset(completion: @escaping @MainActor (Bool) -> Void) {
        guard let arguments = AccessibilityRepairPolicy.resetArguments(userConfirmed: true) else {
            completion(false)
            return
        }
        resetRunner.start(arguments: arguments, completion: completion)
    }

    func cancelAccessibilityReset() { resetRunner.cancel() }
}
