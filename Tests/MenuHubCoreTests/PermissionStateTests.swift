import XCTest
@testable import MenuHubCore

final class PermissionStateTests: XCTestCase {
    func testUnknownIsSilentUntilAFeatureIsRequested() {
        XCTAssertEqual(PermissionState.unknown.reduce(.applicationBecameActive(isTrusted: false)), .init(state: .unknown))

        XCTAssertEqual(
            PermissionState.unknown.reduce(.featureRequested),
            .init(state: .explanation(.systemPrompt), effects: [.showExplanation])
        )
    }

    func testAcceptingInitialExplanationIsTheOnlyPathToSystemPrompt() {
        XCTAssertEqual(
            PermissionState.explanation(.systemPrompt).reduce(.explanationAccepted),
            .init(state: .awaitingSystemChange, effects: [.requestSystemPrompt])
        )
    }

    func testSkippingExplanationEntersLauncherMode() {
        XCTAssertEqual(
            PermissionState.explanation(.systemPrompt).reduce(.explanationSkipped),
            .init(state: .denied, effects: [.setDenied, .enterLauncherMode])
        )
    }

    func testDeniedUserGetsExplanationBeforeOpeningSettings() {
        let explanation = PermissionState.denied.reduce(.featureRequested)
        XCTAssertEqual(explanation, .init(state: .explanation(.settings), effects: [.showExplanation]))
        XCTAssertEqual(
            explanation.state.reduce(.explanationAccepted),
            .init(state: .awaitingSystemChange, effects: [.openSettings])
        )
    }

    func testOpenedSettingsCannotBypassAcceptedExplanation() {
        let states: [PermissionState] = [
            .unknown,
            .denied,
            .explanation(.settings),
            .explanation(.systemPrompt),
        ]

        for state in states {
            XCTAssertEqual(
                state.reduce(.openedSettings),
                .init(state: state),
                "openedSettings must be inert in \(state)"
            )
        }
    }

    func testOpenedSettingsIsAnInertConfirmationWhileAwaiting() {
        XCTAssertEqual(
            PermissionState.awaitingSystemChange.reduce(.openedSettings),
            .init(state: .awaitingSystemChange)
        )
    }

    func testAwaitingTrustChangeAuthorizesAndScansExactlyOnce() {
        let authorized = PermissionState.awaitingSystemChange.reduce(.applicationBecameActive(isTrusted: true))
        XCTAssertEqual(authorized, .init(state: .authorized, effects: [.setAuthorized, .scan]))
        XCTAssertEqual(authorized.state.reduce(.applicationBecameActive(isTrusted: true)), .init(state: .authorized))
    }

    func testTrustedTrueTakesPriorityAndOnlyScansOnStateChange() {
        XCTAssertEqual(
            PermissionState.explanation(.systemPrompt).reduce(.applicationBecameActive(isTrusted: true)),
            .init(state: .authorized, effects: [.setAuthorized, .scan])
        )
        XCTAssertEqual(PermissionState.authorized.reduce(.applicationBecameActive(isTrusted: true)), .init(state: .authorized))
    }

    func testAwaitingDeniedResultEntersLauncherMode() {
        XCTAssertEqual(
            PermissionState.awaitingSystemChange.reduce(.applicationBecameActive(isTrusted: false)),
            .init(state: .denied, effects: [.setDenied, .enterLauncherMode])
        )
    }

    func testAuthorizedOperationDenialOffersRepairWithoutResetting() {
        XCTAssertEqual(
            PermissionState.authorized.reduce(.operationDenied),
            .init(
                state: .repairRequired(reason: .operationDenied),
                effects: [.setDenied, .enterLauncherMode, .offerRepair]
            )
        )
    }

    func testRevokedAuthorizationOffersRepairWithoutResetting() {
        XCTAssertEqual(
            PermissionState.authorized.reduce(.applicationBecameActive(isTrusted: false)),
            .init(
                state: .repairRequired(reason: .trustRevoked),
                effects: [.setDenied, .enterLauncherMode, .offerRepair]
            )
        )
    }

    func testRepairResetRequiresExplicitConfirmation() {
        let state = PermissionState.repairRequired(reason: .operationDenied)
        XCTAssertEqual(state.reduce(.featureRequested), .init(state: state))
        XCTAssertEqual(
            state.reduce(.repairConfirmed),
            .init(state: .resetting, effects: [.resetRequested])
        )
    }

