import Foundation

public struct HotKeyDescriptor: Codable, Equatable, Sendable {
    public var keyCode: UInt32?
    public var modifiers: Set<HotKeyModifier>

    public init(keyCode: UInt32?, modifiers: Set<HotKeyModifier>) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(_ preference: HotKeyPreference) {
        self.init(keyCode: preference.keyCode, modifiers: preference.modifiers)
    }

    public static let `default` = Self(keyCode: 46, modifiers: [.option])

    public var preference: HotKeyPreference {
        HotKeyPreference(keyCode: keyCode, modifiers: modifiers)
    }

    public var isValid: Bool {
        guard let keyCode, !modifiers.isEmpty else { return false }
        return !Self.modifierKeyCodes.contains(keyCode)
    }

    public var displayString: String {
        let modifierSymbols: [(HotKeyModifier, String)] = [
            (.control, "⌃"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘"),
        ]
        let prefix = modifierSymbols
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()
        return prefix + Self.keyLabel(for: keyCode)
    }

    public static func keyLabel(for keyCode: UInt32?) -> String {
        guard let keyCode else { return "—" }
        // ANSI positions are a stable fallback. A recorder can replace this with the current input source.
        return ansiKeyLabels[keyCode] ?? "Key \(keyCode)"
    }

    private static let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static let ansiKeyLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1",
        19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9",
        26: "7", 28: "8", 29: "0", 31: "O", 32: "U", 34: "I",
        35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        49: "Space",
    ]
}

public enum HotKeyRegistrationTransactionOutcome: Equatable, Sendable {
    case registered
    case conflict
    case candidateFailed
    case oldUnregisterFailed(candidateRolledBack: Bool)
}

public struct HotKeyRegistrationState: Equatable, Sendable {
    public private(set) var handlerInstalled = false
    public private(set) var activeDescriptor: HotKeyDescriptor?
    public private(set) var activeIdentifier: UInt32?
    public private(set) var orphanedIdentifiers: [UInt32] = []

    public init() {}

    public var needsHandlerInstallation: Bool { !handlerInstalled }
    public var canAttemptRegistration: Bool { orphanedIdentifiers.isEmpty }

    public mutating func recordHandlerInstallation(succeeded: Bool) {
        handlerInstalled = succeeded
    }

    public mutating func recordRegistration(
        descriptor: HotKeyDescriptor,
        identifier: UInt32,
        outcome: HotKeyRegistrationTransactionOutcome
    ) {
        switch outcome {
        case .registered:
            activeDescriptor = descriptor
            activeIdentifier = identifier
        case .conflict, .candidateFailed:
            break
        case let .oldUnregisterFailed(candidateRolledBack):
            if !candidateRolledBack, !orphanedIdentifiers.contains(identifier) {
                orphanedIdentifiers.append(identifier)
            }
        }
    }

    public mutating func recordOrphanCleanup(identifier: UInt32, succeeded: Bool) {
        guard succeeded else { return }
        orphanedIdentifiers.removeAll { $0 == identifier }
    }

    public func matchesEvent(
        signature: UInt32,
        identifier: UInt32,
        expectedSignature: UInt32
    ) -> Bool {
        signature == expectedSignature && identifier == activeIdentifier
    }

    public mutating func shutdown(
        handlerRemainsInstalled: Bool = false,
        retainingOrphanedIdentifiers: [UInt32] = []
    ) {
        handlerInstalled = handlerRemainsInstalled
        activeDescriptor = nil
        activeIdentifier = nil
        orphanedIdentifiers = retainingOrphanedIdentifiers
    }
}
