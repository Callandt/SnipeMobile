import SwiftUI

// Shows the fields linked to a fieldset and lets you link/unlink them.
struct FieldsetDetailView: View {
    let fieldsetId: Int
    let fieldsetName: String
    @ObservedObject var apiClient: SnipeITAPIClient
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSavingName = false
    @State private var linked: [ManagementItem] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showAddSheet = false
    @State private var pendingRemove: ManagementItem?
    @State private var busyFieldId: Int?
    @State private var isSavingOrder = false
    @State private var notice: String?

    private var canSaveName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != fieldsetName
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(name.isEmpty ? fieldsetName : name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("close")) { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    }
                }
                .onAppear { if name.isEmpty { name = fieldsetName } }
                .task { if linked.isEmpty { await load() } }
                .refreshable { await load() }
                .sheet(isPresented: $showAddSheet, onDismiss: { Task { await load() } }) {
                    FieldAssociatePicker(
                        fieldsetId: fieldsetId,
                        alreadyLinkedIds: Set(linked.map(\.id)),
                        apiClient: apiClient
                    )
                }
                .confirmationDialog(
                    removeTitle,
                    isPresented: removeBinding,
                    titleVisibility: .visible
                ) {
                    Button(L10n.string("fieldset_unlink"), role: .destructive) {
                        if let item = pendingRemove { Task { await disassociate(item) } }
                    }
                    Button(L10n.string("cancel"), role: .cancel) { pendingRemove = nil }
                } message: {
                    if let item = pendingRemove {
                        Text(L10n.string("fieldset_unlink_message", fieldName(item.raw)))
                    }
                }
                .overlay(alignment: .bottom) { noticeView }
        }
    }

    private var content: some View {
        List {
            Section(L10n.string("name")) {
                HStack {
                    TextField(L10n.string("name"), text: $name)
                    if isSavingName {
                        ProgressView()
                    } else if canSaveName {
                        Button(L10n.string("save")) { Task { await saveName() } }
                            .font(.callout.weight(.semibold))
                    }
                }
            }

            linkedSection

            Section {
                Button {
                    showAddSheet = true
                } label: {
                    Label(L10n.string("fieldset_add_field"), systemImage: "plus.circle.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var linkedSection: some View {
        Section {
            if isLoading && linked.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if let loadError, linked.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loadError).foregroundStyle(.secondary)
                    Button(L10n.string("retry")) { Task { await load() } }
                }
            } else if linked.isEmpty {
                Text(L10n.string("fieldset_no_fields_desc"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linked) { item in
                    fieldRow(item)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingRemove = item
                            } label: {
                                Label(L10n.string("fieldset_unlink"), systemImage: "minus.circle")
                            }
                        }
                }
                .onMove(perform: moveFields)
            }
        } header: {
            Text(L10n.string("fieldset_linked_fields"))
        } footer: {
            if !linked.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("mgmt_item_count", linked.count))
                    Text(L10n.string("fieldset_reorder_hint"))
                }
            }
        }
        .environment(\.editMode, linked.isEmpty ? .constant(.inactive) : .constant(.active))
    }

    private func fieldRow(_ item: ManagementItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.indigo.gradient)
                .frame(width: 29, height: 29)
                .overlay(
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldName(item.raw))
                if let element = fieldElement(item.raw) {
                    Text(element).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if busyFieldId == item.id {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    private func fieldName(_ row: [String: Any]) -> String {
        HTMLDecoder.decode(ManagementValue.scalarString(row["name"]))
    }

    private func fieldElement(_ row: [String: Any]) -> String? {
        let element = ManagementValue.scalarString(row["type"] ?? row["element"]).capitalized
        return element.isEmpty ? nil : element
    }

    private var removeBinding: Binding<Bool> {
        Binding(
            get: { pendingRemove != nil },
            set: { if !$0 { pendingRemove = nil } }
        )
    }

    private var removeTitle: String {
        guard let item = pendingRemove else { return L10n.string("fieldset_unlink") }
        return L10n.string("fieldset_unlink_title", fieldName(item.raw))
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        loadError = nil
        let result = await apiClient.fetchFieldsetLinkedFields(fieldsetId: fieldsetId)
        isLoading = false
        if let rows = result.rows {
            linked = rows.compactMap { row in
                guard let id = row["id"] as? Int else { return nil }
                return ManagementItem(id: id, raw: row)
            }
        } else {
            loadError = result.error
        }
    }

    private func moveFields(from source: IndexSet, to destination: Int) {
        guard !isSavingOrder else { return }
        var reordered = linked
        reordered.move(fromOffsets: source, toOffset: destination)
        let previous = linked
        linked = reordered
        Task { await persistOrder(previous: previous) }
    }

    private func persistOrder(previous: [ManagementItem]) async {
        isSavingOrder = true
        let result = await apiClient.reorderFieldsetFields(
            fieldsetId: fieldsetId,
            fieldIds: linked.map(\.id)
        )
        isSavingOrder = false
        if result.success {
            await apiClient.fetchFieldsets()
        } else {
            linked = previous
            await showNotice(result.message ?? L10n.string("fieldset_reorder_failed"))
        }
    }

    private func saveName() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSavingName = true
        let result = await apiClient.managementUpdate(
            path: "/api/v1/fieldsets",
            id: fieldsetId,
            body: ["name": trimmed]
        )
        isSavingName = false
        await showNotice(result.success ? L10n.string("saved") : (result.message ?? L10n.string("mgmt_save_failed")))
        if result.success { await apiClient.fetchFieldsets() }
    }

    private func disassociate(_ item: ManagementItem) async {
        pendingRemove = nil
        busyFieldId = item.id
        let result = await apiClient.managementCreate(
            path: "/api/v1/fields/\(item.id)/disassociate",
            body: ["fieldset_id": fieldsetId]
        )
        busyFieldId = nil
        if result.success {
            linked.removeAll { $0.id == item.id }
            await showNotice(L10n.string("fieldset_field_unlinked"))
        } else {
            await showNotice(result.message ?? L10n.string("mgmt_save_failed"))
        }
    }

    @MainActor
    private func showNotice(_ message: String) async {
        withAnimation { notice = message }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        withAnimation { notice = nil }
    }
}

