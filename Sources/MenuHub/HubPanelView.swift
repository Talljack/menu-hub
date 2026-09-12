import AppKit
import MenuHubCore
import SwiftUI

enum HubPanelLayout {
    static let width: CGFloat = 340
    static let minimumHeight: CGFloat = 200
    static let maximumHeight: CGFloat = 500
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 38
    static let iconSize: CGFloat = 22
    static let panelPadding: CGFloat = 8
    static let groupSpacing: CGFloat = 10
    static let scrollContentTrailingGutter: CGFloat = 16
    static let rowActionTrailingPadding: CGFloat = 8
    static let footerHeight: CGFloat = 36
    static let scrollAccessibilityIdentifier = "hub.items.scroll"
}

enum HubPanelBackgroundMode: Equatable {
    case material, solid
    static func resolve(reduceTransparency: Bool) -> Self { reduceTransparency ? .solid : .material }
}

enum HubGridProjection {
    static func items(
        records: [MenuBarItemRecord],
        availableItems: [HubPanelItem]
    ) -> [HubPanelItem] {
        var itemsByID: [String: HubPanelItem] = [:]
        for item in availableItems where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        var emittedIDs = Set<String>()
        return records.compactMap { record in
            guard emittedIDs.insert(record.id).inserted else { return nil }
            return itemsByID[record.id]
        }
    }
}

