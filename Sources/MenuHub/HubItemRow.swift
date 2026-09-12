import AppKit
import SwiftUI

enum HubItemInteractionState: Equatable {
    case idle, invoking, succeeded, failed, unavailable
}

struct HubItemAccessibilityPresentation: Equatable {
    let label: String
    let value: String
    let help: String

    static func resolve(title: String, capability: String, state: HubItemInteractionState) -> Self {
        let value: String
        let help: String
        switch state {
        case .idle:
            value = capability == L("panel.press") ? L("accessibility.clickable") : capability
            help = capability
        case .invoking: value = L("accessibility.invoking"); help = L("accessibility.invokingHelp")
        case .succeeded: value = L("accessibility.succeeded"); help = L("accessibility.succeededHelp")
        case .failed: value = L("accessibility.failed"); help = L("accessibility.failedHelp")
        case .unavailable: value = L("accessibility.unavailable"); help = L("accessibility.unavailableHelp")
        }
        return Self(label: L("accessibility.itemLabelFormat", title, value), value: value, help: help)
    }
}

struct HubRowAppearance: Equatable {
    enum Layer: Equatable { case idle, hovered, selected, pressed }
    let layer: Layer
    let scale: CGFloat

    static func resolve(selected: Bool, hovered: Bool, pressed: Bool, reduceMotion: Bool) -> Self {
        let layer: Layer = pressed ? .pressed : (selected ? .selected : (hovered ? .hovered : .idle))
        return Self(layer: layer, scale: pressed && !reduceMotion ? 0.995 : 1)
    }
}

struct HubItemActionGroup: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isMember: Bool
}

enum HubItemLayoutStyle: Equatable {
    case row
    case grid
}

enum HubItemActionLabel {
    static func primary(hasFailure: Bool, isLaunchOnly: Bool) -> String {
        if hasFailure { return L("panel.retry") }
        return L(isLaunchOnly ? "panel.openApp" : "panel.defaultAction")
    }
}

struct HubItemRow: View {
    let item: HubPanelItem
    let isSelected: Bool
    let isInvoking: Bool
    let hasFailure: Bool
    let hasSucceeded: Bool
    let isActionMenuRequested: Bool
    let actionMenuDidDismiss: () -> Void
    let canOpenHost: Bool
    let groups: [HubItemActionGroup]
    let action: () -> Void
    let openHost: () -> Void
    let toggleFavorite: () -> Void
    let saveAlias: (String?) -> Void
    let setMembership: (UUID, Bool) -> Void
    let ignore: () -> Void
    let retestCapability: () -> Void
    let openManagement: () -> Void
    let showsCapability: Bool
    let layoutStyle: HubItemLayoutStyle
    @State private var isHovering = false
    @State private var actionMenuState = HubItemActionPanelState()

    init(
        item: HubPanelItem, isSelected: Bool, isInvoking: Bool, hasFailure: Bool, hasSucceeded: Bool,
        isActionMenuRequested: Bool, actionMenuDidDismiss: @escaping () -> Void,
        canOpenHost: Bool, groups: [HubItemActionGroup],
        action: @escaping () -> Void, openHost: @escaping () -> Void, toggleFavorite: @escaping () -> Void,
        saveAlias: @escaping (String?) -> Void, setMembership: @escaping (UUID, Bool) -> Void,
        ignore: @escaping () -> Void, retestCapability: @escaping () -> Void,
        openManagement: @escaping () -> Void, showsCapability: Bool = true,
        layoutStyle: HubItemLayoutStyle = .row
    ) {
        self.item = item; self.isSelected = isSelected; self.isInvoking = isInvoking
        self.hasFailure = hasFailure; self.hasSucceeded = hasSucceeded
        self.isActionMenuRequested = isActionMenuRequested
        self.actionMenuDidDismiss = actionMenuDidDismiss
        self.canOpenHost = canOpenHost; self.groups = groups
        self.action = action; self.openHost = openHost; self.toggleFavorite = toggleFavorite
        self.saveAlias = saveAlias; self.setMembership = setMembership; self.ignore = ignore
        self.retestCapability = retestCapability
        self.openManagement = openManagement
        self.showsCapability = showsCapability
        self.layoutStyle = layoutStyle
    }

