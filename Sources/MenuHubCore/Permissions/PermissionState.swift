public enum PermissionExplanationDestination: Equatable, Sendable {
    case systemPrompt
    case settings
}

public enum PermissionRepairReason: Equatable, Sendable {
    case operationDenied
    case trustRevoked
}

public enum PermissionState: Equatable, Sendable {
    case unknown
    case explanation(PermissionExplanationDestination)
    case awaitingSystemChange
    case authorized
    case denied
    case repairRequired(reason: PermissionRepairReason)
    case resetting
}

public enum PermissionEvent: Equatable, Sendable {
    case featureRequested
    case explanationAccepted
    case explanationSkipped
    case openedSettings
    case applicationBecameActive(isTrusted: Bool)
    case operationDenied
    case repairConfirmed
    case resetCompleted
}

public enum PermissionEffect: Equatable, Sendable {
    case showExplanation
    case requestSystemPrompt
    case openSettings
    case setAuthorized
    case setDenied
    case enterLauncherMode
    case offerRepair
    case resetRequested
    case scan
}

public struct PermissionTransition: Equatable, Sendable {
    /// The complete permission state that UI should render after an event.
    public let state: PermissionState

    /// Ordered, one-shot work for the integration layer. Consumers must execute
    /// these in array order. `setAuthorized` and `setDenied` coordinate external
    /// services only; they do not represent additional UI state.
    public let effects: [PermissionEffect]

    public init(state: PermissionState, effects: [PermissionEffect] = []) {
        self.state = state
        self.effects = effects
    }
}

public extension PermissionState {
    /// Reduces one event without performing I/O. `state` is the sole UI truth;
    /// effects describe imperative work for a consumer and are never replayed.
    func reduce(_ event: PermissionEvent) -> PermissionTransition {
        // Trust observations can be stale while the external reset is in flight.
        // Only reset completion may advance this state.
        if self == .resetting, case .applicationBecameActive = event {
            return PermissionTransition(state: self)
        }

        if case .applicationBecameActive(isTrusted: true) = event {
            guard self != .authorized else {
                return PermissionTransition(state: self)
            }
            return PermissionTransition(state: .authorized, effects: [.setAuthorized, .scan])
        }

        switch (self, event) {
        case (.unknown, .featureRequested):
            return PermissionTransition(state: .explanation(.systemPrompt), effects: [.showExplanation])

        case (.denied, .featureRequested):
            return PermissionTransition(state: .explanation(.settings), effects: [.showExplanation])

        case let (.explanation(destination), .explanationAccepted):
            let effect: PermissionEffect = destination == .systemPrompt ? .requestSystemPrompt : .openSettings
            return PermissionTransition(state: .awaitingSystemChange, effects: [effect])

        case (.explanation, .explanationSkipped):
            return PermissionTransition(state: .denied, effects: [.setDenied, .enterLauncherMode])

        case (.awaitingSystemChange, .applicationBecameActive(isTrusted: false)):
            return PermissionTransition(state: .denied, effects: [.setDenied, .enterLauncherMode])

        case (.authorized, .applicationBecameActive(isTrusted: false)):
            return repairTransition(reason: .trustRevoked)

        case (.authorized, .operationDenied):
            return repairTransition(reason: .operationDenied)

        case (.repairRequired, .repairConfirmed):
            return PermissionTransition(state: .resetting, effects: [.resetRequested])

        case (.resetting, .resetCompleted):
            return PermissionTransition(state: .awaitingSystemChange, effects: [.openSettings])

        default:
            return PermissionTransition(state: self)
        }
    }

    private func repairTransition(reason: PermissionRepairReason) -> PermissionTransition {
        PermissionTransition(
            state: .repairRequired(reason: reason),
            effects: [.setDenied, .enterLauncherMode, .offerRepair]
        )
    }
}