// Picker of fields not yet in the fieldset; tap to link.
private struct FieldAssociatePicker: View {
    let fieldsetId: Int
    let alreadyLinkedIds: Set<Int>
    @ObservedObject var apiClient: SnipeITAPIClient
    @Environment(\.dismiss) private var dismiss

    @State private var allFields: [ManagementItem] = []
    @State private var addedIds: Set<Int> = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var busyFieldId: Int?

    private var available: [ManagementItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return allFields.filter { item in
            guard !alreadyLinkedIds.contains(item.id), !addedIds.contains(item.id) else { return false }
            guard !query.isEmpty else { return true }
            return name(item.raw).lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && allFields.isEmpty {
                    ProgressView(L10n.string("loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError, allFields.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.string("mgmt_load_failed"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    }
                } else if available.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.string("fieldset_no_available"), systemImage: "checkmark.circle")
                    }
                } else {
                    List(available) { item in
                        Button {
                            Task { await associate(item) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name(item.raw)).foregroundStyle(.primary)
                                    if let element = element(item.raw) {
                                        Text(element).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if busyFieldId == item.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: Text(L10n.string("search")))
                }
            }
            .navigationTitle(L10n.string("fieldset_add_field"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("close")) { dismiss() }
                }
            }
            .task { if allFields.isEmpty { await load() } }
        }
    }

    private func name(_ row: [String: Any]) -> String {
        HTMLDecoder.decode(ManagementValue.scalarString(row["name"]))
    }

    private func element(_ row: [String: Any]) -> String? {
        let element = ManagementValue.scalarString(row["type"] ?? row["element"]).capitalized
        return element.isEmpty ? nil : element
    }

    private func load() async {
        isLoading = true
        loadError = nil
        let result = await apiClient.managementFetchRows(path: "/api/v1/fields")
        isLoading = false
        if let rows = result.rows {
            allFields = rows.compactMap { row in
                guard let id = row["id"] as? Int else { return nil }
                return ManagementItem(id: id, raw: row)
            }
            .sorted { name($0.raw).localizedCaseInsensitiveCompare(name($1.raw)) == .orderedAscending }
        } else {
            loadError = result.error
        }
    }

    private func associate(_ item: ManagementItem) async {
        busyFieldId = item.id
        let result = await apiClient.managementCreate(
            path: "/api/v1/fields/\(item.id)/associate",
            body: [
                "fieldset_id": fieldsetId,
                "order": alreadyLinkedIds.count + addedIds.count
            ]
        )
        busyFieldId = nil
        if result.success {
            withAnimation { _ = addedIds.insert(item.id) }
        }
    }
}
