import Carbon.HIToolbox
import Foundation
import MenuHubCore

enum HotKeyRegistrationResult: Equatable {
    case registered
    case conflict
    case systemError(OSStatus)
}

protocol HotKeyCarbonAdapting {
    func installHandler(
        callback: EventHandlerUPP?,
        userData: UnsafeMutableRawPointer
    ) -> (status: OSStatus, reference: EventHandlerRef?)
    func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        identifier: EventHotKeyID
    ) -> (status: OSStatus, reference: EventHotKeyRef?)
    func unregisterHotKey(_ reference: EventHotKeyRef) -> OSStatus
    func removeHandler(_ reference: EventHandlerRef) -> OSStatus
}

struct SystemHotKeyCarbonAdapter: HotKeyCarbonAdapting {
    func installHandler(
        callback: EventHandlerUPP?,
        userData: UnsafeMutableRawPointer
    ) -> (status: OSStatus, reference: EventHandlerRef?) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &reference
        )
        return (status, reference)
    }

    func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        identifier: EventHotKeyID
    ) -> (status: OSStatus, reference: EventHotKeyRef?) {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &reference
        )
        return (status, reference)
    }

    func unregisterHotKey(_ reference: EventHotKeyRef) -> OSStatus {
        UnregisterEventHotKey(reference)
    }

    func removeHandler(_ reference: EventHandlerRef) -> OSStatus {
        RemoveEventHandler(reference)
    }
}

@MainActor
final class HotKeyController {
    private static let signature = OSType(0x4D485542) // MHUB

    private struct HotKeyReference: @unchecked Sendable {
        let identifier: UInt32
        let rawValue: EventHotKeyRef
    }

    private struct HandlerReference: @unchecked Sendable {
        let rawValue: EventHandlerRef
    }

    private var state = HotKeyRegistrationState()
    private var activeHotKey: HotKeyReference?
    private var orphanedHotKeys: [HotKeyReference] = []
    private var eventHandler: HandlerReference?
    private var nextIdentifier: UInt32 = 0
    private var resourcesWereShutdown = true
    private let carbon: any HotKeyCarbonAdapting
    private let action: @MainActor () -> Void

    init(
        carbon: any HotKeyCarbonAdapting = SystemHotKeyCarbonAdapter(),
        action: @escaping @MainActor () -> Void
    ) {
        self.carbon = carbon
        self.action = action
    }

    @discardableResult
    func register(_ candidate: HotKeyDescriptor) -> HotKeyRegistrationResult {
        if let cleanupFailure = cleanupOrphanedHotKeys() {
            return .systemError(cleanupFailure)
        }

        guard candidate.isValid else {
            let status = OSStatus(eventHotKeyInvalidErr)
            recordRegistrationStatus(status)
            return .systemError(status)
        }

        if candidate == state.activeDescriptor, activeHotKey != nil {
            recordRegistrationStatus(noErr)
            return .registered
        }

        if state.needsHandlerInstallation {
            let handlerStatus = installEventHandler()
            guard handlerStatus == noErr else {
                recordRegistrationStatus(handlerStatus)
                return .systemError(handlerStatus)
            }
        }

        let identifier = makeIdentifier()
        let registration = carbon.registerHotKey(
            keyCode: candidate.keyCode!,
            modifiers: carbonModifiers(for: candidate.modifiers),
            identifier: identifier
        )
        let registrationStatus = registration.status == noErr && registration.reference == nil
            ? OSStatus(paramErr)
            : registration.status
        recordRegistrationStatus(registrationStatus)

        if registrationStatus == eventHotKeyExistsErr {
            state.recordRegistration(descriptor: candidate, identifier: identifier.id, outcome: .conflict)
            return .conflict
        }
        guard registrationStatus == noErr, let candidateReference = registration.reference else {
            state.recordRegistration(descriptor: candidate, identifier: identifier.id, outcome: .candidateFailed)
            return .systemError(registrationStatus)
        }

        let candidateHotKey = HotKeyReference(identifier: identifier.id, rawValue: candidateReference)
        if let oldHotKey = activeHotKey {
            let oldUnregisterStatus = carbon.unregisterHotKey(oldHotKey.rawValue)
            recordStatus(oldUnregisterStatus, key: "diagnostics.hotKeyOldUnregistrationStatus")
            guard oldUnregisterStatus == noErr else {
                let rollbackStatus = carbon.unregisterHotKey(candidateHotKey.rawValue)
                recordStatus(rollbackStatus, key: "diagnostics.hotKeyCandidateRollbackStatus")
                let rolledBack = rollbackStatus == noErr
                if !rolledBack {
                    orphanedHotKeys.append(candidateHotKey)
                }
                state.recordRegistration(
                    descriptor: candidate,
                    identifier: identifier.id,
                    outcome: .oldUnregisterFailed(candidateRolledBack: rolledBack)
                )
                recordRegistrationStatus(oldUnregisterStatus)
                return .systemError(oldUnregisterStatus)
            }
        }

        activeHotKey = candidateHotKey
        state.recordRegistration(descriptor: candidate, identifier: identifier.id, outcome: .registered)
        resourcesWereShutdown = false
        return .registered
    }

