import XCTest
@testable import MenuHubCore

final class HotKeyDescriptorTests: XCTestCase {
    func testDefaultIsOptionM() {
        XCTAssertEqual(HotKeyDescriptor.default.keyCode, 46)
        XCTAssertEqual(HotKeyDescriptor.default.modifiers, [.option])
        XCTAssertEqual(HotKeyDescriptor.default.displayString, "⌥M")
        XCTAssertTrue(HotKeyDescriptor.default.isValid)
    }

    func testBareLetterIsInvalid() {
        XCTAssertFalse(HotKeyDescriptor(keyCode: 0, modifiers: []).isValid)
    }

    func testMissingKeyIsInvalid() {
        XCTAssertFalse(HotKeyDescriptor(keyCode: nil, modifiers: [.command]).isValid)
    }

    func testModifierKeyAloneIsInvalid() {
        for keyCode: UInt32 in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] {
            XCTAssertFalse(
                HotKeyDescriptor(keyCode: keyCode, modifiers: [.command]).isValid,
                "Expected modifier key code \(keyCode) to be invalid"
            )
        }
    }

    func testModifierSymbolsHaveStableDisplayOrder() {
        let descriptor = HotKeyDescriptor(
            keyCode: 0,
            modifiers: [.command, .shift, .option, .control]
        )

        XCTAssertEqual(descriptor.displayString, "⌃⌥⇧⌘A")
    }

    func testEachModifierHasExpectedSymbol() {
        XCTAssertEqual(HotKeyDescriptor(keyCode: 0, modifiers: [.control]).displayString, "⌃A")
        XCTAssertEqual(HotKeyDescriptor(keyCode: 0, modifiers: [.option]).displayString, "⌥A")
        XCTAssertEqual(HotKeyDescriptor(keyCode: 0, modifiers: [.shift]).displayString, "⇧A")
        XCTAssertEqual(HotKeyDescriptor(keyCode: 0, modifiers: [.command]).displayString, "⌘A")
    }

    func testCodableRoundTrip() throws {
        let descriptor = HotKeyDescriptor(keyCode: 18, modifiers: [.control, .shift])

        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(HotKeyDescriptor.self, from: data)

        XCTAssertEqual(decoded, descriptor)
    }

    func testKeyLabelsCoverANSILettersDigitsSpaceAndFallback() {
        XCTAssertEqual(HotKeyDescriptor.keyLabel(for: 0), "A")
        XCTAssertEqual(HotKeyDescriptor.keyLabel(for: 46), "M")
        XCTAssertEqual(HotKeyDescriptor.keyLabel(for: 18), "1")
        XCTAssertEqual(HotKeyDescriptor.keyLabel(for: 29), "0")
        XCTAssertEqual(HotKeyDescriptor.keyLabel(for: 49), "Space")
        XCTAssertEqual(HotKeyDescriptor.keyLabel(for: 999), "Key 999")
        XCTAssertEqual(HotKeyDescriptor.keyLabel(for: nil), "—")
    }

    func testBridgesCatalogHotKeyPreference() {
        let preference = HotKeyPreference(keyCode: 12, modifiers: [.command, .shift])
        let descriptor = HotKeyDescriptor(preference)

        XCTAssertEqual(descriptor.keyCode, preference.keyCode)
        XCTAssertEqual(descriptor.modifiers, preference.modifiers)
        XCTAssertEqual(descriptor.preference, preference)
    }

    func testHandlerInstallFailureAllowsRetry() {
        var state = HotKeyRegistrationState()

        state.recordHandlerInstallation(succeeded: false)

        XCTAssertTrue(state.needsHandlerInstallation)
    }

    func testShutdownAllowsHandlerReinstallation() {
        var state = HotKeyRegistrationState()
        state.recordHandlerInstallation(succeeded: true)

        state.shutdown()

        XCTAssertTrue(state.needsHandlerInstallation)
    }

    func testIncompleteShutdownRetainsResourcesThatNeedCleanup() {
        var state = HotKeyRegistrationState()

        state.shutdown(handlerRemainsInstalled: true, retainingOrphanedIdentifiers: [3])

        XCTAssertFalse(state.needsHandlerInstallation)
        XCTAssertEqual(state.orphanedIdentifiers, [3])
        XCTAssertFalse(state.canAttemptRegistration)
    }

    func testForeignEventIsNotHandled() {
        var state = HotKeyRegistrationState()
        state.recordRegistration(
            descriptor: .default,
            identifier: 7,
            outcome: .registered
        )

        XCTAssertFalse(state.matchesEvent(signature: 0x4F544852, identifier: 7, expectedSignature: 0x4D485542))
        XCTAssertFalse(state.matchesEvent(signature: 0x4D485542, identifier: 8, expectedSignature: 0x4D485542))
        XCTAssertTrue(state.matchesEvent(signature: 0x4D485542, identifier: 7, expectedSignature: 0x4D485542))
    }

    func testConflictRetainsOldRegistration() {
        let old = HotKeyDescriptor(keyCode: 0, modifiers: [.command])
        var state = HotKeyRegistrationState()
        state.recordRegistration(descriptor: old, identifier: 1, outcome: .registered)

        state.recordRegistration(descriptor: .default, identifier: 2, outcome: .conflict)

        XCTAssertEqual(state.activeDescriptor, old)
        XCTAssertEqual(state.activeIdentifier, 1)
        XCTAssertTrue(state.orphanedIdentifiers.isEmpty)
    }

    func testOldUnregisterFailureAndCandidateRollbackRetainsOldRegistration() {
        let old = HotKeyDescriptor(keyCode: 0, modifiers: [.command])
        var state = HotKeyRegistrationState()
        state.recordRegistration(descriptor: old, identifier: 1, outcome: .registered)

        state.recordRegistration(
            descriptor: .default,
            identifier: 2,
            outcome: .oldUnregisterFailed(candidateRolledBack: true)
        )

        XCTAssertEqual(state.activeDescriptor, old)
        XCTAssertEqual(state.activeIdentifier, 1)
        XCTAssertTrue(state.orphanedIdentifiers.isEmpty)
    }

    func testDoubleUnregisterFailureRecordsOrphanThatMustBeCleanedFirst() {
        let old = HotKeyDescriptor(keyCode: 0, modifiers: [.command])
        var state = HotKeyRegistrationState()
        state.recordRegistration(descriptor: old, identifier: 1, outcome: .registered)

        state.recordRegistration(
            descriptor: .default,
            identifier: 2,
            outcome: .oldUnregisterFailed(candidateRolledBack: false)
        )

        XCTAssertEqual(state.activeDescriptor, old)
        XCTAssertEqual(state.orphanedIdentifiers, [2])
        XCTAssertFalse(state.canAttemptRegistration)

        state.recordOrphanCleanup(identifier: 2, succeeded: true)

        XCTAssertTrue(state.canAttemptRegistration)
    }

    func testFailedOrphanCleanupContinuesToBlockRegistration() {
        var state = HotKeyRegistrationState()
        state.recordRegistration(
            descriptor: .default,
            identifier: 2,
            outcome: .oldUnregisterFailed(candidateRolledBack: false)
        )

        state.recordOrphanCleanup(identifier: 2, succeeded: false)

        XCTAssertEqual(state.orphanedIdentifiers, [2])
        XCTAssertFalse(state.canAttemptRegistration)
    }
}