    func testResetCompletionOpensSettingsAndWaitsForTrustChange() {
        XCTAssertEqual(
            PermissionState.resetting.reduce(.resetCompleted),
            .init(state: .awaitingSystemChange, effects: [.openSettings])
        )
    }

    func testAllLegalTransitionsHaveDeterministicResults() {
        let cases: [(PermissionState, PermissionEvent, PermissionTransition)] = [
            (.unknown, .featureRequested, .init(state: .explanation(.systemPrompt), effects: [.showExplanation])),
            (.explanation(.systemPrompt), .explanationAccepted, .init(state: .awaitingSystemChange, effects: [.requestSystemPrompt])),
            (.explanation(.settings), .explanationAccepted, .init(state: .awaitingSystemChange, effects: [.openSettings])),
            (.explanation(.systemPrompt), .explanationSkipped, .init(state: .denied, effects: [.setDenied, .enterLauncherMode])),
            (.explanation(.settings), .explanationSkipped, .init(state: .denied, effects: [.setDenied, .enterLauncherMode])),
            (.awaitingSystemChange, .applicationBecameActive(isTrusted: false), .init(state: .denied, effects: [.setDenied, .enterLauncherMode])),
            (.denied, .featureRequested, .init(state: .explanation(.settings), effects: [.showExplanation])),
            (.authorized, .applicationBecameActive(isTrusted: false), .init(state: .repairRequired(reason: .trustRevoked), effects: [.setDenied, .enterLauncherMode, .offerRepair])),
            (.authorized, .operationDenied, .init(state: .repairRequired(reason: .operationDenied), effects: [.setDenied, .enterLauncherMode, .offerRepair])),
            (.repairRequired(reason: .operationDenied), .repairConfirmed, .init(state: .resetting, effects: [.resetRequested])),
            (.repairRequired(reason: .trustRevoked), .repairConfirmed, .init(state: .resetting, effects: [.resetRequested])),
            (.resetting, .resetCompleted, .init(state: .awaitingSystemChange, effects: [.openSettings])),
        ]

        for (state, event, expected) in cases {
            XCTAssertEqual(state.reduce(event), expected, "unexpected result for \(state) + \(event)")
        }
    }

    func testTrustedTrueAuthorizesEveryNonAuthorizedStateExactlyOnce() {
        let states: [PermissionState] = [
            .unknown,
            .explanation(.systemPrompt),
            .explanation(.settings),
            .awaitingSystemChange,
            .denied,
            .repairRequired(reason: .operationDenied),
            .repairRequired(reason: .trustRevoked),
        ]

        for state in states {
            XCTAssertEqual(
                state.reduce(.applicationBecameActive(isTrusted: true)),
                .init(state: .authorized, effects: [.setAuthorized, .scan]),
                "trusted=true must take priority in \(state)"
            )
        }
        XCTAssertEqual(
            PermissionState.authorized.reduce(.applicationBecameActive(isTrusted: true)),
            .init(state: .authorized)
        )
    }

    func testResettingIgnoresTrustRaceUntilResetCompletes() {
        let prematureTrust = PermissionState.resetting.reduce(.applicationBecameActive(isTrusted: true))
        XCTAssertEqual(prematureTrust, .init(state: .resetting))
        XCTAssertEqual(
            prematureTrust.state.reduce(.applicationBecameActive(isTrusted: false)),
            .init(state: .resetting)
        )

        let resetCompleted = prematureTrust.state.reduce(.resetCompleted)
        XCTAssertEqual(
            resetCompleted,
            .init(state: .awaitingSystemChange, effects: [.openSettings])
        )

        XCTAssertEqual(
            resetCompleted.state.reduce(.applicationBecameActive(isTrusted: true)),
            .init(state: .authorized, effects: [.setAuthorized, .scan])
        )
    }

    func testEveryStateIgnoresARepresentativeIllegalEvent() {
        let cases: [(PermissionState, PermissionEvent)] = [
            (.unknown, .repairConfirmed),
            (.explanation(.systemPrompt), .resetCompleted),
            (.explanation(.settings), .operationDenied),
            (.awaitingSystemChange, .featureRequested),
            (.authorized, .explanationAccepted),
            (.denied, .repairConfirmed),
            (.repairRequired(reason: .operationDenied), .explanationAccepted),
            (.repairRequired(reason: .trustRevoked), .explanationSkipped),
            (.resetting, .repairConfirmed),
        ]

        for (state, event) in cases {
            XCTAssertEqual(state.reduce(event), .init(state: state), "\(state) must ignore \(event)")
        }
    }
}