struct HubPanelView: View {
    @ObservedObject var model: HubPanelModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            contentScroller
            if let message = model.statusMessage,
               !model.items.isEmpty,
               model.statusMessageKey != .permissionDenied {
                Divider()
                statusBar(message)
            }
            Divider()
            footer
        }
        .frame(width: HubPanelLayout.width)
        .frame(minHeight: HubPanelLayout.minimumHeight, maxHeight: HubPanelLayout.maximumHeight)
        .background { panelBackground }
        .background(PanelKeyboardMonitor { event in handleKeyEvent(event) })
        .onAppear {
            searchFocused = true
            model.panelDidAppear()
        }
        .onDisappear { model.panelDidDisappear() }
    }

    @ViewBuilder private var panelBackground: some View {
        switch HubPanelBackgroundMode.resolve(reduceTransparency: reduceTransparency) {
        case .solid: Color(nsColor: .windowBackgroundColor)
        case .material: Rectangle().fill(.regularMaterial)
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(L("panel.searchPlaceholder"), text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel(L("panel.searchPlaceholder"))
                .accessibilityIdentifier("hub.search")
            if !model.query.isEmpty {
                Button { model.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("common.clear"))
            }
        }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        searchFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: searchFocused ? 2 : 0.5
                    )
            }
            .padding(.horizontal, HubPanelLayout.panelPadding)
            .frame(height: HubPanelLayout.headerHeight)
    }

    private var contentScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HubPanelLayout.groupSpacing) {
                    if !model.permissionGranted { permissionBanner }
                    switch model.contentState {
                    case .loading:
                        ProgressView(L("panel.loading")).frame(maxWidth: .infinity, minHeight: 120)
                    case .scanning:
                        ProgressView(L("panel.scanning")).frame(maxWidth: .infinity, minHeight: 120)
                    case .empty:
                        ContentUnavailableView {
                            Label(L("panel.emptyTitle"), systemImage: "menubar.rectangle")
                        } description: {
                            Text(L("panel.emptyDescription"))
                        } actions: {
                            Button(L("panel.rescan")) { model.refresh() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    case .content:
                        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if model.catalogController.document.preferences.layout == .grid {
                                iconGrid
                            } else {
                                defaultGroups
                            }
                        } else {
                            panelGroup(title: L("panel.searchResults"), records: Array(model.snapshot.search.prefix(12)), id: "search")
                        }
                    }
                }
                .padding(.leading, HubPanelLayout.panelPadding)
                .padding(.trailing, HubPanelLayout.scrollContentTrailingGutter)
                .padding(.vertical, HubPanelLayout.groupSpacing)
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier(HubPanelLayout.scrollAccessibilityIdentifier)
            .onChange(of: model.selectionID) { _, id in
                guard let id else { return }
                let anchor = HubPanelPresentationContext.canonicalPresentationID(itemID: id, query: model.query).rawValue
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { proxy.scrollTo(anchor, anchor: .center) }
                else { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(anchor, anchor: .center) } }
            }
        }
    }

    private var iconGrid: some View {
        let gridItems = HubGridProjection.items(
            records: model.snapshot.all,
            availableItems: model.items
        )
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach(gridItems) { item in
                let presentationID = HubItemPresentationID.canonical(itemID: item.id)
                HubItemRow(
                    item: item,
                    isSelected: model.selectionID == item.id,
                    isInvoking: model.operationState == .invoking(itemID: item.id),
                    hasFailure: model.lastFailedItemID == item.id,
                    hasSucceeded: model.lastSucceededItemID == item.id,
                    isActionMenuRequested: model.actionMenuPresentationID == presentationID,
                    actionMenuDidDismiss: {
                        if model.actionMenuPresentationID == presentationID {
                            model.actionMenuPresentationID = nil
                        }
                    },
                    canOpenHost: model.canOpenHost(item),
                    groups: model.snapshot.customGroups.map { group in
                        HubItemActionGroup(
                            id: group.id,
                            name: group.name,
                            isMember: item.record.groupIDs.contains(group.id)
                        )
                    },
                    action: { model.selectionID = item.id; model.invoke(item) },
                    openHost: { model.openHost(item) },
                    toggleFavorite: { model.toggleFavorite(item) },
                    saveAlias: { alias in Task { await model.setAlias(alias, for: item) } },
                    setMembership: { groupID, member in
                        Task { await model.setMembership(member, groupID: groupID, for: item) }
                    },
                    ignore: { Task { await model.setIgnored(true, for: item) } },
                    retestCapability: { model.retestCapability() },
                    openManagement: { model.openManagement(itemID: item.id) },
                    showsCapability: model.catalogController.document.preferences.showCapabilities,
                    layoutStyle: .grid
                )
                .id(presentationID.rawValue)
            }
        }
    }

    @ViewBuilder
    private var defaultGroups: some View {
        panelGroup(title: L("panel.favorites"), records: model.snapshot.favorites, id: "favorites")
        panelGroup(title: L("panel.recent"), records: model.snapshot.recent, id: "recent")
        panelGroup(title: L("panel.frequent"), records: model.snapshot.frequent, id: "frequent")
        ForEach(model.snapshot.customGroups) { group in
            panelGroup(title: group.name, records: group.items, id: "custom-\(group.id.uuidString)")
        }
        panelGroup(title: L("panel.allItems"), records: model.snapshot.all, id: "all")
    }

    @ViewBuilder
    private func panelGroup(title: String, records: [MenuBarItemRecord], id: String) -> some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if model.catalogController.document.preferences.showGroupHeadings {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 3)
                }
                ForEach(records) { record in
                    if let item = model.items.first(where: { $0.id == record.id }) {
                        let presentationID = HubItemPresentationID(sectionID: id, itemID: item.id)
                        HubItemRow(
                            item: item,
                            isSelected: id == HubPanelPresentationContext.canonicalSectionID(query: model.query)
                                && model.selectionID == item.id,
                            isInvoking: model.operationState == .invoking(itemID: item.id),
                            hasFailure: model.lastFailedItemID == item.id,
                            hasSucceeded: model.lastSucceededItemID == item.id,
                            isActionMenuRequested: model.actionMenuPresentationID == presentationID,
                            actionMenuDidDismiss: {
                                if model.actionMenuPresentationID == presentationID {
                                    model.actionMenuPresentationID = nil
                                }
                            },
                            canOpenHost: model.canOpenHost(item),
                            groups: model.snapshot.customGroups.map { group in
                                HubItemActionGroup(
                                    id: group.id, name: group.name,
                                    isMember: item.record.groupIDs.contains(group.id)
                                )
                            },
                            action: { model.selectionID = item.id; model.invoke(item) },
                            openHost: { model.openHost(item) },
                            toggleFavorite: { model.toggleFavorite(item) },
                            saveAlias: { alias in Task { await model.setAlias(alias, for: item) } },
                            setMembership: { groupID, member in
                                Task { await model.setMembership(member, groupID: groupID, for: item) }
                            },
                            ignore: { Task { await model.setIgnored(true, for: item) } },
                            retestCapability: { model.retestCapability() },
                            openManagement: { model.openManagement(itemID: item.id) },
                            showsCapability: model.catalogController.document.preferences.showCapabilities
                        )
                        .id(presentationID.rawValue)
                    }
                }
            }
            .padding(.bottom, 2)
            .id(id)
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("panel.permissionTitle"), systemImage: "hand.raised.fill").font(.headline)
            Text(L("panel.permissionBody"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(permissionButtonTitle) { handlePermissionPrimaryAction() }
                    .buttonStyle(.borderedProminent).disabled(permissionButtonDisabled)
                Button(L("panel.systemSettings")) { model.openAccessibilitySettings() }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("hub.permission.banner")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { model.refresh() } label: {
                HStack(spacing: 5) {
                    if model.isScanning {
                        ProgressView().controlSize(.small)
                        Text(L("panel.scanningShort"))
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text(L("panel.rescan"))
                    }
                }
                .frame(minWidth: 72, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(model.isScanning)
            .help(L("panel.refreshHelp"))
            .accessibilityIdentifier("panel.rescan")

            Button { model.openSettings() } label: { Label(L("panel.settings"), systemImage: "gearshape") }
                .buttonStyle(.borderless).help(L("panel.settingsHelp")).accessibilityLabel(L("panel.settingsHelp"))
            Spacer()
            if model.lastRefreshAt != nil, !model.isScanning {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .help(L("panel.updatedNow"))
                    .accessibilityLabel(L("panel.updatedNow"))
            }
            if model.hotKeyAvailable {
                Text("⌥M")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .help(L("panel.footerHotKey"))
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(L("panel.footerConflict"))
                    .accessibilityLabel(L("panel.footerConflict"))
            }
        }
        .padding(.horizontal, HubPanelLayout.panelPadding)
        .controlSize(.small)
        .frame(height: HubPanelLayout.footerHeight)
        .background(.bar)
    }

    private func statusBar(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, HubPanelLayout.panelPadding)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var permissionButtonTitle: String {
        switch model.permissionState {
        case .explanation: return L("panel.permissionContinue")
        case .repairRequired: return L("panel.permissionRepair")
        case .resetting: return L("panel.permissionRepairing")
        case .awaitingSystemChange: return L("panel.permissionWaiting")
        default: return L("panel.permissionLearn")
        }
    }

    private var permissionButtonDisabled: Bool {
        model.permissionState == .resetting || model.permissionState == .awaitingSystemChange
    }

    private func handlePermissionPrimaryAction() {
        switch model.permissionState {
        case .explanation: model.acceptPermissionExplanation()
        case .repairRequired: model.confirmPermissionRepair()
        case .unknown, .denied: model.requestPermission()
        case .authorized, .awaitingSystemChange, .resetting: break
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let router = PanelKeyboardRouter()
        guard let command = router.command(for: event) else { return false }
        switch router.action(for: command, hasSearchText: !model.query.isEmpty) {
        case .selectPrevious: model.selectPrevious()
        case .selectNext: model.selectNext()
        case .invokeSelection: model.invokeSelection(forceLaunchHost: false)
        case .openHost: model.invokeSelection(forceLaunchHost: true)
        case .openActionMenu:
            if let id = model.selectionID {
                model.actionMenuPresentationID = HubPanelPresentationContext.canonicalPresentationID(
                    itemID: id, query: model.query
                )
            }
        case .focusSearch: searchFocused = true
        case .invokeFavorite(let index): invokeFavorite(index)
        case .clearSearch: model.clearSearch(); searchFocused = true
        case .closePanel: NSApp.keyWindow?.performClose(nil)
        }
        return true
    }

    private func invokeFavorite(_ index: Int) {
        guard model.snapshot.favorites.indices.contains(index),
              let item = model.items.first(where: { $0.id == model.snapshot.favorites[index].id }) else { return }
        model.selectionID = item.id
        model.invoke(item)
    }

}

private struct PanelKeyboardMonitor: NSViewRepresentable {
    let handler: (NSEvent) -> Bool
    func makeNSView(context: Context) -> MonitoringView { let view = MonitoringView(); view.handler = handler; return view }
    func updateNSView(_ view: MonitoringView, context: Context) { view.handler = handler }

    final class MonitoringView: NSView {
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                guard event.window === window, self?.handler?(event) == true else { return event }
                return nil
            }
        }
    }
}
