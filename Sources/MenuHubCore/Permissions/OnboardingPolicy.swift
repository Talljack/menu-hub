public enum OnboardingMode: Equatable, Sendable {
    case launcher
    case full
}

public enum OnboardingStep: Equatable, Sendable {
    case welcome
    case capabilityBoundary
    case permission
    case statusItemPlacement(mode: OnboardingMode)
    case scanSummary(mode: OnboardingMode)
    case shortcutConfirmation(mode: OnboardingMode)
}

public enum OnboardingChoice: Equatable, Sendable {
    case `continue`
    case skip
    case authorized
}

public enum OnboardingPolicy {
    public static func next(after step: OnboardingStep, choice: OnboardingChoice) -> OnboardingStep {
        switch (step, choice) {
        case (.welcome, _):
            return .capabilityBoundary
        case (.capabilityBoundary, _):
            return .permission
        case (.permission, .authorized):
            return .scanSummary(mode: .full)
        case (.permission, .skip), (.permission, .continue):
            return .scanSummary(mode: .launcher)
        case let (.scanSummary(mode), _):
            return .statusItemPlacement(mode: mode)
        case let (.statusItemPlacement(mode), _):
            return .shortcutConfirmation(mode: mode)
        case (.shortcutConfirmation, _):
            return step
        }
    }

    public static func previous(before step: OnboardingStep) -> OnboardingStep? {
        switch step {
        case .welcome:
            return nil
        case .capabilityBoundary:
            return .welcome
        case .permission:
            return .capabilityBoundary
        case .scanSummary:
            return .permission
        case let .statusItemPlacement(mode):
            return .scanSummary(mode: mode)
        case let .shortcutConfirmation(mode):
            return .statusItemPlacement(mode: mode)
        }
    }

    public static func authorizedVersion(of step: OnboardingStep) -> OnboardingStep {
        switch step {
        case .statusItemPlacement:
            return .statusItemPlacement(mode: .full)
        case .scanSummary:
            return .scanSummary(mode: .full)
        case .shortcutConfirmation:
            return .shortcutConfirmation(mode: .full)
        default:
            return step
        }
    }

    public static func canFinish(_ step: OnboardingStep) -> Bool {
        if case .shortcutConfirmation = step { return true }
        return false
    }
}

public enum AccessibilityRepairPolicy {
    public static func resetArguments(userConfirmed: Bool) -> [String]? {
        guard userConfirmed else { return nil }
        return ["reset", "Accessibility", "com.local.MenuHub"]
    }
}

public struct OnboardingCapabilitySummary: Equatable, Sendable {
    public let pressableCount: Int
    public let launchOnlyCount: Int
    public let unavailableCount: Int

    public var totalCount: Int { pressableCount + launchOnlyCount + unavailableCount }

    public init(capabilities: [ItemCapability]) {
        var pressable = 0
        var launchOnly = 0
        var unavailable = 0
        for capability in capabilities {
            switch capability {
            case .full, .actionable: pressable += 1
            case .launchOnly: launchOnly += 1
            case .unavailable: unavailable += 1
            }
        }
        pressableCount = pressable
        launchOnlyCount = launchOnly
        unavailableCount = unavailable
    }
}