    /// Compatibility entry point. Despite its historical name, it registers the default ⌥M shortcut.
    @discardableResult
    func registerCommandOptionControlM() -> Bool {
        register(.default) == .registered
    }

    /// Must be called on the main actor before releasing the controller.
    func shutdown() {
        var remainingOrphans: [HotKeyReference] = []

        if let activeHotKey {
            let status = carbon.unregisterHotKey(activeHotKey.rawValue)
            recordStatus(status, key: "diagnostics.hotKeyShutdownUnregistrationStatus")
            if status != noErr {
                remainingOrphans.append(activeHotKey)
            }
            self.activeHotKey = nil
        }

        for hotKey in orphanedHotKeys {
            let status = carbon.unregisterHotKey(hotKey.rawValue)
            recordStatus(status, key: "diagnostics.hotKeyOrphanCleanupStatus")
            if status != noErr {
                remainingOrphans.append(hotKey)
            }
        }
        orphanedHotKeys = remainingOrphans

        if let eventHandler {
            let status = carbon.removeHandler(eventHandler.rawValue)
            recordStatus(status, key: "diagnostics.hotKeyHandlerRemovalStatus")
            if status == noErr {
                self.eventHandler = nil
            }
        }

        state.shutdown(
            handlerRemainsInstalled: eventHandler != nil,
            retainingOrphanedIdentifiers: orphanedHotKeys.map(\.identifier)
        )
        resourcesWereShutdown = orphanedHotKeys.isEmpty && eventHandler == nil
    }

    deinit {
        if !resourcesWereShutdown {
            assertionFailure("HotKeyController.shutdown() must run on MainActor before deinit")
        }
    }

    private func installEventHandler() -> OSStatus {
        let installation = carbon.installHandler(
            callback: Self.eventCallback,
            userData: Unmanaged.passUnretained(self).toOpaque()
        )
        let effectiveStatus = installation.status == noErr && installation.reference == nil
            ? OSStatus(paramErr)
            : installation.status
        let succeeded = effectiveStatus == noErr
        state.recordHandlerInstallation(succeeded: succeeded)
        recordStatus(effectiveStatus, key: "diagnostics.hotKeyHandlerStatus")

        guard succeeded, let reference = installation.reference else {
            return effectiveStatus
        }
        eventHandler = HandlerReference(rawValue: reference)
        resourcesWereShutdown = false
        return noErr
    }

    private func cleanupOrphanedHotKeys() -> OSStatus? {
        while let orphan = orphanedHotKeys.first {
            let status = carbon.unregisterHotKey(orphan.rawValue)
            recordStatus(status, key: "diagnostics.hotKeyOrphanCleanupStatus")
            guard status == noErr else { return status }
            orphanedHotKeys.removeFirst()
            state.recordOrphanCleanup(identifier: orphan.identifier, succeeded: true)
        }
        resourcesWereShutdown = activeHotKey == nil && eventHandler == nil
        return nil
    }

    private func makeIdentifier() -> EventHotKeyID {
        nextIdentifier &+= 1
        if nextIdentifier == 0 {
            nextIdentifier = 1
        }
        return EventHotKeyID(signature: Self.signature, id: nextIdentifier)
    }

    private func carbonModifiers(for modifiers: Set<HotKeyModifier>) -> UInt32 {
        modifiers.reduce(into: UInt32(0)) { result, modifier in
            switch modifier {
            case .command: result |= UInt32(cmdKey)
            case .option: result |= UInt32(optionKey)
            case .control: result |= UInt32(controlKey)
            case .shift: result |= UInt32(shiftKey)
            }
        }
    }

    private func handle(identifierID: UInt32, signature: OSType) -> Bool {
        guard state.matchesEvent(
            signature: signature,
            identifier: identifierID,
            expectedSignature: Self.signature
        ) else { return false }
        action()
        return true
    }

    private func recordRegistrationStatus(_ status: OSStatus) {
        recordStatus(status, key: "diagnostics.hotKeyRegistrationStatus")
    }

    private func recordStatus(_ status: OSStatus, key: String) {
        UserDefaults.standard.set(Int(status), forKey: key)
    }

    private static let eventCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr else { return status }
        let identifierID = identifier.id
        let signature = identifier.signature
        let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
        let handled = MainActor.assumeIsolated {
            controller.handle(identifierID: identifierID, signature: signature)
        }
        return handled ? noErr : OSStatus(eventNotHandledErr)
    }
}