    var body: some View {
        Group {
            switch layoutStyle {
            case .row: rowLayout
            case .grid: gridLayout
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu { sharedMenuActions }
        .accessibilityIdentifier("hub.item.\(item.id)")
        .onAppear { actionMenuState.applyExternalRequest(isActionMenuRequested, alias: item.record.alias) }
        .onChange(of: isActionMenuRequested) { _, requested in
            actionMenuState.applyExternalRequest(requested, alias: item.record.alias)
        }
        .onChange(of: actionMenuState.isPresented) { wasPresented, isPresented in
            if wasPresented && !isPresented { actionMenuDidDismiss() }
        }
    }

    private var rowLayout: some View {
        HStack(spacing: 2) {
            Button(action: action) {
                HStack(spacing: 9) {
                    hostIcon.frame(width: HubPanelLayout.iconSize, height: HubPanelLayout.iconSize)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.primaryTitle).font(.body).lineLimit(1)
                        if showsCapability { HStack(spacing: 4) {
                            if hasFailure { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red) }
                            else if hasSucceeded { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            Text(hasFailure ? L("panel.actionFailed") : (hasSucceeded ? L("panel.completed") : item.secondaryTitle))
                        }
                        .font(.caption).foregroundStyle(hasFailure ? Color.red : Color.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: HubPanelLayout.rowHeight, maxHeight: HubPanelLayout.rowHeight)
            }
            .buttonStyle(HubRowButtonStyle(selected: isSelected, hovered: isHovering))
            .disabled(!item.canInvoke || isInvoking)
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(accessibility.value)
            .accessibilityHint(accessibility.help)

            actionMenuButton
        }
        .padding(.trailing, HubPanelLayout.rowActionTrailingPadding)
    }

    private var gridLayout: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                VStack(spacing: 5) {
                    hostIcon.frame(width: 30, height: 30)
                    Text(item.primaryTitle)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if showsCapability {
                        Text(hasFailure ? L("panel.actionFailed") : (hasSucceeded ? L("panel.completed") : item.secondaryTitle))
                            .font(.caption2)
                            .foregroundStyle(hasFailure ? Color.red : Color.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 76)
                .contentShape(Rectangle())
            }
            .buttonStyle(HubGridButtonStyle(selected: isSelected, hovered: isHovering))
            .disabled(!item.canInvoke || isInvoking)
            .accessibilityLabel(accessibility.label)
            .accessibilityValue(accessibility.value)
            .accessibilityHint(accessibility.help)

            actionMenuButton
                .padding(4)
        }
    }

    private var actionMenuButton: some View {
        Button { actionMenuState.toggle(alias: item.record.alias) } label: {
            Group {
                if isInvoking { ProgressView().controlSize(.small) }
                else if hasFailure { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red) }
                else if hasSucceeded { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else { capabilityIcon }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .opacity(actionButtonIsVisible ? 1 : 0)
        .allowsHitTesting(actionButtonIsVisible)
        .accessibilityLabel(L("accessibility.moreActionsFormat", accessibility.label))
        .accessibilityValue(accessibility.value)
        .accessibilityHint(accessibility.help)
        .help(accessibility.help)
        .popover(isPresented: $actionMenuState.isPresented, arrowEdge: .trailing) {
            HubItemActionPanel(
                item: item,
                canOpenHost: canOpenHost,
                groups: groups,
                isInvoking: isInvoking,
                hasFailure: hasFailure,
                primaryAction: action,
                openHost: openHost,
                toggleFavorite: toggleFavorite,
                saveAlias: saveAlias,
                setMembership: setMembership,
                ignore: ignore,
                retestCapability: retestCapability,
                openManagement: openManagement,
                dismiss: { actionMenuState.dismiss() },
                state: $actionMenuState
            )
        }
    }

    @ViewBuilder private var sharedMenuActions: some View {
        Button(HubItemActionLabel.primary(hasFailure: hasFailure, isLaunchOnly: item.isLaunchOnly), action: action)
            .disabled(!item.canInvoke || isInvoking)
        if canOpenHost { Button(L("panel.openHost"), action: openHost).disabled(isInvoking) }
        Button(L(item.record.isFavorite ? "panel.unfavorite" : "panel.favorite"), action: toggleFavorite)
        Button(L("panel.editAlias")) {
            actionMenuState.present(alias: item.record.alias)
            actionMenuState.showRename()
        }
        if !groups.isEmpty {
            Menu(L("panel.addToGroup")) {
                ForEach(groups) { group in
                    Button { setMembership(group.id, !group.isMember) } label: {
                        Label(group.name, systemImage: group.isMember ? "checkmark" : "circle")
                    }
                }
            }
        }
        Button(L("panel.ignoreItem"), role: .destructive, action: ignore)
        Button(L("panel.retest"), action: retestCapability)
        Button(L("panel.showInManagement"), action: openManagement)
    }

    private var interactionState: HubItemInteractionState {
        if isInvoking { return .invoking }
        if hasFailure { return .failed }
        if hasSucceeded { return .succeeded }
        return item.canInvoke ? .idle : .unavailable
    }

    private var accessibility: HubItemAccessibilityPresentation {
        .resolve(title: item.primaryTitle, capability: item.secondaryTitle, state: interactionState)
    }

    private var actionButtonIsVisible: Bool {
        isHovering || isSelected || isInvoking || hasFailure || hasSucceeded || actionMenuState.isPresented
    }

    @ViewBuilder private var hostIcon: some View {
        if let icon = item.hostIcon { Image(nsImage: icon).resizable().scaledToFit() }
        else { Image(systemName: "app.dashed").resizable().scaledToFit().padding(2).foregroundStyle(.secondary) }
    }

    private var capabilityIcon: some View {
        Image(systemName: item.canInvoke ? "ellipsis" : "exclamationmark.circle")
            .foregroundStyle(.secondary)
    }
}

private struct HubRowButtonStyle: ButtonStyle {
    let selected: Bool
    let hovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let appearance = HubRowAppearance.resolve(
            selected: selected, hovered: hovered, pressed: configuration.isPressed, reduceMotion: reduceMotion
        )
        configuration.label
            .padding(.horizontal, 6)
            .background(background(for: appearance.layer), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .scaleEffect(appearance.scale)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func background(for layer: HubRowAppearance.Layer) -> Color {
        switch layer {
        case .idle: return .clear
        case .hovered: return Color(nsColor: .selectedContentBackgroundColor).opacity(0.10)
        case .selected: return Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
        case .pressed: return Color(nsColor: .selectedContentBackgroundColor).opacity(0.32)
        }
    }
}

private struct HubGridButtonStyle: ButtonStyle {
    let selected: Bool
    let hovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let appearance = HubRowAppearance.resolve(
            selected: selected,
            hovered: hovered,
            pressed: configuration.isPressed,
            reduceMotion: reduceMotion
        )
        configuration.label
            .padding(4)
            .background(background(for: appearance.layer), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                }
            }
            .scaleEffect(appearance.scale)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func background(for layer: HubRowAppearance.Layer) -> Color {
        switch layer {
        case .idle: return .clear
        case .hovered: return Color(nsColor: .selectedContentBackgroundColor).opacity(0.10)
        case .selected: return Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
        case .pressed: return Color(nsColor: .selectedContentBackgroundColor).opacity(0.32)
        }
    }
}
