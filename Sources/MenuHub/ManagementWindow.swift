import AppKit
import Combine
import MenuHubCore
import SwiftUI

@MainActor
final class ManagementModel: ObservableObject {
    @Published var query = ""
    @Published var selectedItemID: String?
    @Published private(set) var revision = 0
    let controller: CatalogController
    private var observation: AnyCancellable?

    init(controller: CatalogController) {
        self.controller = controller
        observation = controller.objectWillChange.sink { [weak self] _ in self?.revision += 1 }
    }

    var filteredItems: [MenuBarItemRecord] {
        let ordered = controller.document.items.sorted {
            $0.manualOrder == $1.manualOrder ? $0.id < $1.id : $0.manualOrder < $1.manualOrder
        }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return ordered }
        let groupNames = Dictionary(uniqueKeysWithValues: controller.document.groups.map { ($0.id, $0.name) })
        return ordered.filter { item in
            let names = item.groupIDs.compactMap { groupNames[$0] }
            return ([item.hostName, item.displayName, item.identity.originalName, item.identity.bundleIdentifier] + names)
                .contains { $0.localizedStandardContains(term) }
        }
    }

    var selectedItem: MenuBarItemRecord? {
        controller.document.items.first { $0.id == selectedItemID }
    }

    var canReorder: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func move(from offsets: IndexSet, to destination: Int) {
        guard canReorder else { return }
        var ids = filteredItems.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        Task { await controller.reorderItems(itemIDs: ids) }
    }

    func moveGroups(from offsets: IndexSet, to destination: Int) {
        var ids = controller.document.groups.sorted { $0.manualOrder < $1.manualOrder }.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        Task { await controller.reorderGroups(groupIDs: ids) }
    }

    func deleteGroup(_ id: UUID, undoManager: UndoManager?) {
        Task {
            guard let deletion = await controller.deleteGroupForUndo(id: id) else { return }
            undoManager?.registerUndo(withTarget: self) { target in target.restoreGroup(deletion) }
            undoManager?.setActionName(L("management.deleteUndoName"))
        }
    }

    nonisolated private func restoreGroup(_ deletion: DeletedGroupSnapshot) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await controller.restoreDeletedGroup(deletion)
        }
    }
}

struct ManagementWindow: View {
    @StateObject private var model: ManagementModel
    @Environment(\.undoManager) private var undoManager

    init(controller: CatalogController) {
        _model = StateObject(wrappedValue: ManagementModel(controller: controller))
    }

    init(model: ManagementModel) { _model = StateObject(wrappedValue: model) }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedItemID) {
                Section(L("management.items")) {
                    ForEach(model.filteredItems) { item in
                        HStack {
                            Image(systemName: item.isIgnored ? "eye.slash" : "menubar.rectangle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.hostName.isEmpty ? item.displayName : item.hostName)
                                Text(item.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        }
                        .tag(item.id)
                        .moveDisabled(!model.canReorder)
                    }
                    .onMove(perform: model.move)
                    if !model.canReorder {
                        Text(L("management.clearSearchToReorder"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(L("management.groups")) {
                    ForEach(model.controller.document.groups.sorted { $0.manualOrder < $1.manualOrder }) { group in
                        TextField(L("management.groupName"), text: Binding(
                            get: { group.name },
                            set: { value in Task { await model.controller.renameGroup(id: group.id, name: value) } }
                        ))
                        .contextMenu {
                            Button(L("management.deleteGroup"), role: .destructive) { model.deleteGroup(group.id, undoManager: undoManager) }
                        }
                    }
                    .onMove(perform: model.moveGroups)
                }
            }
            .searchable(text: $model.query, prompt: L("management.search"))
            .navigationSplitViewColumnWidth(min: 260, ideal: 310)
        } detail: {
            if let item = model.selectedItem {
                ItemInspector(item: item, controller: model.controller)
            } else {
                ContentUnavailableView(L("management.selectItem"), systemImage: "menubar.rectangle")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await model.controller.scan() } } label: { Label(L("management.rescan"), systemImage: "arrow.clockwise") }
                Menu {
                    Button(L("management.newGroup")) { Task { _ = await model.controller.createGroup(name: L("management.newGroupName")) } }
                    Divider()
                    ForEach(model.controller.document.groups.sorted { $0.manualOrder < $1.manualOrder }) { group in
                        Button(L("management.deleteNamedGroupFormat", group.name), role: .destructive) { model.deleteGroup(group.id, undoManager: undoManager) }
                    }
                } label: { Label(L("management.groups"), systemImage: "folder") }
            }
        }
        .frame(minWidth: 700, minHeight: 480)
    }
}

private struct ItemInspector: View {
    let item: MenuBarItemRecord
    @ObservedObject var controller: CatalogController
    @State private var alias = ""

    var body: some View {
        Form {
            Section(L("management.items")) {
                LabeledContent(L("management.app"), value: item.hostName)
                LabeledContent(L("management.originalName"), value: item.identity.originalName)
                TextField(L("management.alias"), text: $alias)
                    .onSubmit { Task { await controller.setAlias(alias, itemID: item.id) } }
                    .onChange(of: alias) { _, value in
                        Task { await controller.setAlias(value, itemID: item.id) }
                    }
                Toggle(L("management.favorite"), isOn: Binding(
                    get: { item.isFavorite },
                    set: { value in Task { await controller.setFavorite(value, itemID: item.id) } }
                ))
                Toggle(L("management.ignore"), isOn: Binding(
                    get: { item.isIgnored },
                    set: { value in Task { await controller.setIgnored(value, itemID: item.id) } }
                ))
                Picker(L("management.unreadBadge"), selection: Binding(
                    get: { item.unreadBadgePreference },
                    set: { value in
                        Task { await controller.setUnreadBadgePreference(value, itemID: item.id) }
                    }
                )) {
                    Text(L("management.unreadBadgeAutomatic")).tag(UnreadBadgePreference.automatic)
                    Text(L("management.unreadBadgeInclude")).tag(UnreadBadgePreference.include)
                    Text(L("management.unreadBadgeExclude")).tag(UnreadBadgePreference.exclude)
                }
                Text(L("management.unreadBadgeHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L("management.groups")) {
                ForEach(controller.document.groups.sorted { $0.manualOrder < $1.manualOrder }) { group in
                    Toggle(group.name, isOn: Binding(
                        get: { item.groupIDs.contains(group.id) },
                        set: { value in Task { await controller.setMembership(value, itemID: item.id, groupID: group.id) } }
                    ))
                }
            }
            Section(L("management.capabilities")) {
                LabeledContent(L("management.status"), value: localizedCapability(item.capability))
                LabeledContent(L("management.lastSeen"), value: item.lastSeenAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent(L("management.lastError"), value: item.lastError?.rawValue ?? L("common.none"))
                Button(L("management.retest")) { Task { await controller.scan() } }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { alias = item.alias ?? "" }
        .onChange(of: item.id) { _, _ in alias = item.alias ?? "" }
    }

    private func localizedCapability(_ capability: ItemCapability) -> String {
        switch capability {
        case .full, .actionable: L("capability.actionable")
        case .launchOnly: L("capability.openApp")
        case .unavailable: L("capability.unavailable")
        }
    }
}
