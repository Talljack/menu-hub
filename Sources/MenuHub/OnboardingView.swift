import MenuHubCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: HubPanelModel
    let hotKeyAvailable: Bool
    let onShowSetupMarker: () -> Void
    let onTestHide: () -> Void
    let onRestore: () -> Void
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Label(title, systemImage: symbol)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
                Spacer(minLength: 0)
            }
            .padding(28)

            Divider()
            HStack {
                if OnboardingPolicy.previous(before: step) != nil {
                    Button(L("common.back")) { goBack() }
                }
                Spacer()
                if step == .permission && !model.permissionGranted {
                    Button(L("onboarding.skip")) { step = OnboardingPolicy.next(after: step, choice: .skip) }
                        .accessibilityIdentifier("onboarding.skip")
                }
                Button(primaryButtonTitle) { performPrimaryAction() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.primary")
            }
            .padding(18)
        }
        .frame(width: 520, height: 390)
        .accessibilityIdentifier("onboarding.root")
        .onReceive(model.$permissionState) { state in
            guard state == .authorized else { return }
            step = OnboardingPolicy.authorizedVersion(of: step)
            if step == .permission {
                step = OnboardingPolicy.next(after: step, choice: .authorized)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            Label(L("onboarding.openHint"), systemImage: "menubar.rectangle")
        case .capabilityBoundary:
            VStack(alignment: .leading, spacing: 10) {
                capability(L("capability.actionable"), detail: L("capability.actionableDetail"), symbol: "cursorarrow.click")
                capability(L("capability.openApp"), detail: L("capability.openAppDetail"), symbol: "arrow.up.forward.app")
                capability(L("capability.unavailable"), detail: L("capability.unavailableDetail"), symbol: "exclamationmark.triangle")
            }
        case .permission:
            VStack(alignment: .leading, spacing: 12) {
                Label(permissionStatusText, systemImage: model.permissionGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .foregroundStyle(model.permissionGranted ? Color.green : Color.accentColor)
                Text(L("onboarding.permissionPrivacy"))
                    .font(.callout)
                Text(L("onboarding.permissionScope"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.permissionState == .awaitingSystemChange || model.permissionState == .denied {
                    Button(L("onboarding.openSystemSettings")) { model.openAccessibilitySettings() }
                }
            }
        case .statusItemPlacement:
            VStack(alignment: .leading, spacing: 12) {
                Label(L("onboarding.dragHint"), systemImage: "command")
                Text(L("onboarding.placementBody"))
                    .font(.callout)
                Button(L("onboarding.showMarker")) { onShowSetupMarker() }
                HStack {
                    Button(L("onboarding.testHide")) { onTestHide() }
                    Button(L("onboarding.restoreNow")) { onRestore() }
                }
            }
        case let .scanSummary(mode):
            VStack(alignment: .leading, spacing: 12) {
                Label(scanSummary(mode: mode), systemImage: mode == .full ? "checkmark.circle.fill" : "rectangle.stack.badge.person.crop")
                if mode == .launcher {
                    Text(L("onboarding.launcherHint"))
                        .font(.callout)
                }
            }
        case let .shortcutConfirmation(mode):
            VStack(alignment: .leading, spacing: 12) {
                Label(L(hotKeyAvailable ? "onboarding.hotKeyEnabled" : "onboarding.hotKeyUnavailable"), systemImage: hotKeyAvailable ? "keyboard.badge.ellipsis" : "exclamationmark.triangle")
                Text(L(mode == .full ? "onboarding.fullComplete" : "onboarding.launcherComplete"))
                    .font(.callout)
            }
        }
    }

    private var title: String {
        switch step {
        case .welcome: return L("onboarding.welcomeTitle")
        case .capabilityBoundary: return L("onboarding.capabilitiesTitle")
        case .permission: return L("onboarding.permissionTitle")
        case .statusItemPlacement: return L("onboarding.placementTitle")
        case .scanSummary: return L("onboarding.scanTitle")
        case .shortcutConfirmation: return L("onboarding.shortcutTitle")
        }
    }

    private var symbol: String {
        switch step {
        case .welcome: return "square.grid.2x2.fill"
        case .capabilityBoundary: return "checklist"
        case .permission: return "hand.raised.fill"
        case .statusItemPlacement: return "menubar.rectangle"
        case .scanSummary: return "magnifyingglass"
        case .shortcutConfirmation: return "keyboard"
        }
    }

    private var message: String {
        switch step {
        case .welcome: return L("onboarding.welcomeMessage")
        case .capabilityBoundary: return L("onboarding.capabilitiesMessage")
        case .permission: return L("onboarding.permissionMessage")
        case .statusItemPlacement: return L("onboarding.placementMessage")
        case .scanSummary: return L("onboarding.scanMessage")
        case .shortcutConfirmation: return L("onboarding.shortcutMessage")
        }
    }

    private var permissionStatusText: String {
        switch model.permissionState {
        case .authorized: return L("onboarding.authorized")
        case .awaitingSystemChange: return L("onboarding.awaiting")
        case .repairRequired: return L("onboarding.repairRequired")
        default: return L("onboarding.notAuthorized")
        }
    }

    private var primaryButtonTitle: String {
        if OnboardingPolicy.canFinish(step) { return L("common.done") }
        if step == .permission {
            switch model.permissionState {
            case .unknown, .denied: return L("onboarding.understand")
            case .explanation: return L("onboarding.showPrompt")
            case .authorized: return L("common.continue")
            default: return L("common.continue")
            }
        }
        return L("common.continue")
    }

    private func performPrimaryAction() {
        if OnboardingPolicy.canFinish(step) {
            onComplete()
            return
        }
        guard step == .permission else {
            step = OnboardingPolicy.next(after: step, choice: .continue)
            return
        }
        switch model.permissionState {
        case .authorized:
            model.refresh()
            step = OnboardingPolicy.next(after: step, choice: .authorized)
        case .unknown, .denied:
            model.requestPermission()
        case .explanation:
            model.acceptPermissionExplanation()
        case .awaitingSystemChange, .repairRequired, .resetting:
            model.openAccessibilitySettings()
        }
    }

    private func goBack() {
        if let previous = OnboardingPolicy.previous(before: step) { step = previous }
    }

    private func capability(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func scanSummary(mode: OnboardingMode) -> String {
        if model.isScanning { return L("onboarding.scanning") }
        let summary = OnboardingCapabilitySummary(capabilities: model.items.map {
            if $0.canPress { return .actionable }
            if $0.isLaunchOnly { return .launchOnly }
            return .unavailable
        })
        let prefix = L(mode == .launcher ? "onboarding.launcherReady" : "onboarding.scanComplete")
        return L("onboarding.scanSummaryFormat", prefix, summary.totalCount, summary.pressableCount, summary.launchOnlyCount, summary.unavailableCount)
    }
}
