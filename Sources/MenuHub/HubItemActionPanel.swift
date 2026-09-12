import SwiftUI

struct HubItemActionPanel: View {
    let item: HubPanelItem
    let canOpenHost: Bool
    let groups: [HubItemActionGroup]
    let isInvoking: Bool
    let hasFailure: Bool
    let primaryAction: () -> Void
    let openHost: () -> Void
    let toggleFavorite: () -> Void
    let saveAlias: (String?) -> Void
    let setMembership: (UUID, Bool) -> Void
    let ignore: () -> Void
    let retestCapability: () -> Void
    let openManagement: () -> Void
    let dismiss: () -> Void
    @Binding var state: HubItemActionPanelState

    @FocusState private var focusedCommand: HubItemActionPanelCommand?
    @FocusState private var aliasFieldIsFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var configuration: HubItemActionPanelConfiguration {
        .init(canOpenHost: canOpenHost, hasGroups: !groups.isEmpty, isInvoking: isInvoking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch state.page {
            case .commands:
                commandsPage
            case .rename:
                renamePage
            case .groups:
                groupsPage
            }
        }
        .padding(14)
        .frame(width: 354)
        .hubActionPanelSurface()
        .padding(6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.item.actions.panel")
    }

    private var header: some View {
        HStack(spacing: 11) {
            hostIcon
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .lineLimit(2)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if state.page == .commands {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusLabel)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private var commandsPage: some View {
        VStack(alignment: .leading, spacing: 13) {
            commandButton(
                .primary,
                title: HubItemActionLabel.primary(hasFailure: hasFailure, isLaunchOnly: item.isLaunchOnly),
                symbol: hasFailure ? "arrow.clockwise" : "arrow.up.forward",
                keyHint: "↩",
                role: .primary,
                disabled: !item.canInvoke || isInvoking
            ) {
                leavePanel(then: primaryAction)
            }

            actionSection(title: L("actionPanel.quickActions")) {
                if canOpenHost {
                    commandButton(
                        .openHost,
                        title: L("panel.openHost"),
                        symbol: "macwindow",
                        keyHint: "⌘↩",
                        disabled: isInvoking
                    ) {
                        leavePanel(then: openHost)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }

                commandButton(
                    .favorite,
                    title: L(item.record.isFavorite ? "panel.unfavorite" : "panel.favorite"),
                    symbol: item.record.isFavorite ? "star.slash" : "star"
                ) {
                    leavePanel(then: toggleFavorite)
                }
            }

            actionSection(title: L("actionPanel.customize")) {
                commandButton(
                    .rename,
                    title: L("actionPanel.rename"),
                    symbol: "pencil",
                    trailing: item.record.alias ?? item.record.hostName,
                    showsChevron: true
                ) {
                    state.showRename()
                }

                if !groups.isEmpty {
                    commandButton(
                        .groups,
                        title: L("actionPanel.groups"),
                        symbol: "folder",
                        trailing: groupSummary,
                        showsChevron: true
                    ) {
                        state.showGroups()
                    }
                }

                commandButton(
                    .more,
                    title: L("actionPanel.moreActions"),
                    symbol: "ellipsis.circle",
                    trailingSymbol: state.showsMoreActions ? "chevron.up" : "chevron.down"
                ) {
                    withOptionalAnimation { state.toggleMoreActions() }
                }
            }

            if state.showsMoreActions {
                actionSection {
                    commandButton(.retest, title: L("panel.retest"), symbol: "arrow.triangle.2.circlepath") {
                        leavePanel(then: retestCapability)
                    }
                    commandButton(.management, title: L("panel.showInManagement"), symbol: "slider.horizontal.3") {
                        leavePanel(then: openManagement)
                    }
                    commandButton(
                        .ignore,
                        title: L("panel.ignoreItem"),
                        symbol: "eye.slash",
                        role: .destructive
                    ) {
                        leavePanel(then: ignore)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            keyboardFooter(L("actionPanel.keyboardDefault"))
        }
        .onAppear { focusInitialCommand() }
        .onKeyPress(.upArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
    }

    private var renamePage: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L("actionPanel.displayName"))
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(L("actionPanel.optional"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                TextField(L("panel.aliasPlaceholder"), text: $state.aliasDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($aliasFieldIsFocused)
                    .onSubmit(commitAlias)
                    .accessibilityIdentifier("hub.item.actions.aliasField")

                HStack(spacing: 8) {
                    Button(L("common.clear"), action: clearAlias)
                        .buttonStyle(.bordered)
                    Spacer()
                    Button(L("common.cancel"), action: cancelRename)
                        .buttonStyle(.bordered)
                    Button(L("common.save"), action: commitAlias)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                }
                .controlSize(.regular)
            }
            .padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            keyboardFooter(L("actionPanel.keyboardRename"))
        }
        .onAppear {
            state.aliasDraft = item.record.alias ?? ""
            Task { @MainActor in
                await Task.yield()
                aliasFieldIsFocused = true
            }
        }
        .onKeyPress(.escape) {
            cancelRename()
            return .handled
        }
    }

    private var groupsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                state.showCommands()
            } label: {
                Label(L("common.back"), systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("hub.item.actions.groups.back")

            VStack(spacing: 5) {
                ForEach(groups) { group in
                    Button {
                        setMembership(group.id, !group.isMember)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: group.isMember ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(group.isMember ? Color.accentColor : Color.secondary)
                            Text(group.name)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                        }
                    }
                    .buttonStyle(HubActionPanelButtonStyle(role: .standard, isFocused: false))
                }
            }

            keyboardFooter(L("actionPanel.keyboardGroups"))
        }
        .onKeyPress(.escape) {
            state.showCommands()
            return .handled
        }
    }

    @ViewBuilder
    private func actionSection<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
            }
            VStack(spacing: 5, content: content)
        }
    }

    private func commandButton(
        _ command: HubItemActionPanelCommand,
        title: String,
        symbol: String,
        keyHint: String? = nil,
        trailing: String? = nil,
        trailingSymbol: String? = nil,
        showsChevron: Bool = false,
        role: HubActionPanelButtonRole = .standard,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(role == .destructive ? Color.red : Color.secondary)
                Text(title)
                    .font(.callout.weight(role == .primary ? .semibold : .regular))
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let keyHint {
                    Text(keyHint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(role == .primary ? Color.white.opacity(0.82) : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(role == .primary ? 0.14 : 0.07), in: Capsule())
                }
                if let trailingSymbol {
                    Image(systemName: trailingSymbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HubActionPanelButtonStyle(role: role, isFocused: focusedCommand == command))
        .focused($focusedCommand, equals: command)
        .disabled(disabled)
        .accessibilityIdentifier("hub.item.actions.\(command.accessibilityComponent)")
    }

    private func keyboardFooter(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }

    private var headerTitle: String {
        switch state.page {
        case .commands: item.primaryTitle
        case .rename: L("actionPanel.rename")
        case .groups: L("actionPanel.groups")
        }
    }

    private var headerSubtitle: String {
        switch state.page {
        case .commands: L("actionPanel.menuBarItem")
        case .rename, .groups: item.primaryTitle
        }
    }

    private var statusLabel: String {
        if hasFailure { return L("panel.actionFailed") }
        if !item.canInvoke { return L("panel.currentlyUnavailable") }
        return isInvoking ? L("accessibility.invoking") : L("actionPanel.ready")
    }

    private var statusColor: Color {
        if hasFailure || !item.canInvoke { return .red }
        return isInvoking ? .orange : .green
    }

    private var groupSummary: String {
        let memberCount = groups.lazy.filter(\.isMember).count
        return memberCount == 0 ? L("common.none") : String(memberCount)
    }

    @ViewBuilder
    private var hostIcon: some View {
        if let icon = item.hostIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .padding(7)
                .foregroundStyle(.secondary)
                .background(Color.primary.opacity(0.06))
        }
    }

    private func leavePanel(then action: () -> Void) {
        dismiss()
        action()
    }

    private func commitAlias() {
        let trimmed = state.aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAlias(trimmed.isEmpty ? nil : trimmed)
        state.showCommands()
        focusInitialCommand()
    }

    private func clearAlias() {
        state.aliasDraft = ""
        saveAlias(nil)
        state.showCommands()
        focusInitialCommand()
    }

    private func cancelRename() {
        state.aliasDraft = item.record.alias ?? ""
        state.showCommands()
        focusInitialCommand()
    }

    private func handleEscape() {
        if state.handleEscape() == .dismiss {
            dismiss()
        } else {
            focusInitialCommand()
        }
    }

    private func focusInitialCommand() {
        Task { @MainActor in
            await Task.yield()
            focusedCommand = .primary
        }
    }

    private func moveFocus(by offset: Int) {
        let commands = configuration.visibleCommands(showsMore: state.showsMoreActions)
        guard !commands.isEmpty else { return }
        let currentIndex = focusedCommand.flatMap(commands.firstIndex(of:)) ?? 0
        let destination = min(max(currentIndex + offset, 0), commands.count - 1)
        focusedCommand = commands[destination]
    }

    private func withOptionalAnimation(_ changes: () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.easeInOut(duration: 0.16), changes)
        }
    }
}

private extension HubItemActionPanelCommand {
    var accessibilityComponent: String {
        switch self {
        case .primary: "primary"
        case .openHost: "openHost"
        case .favorite: "favorite"
        case .rename: "rename"
        case .groups: "groups"
        case .more: "more"
        case .retest: "retest"
        case .management: "management"
        case .ignore: "ignore"
        }
    }
}
