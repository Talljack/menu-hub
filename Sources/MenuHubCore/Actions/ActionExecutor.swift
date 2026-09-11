import Foundation

public protocol ApplicationLaunching: Sendable {
    func launch(bundleIdentifier: String) async -> Bool
}

public enum ActionFailure: Error, Equatable, Sendable {
    case accessibility(AccessibilityDomainError)
    case launchFailed(bundleIdentifier: String)
}

public enum ActionOutcome: Equatable, Sendable {
    case pressed
    case openedHost
    case unavailable
    case failed(ActionFailure)
}

public struct ActionExecutor: Sendable {
    private let accessibility: any AccessibilityServing
    private let launcher: any ApplicationLaunching
    private let scanTimeout: Duration
    private let pressTimeout: Duration

    public init(
        accessibility: any AccessibilityServing,
        launcher: any ApplicationLaunching,
        scanTimeout: Duration = .seconds(2),
        pressTimeout: Duration = .milliseconds(1_200)
    ) {
        self.accessibility = accessibility
        self.launcher = launcher
        self.scanTimeout = scanTimeout
        self.pressTimeout = pressTimeout
    }

    public func execute(
        _ item: MenuBarItemRecord,
        snapshot: AccessibilitySnapshot
    ) async -> ActionOutcome {
        switch ActionPolicy.defaultAction(for: item.capability) {
        case .unavailable:
            return .unavailable
        case .openHostApplication:
            let bundleIdentifier = item.identity.bundleIdentifier
            return await launcher.launch(bundleIdentifier: bundleIdentifier)
                ? .openedHost
                : .failed(.launchFailed(bundleIdentifier: bundleIdentifier))
        case .press:
            guard item.identity.stableID == snapshot.menuBarItemIdentity.stableID else {
                return .failed(.accessibility(.staleElement))
            }
            return await press(snapshot, for: item.identity)
        }
    }

    private func press(
        _ snapshot: AccessibilitySnapshot,
        for identity: MenuBarItemIdentity
    ) async -> ActionOutcome {
        guard let first = await withTimeout(pressTimeout, operation: { [accessibility] in
            await accessibility.press(snapshot)
        }) else {
            return .failed(.accessibility(.targetUnresponsive))
        }

        switch first {
        case .success:
            return .pressed
        case .failure(let error) where error == .staleElement || error == .elementNotFound:
            return await refreshAndRetry(identity: identity)
        case .failure(let error):
            return .failed(.accessibility(error))
        }
    }

    private func refreshAndRetry(identity: MenuBarItemIdentity) async -> ActionOutcome {
        guard let result = await withTimeout(scanTimeout, operation: { [accessibility] in
            await accessibility.scan()
        }) else {
            return .failed(.accessibility(.targetUnresponsive))
        }

        let matches = result.snapshots.filter { $0.menuBarItemIdentity.stableID == identity.stableID }
        guard matches.count == 1, let refreshed = matches.first else {
            if result.issues.contains(.permissionDenied) {
                return .failed(.accessibility(.permissionDenied))
            }
            if !result.issues.isEmpty {
                return .failed(.accessibility(.targetUnresponsive))
            }
            let error: AccessibilityDomainError = matches.isEmpty ? .elementNotFound : .ambiguousMatch
            return .failed(.accessibility(error))
        }

        guard let retry = await withTimeout(pressTimeout, operation: { [accessibility] in
            await accessibility.press(refreshed)
        }) else {
            return .failed(.accessibility(.targetUnresponsive))
        }
        switch retry {
        case .success:
            return .pressed
        case .failure(let error):
            return .failed(.accessibility(error))
        }
    }

}

private final class TimeoutCompletion<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var operationTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var isFinished = false

    func install(_ continuation: CheckedContinuation<Value?, Never>) {
        lock.lock()
        let finished = isFinished
        if !finished { self.continuation = continuation }
        lock.unlock()
        if finished { continuation.resume(returning: nil) }
    }

    func registerOperation(_ task: Task<Void, Never>) -> Bool {
        lock.lock()
        let registered = !isFinished
        if registered { operationTask = task }
        lock.unlock()
        if !registered { task.cancel() }
        return registered
    }

    func installTimer(_ task: Task<Void, Never>) {
        lock.lock()
        timerTask = task
        let finished = isFinished
        lock.unlock()
        if finished { task.cancel() }
    }

    func operationFinished(_ value: Value) {
        finish(value, cancelOperation: false)
    }

    func timeoutOrCancel() {
        finish(nil, cancelOperation: true)
    }

    private func finish(_ value: Value?, cancelOperation: Bool) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let pending = continuation
        continuation = nil
        let operation = operationTask
        let timer = timerTask
        lock.unlock()

        if cancelOperation { operation?.cancel() }
        timer?.cancel()
        pending?.resume(returning: value)
    }
}

private final class OperationStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var decision: Bool?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let decision {
                lock.unlock()
                continuation.resume(returning: decision)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func open(_ shouldStart: Bool) {
        lock.lock()
        guard decision == nil else {
            lock.unlock()
            return
        }
        decision = shouldStart
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: shouldStart)
    }
}

private func withTimeout<Value: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async -> Value
) async -> Value? {
    // Cancellation bounds the caller and prevents queued or later work. It cannot
    // interrupt a synchronous Accessibility system call that has already started;
    // any such late result is discarded by TimeoutCompletion.
    let completion = TimeoutCompletion<Value>()
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: duration)
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            completion.install(continuation)
            let startGate = OperationStartGate()
            let operationTask = Task.detached {
                guard await startGate.wait() else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                let value = await operation()
                guard !Task.isCancelled else { return }
                guard clock.now < deadline else {
                    completion.timeoutOrCancel()
                    return
                }
                completion.operationFinished(value)
            }
            let registered = completion.registerOperation(operationTask)
            startGate.open(registered)
            let timerTask = Task.detached {
                do {
                    try await clock.sleep(until: deadline)
                    completion.timeoutOrCancel()
                } catch {
                    return
                }
            }
            completion.installTimer(timerTask)
        }
    } onCancel: {
        completion.timeoutOrCancel()
    }
}
