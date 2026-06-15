import SwiftUI

// one row from a list endpoint
struct ManagementItem: Identifiable {
    let id: Int
    let raw: [String: Any]
}

// Browse + search + add/edit/delete, shared by every entity.
struct ManagementListView: View {
    let entity: ManagementEntity
    @ObservedObject var apiClient: SnipeITAPIClient

    @State private var items: [ManagementItem] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editItem: ManagementItem?
    @State private var pendingDelete: ManagementItem?
    @State private var isDeleting = false
    @State private var notice: String?

    private var config: ManagementEntityConfig { entity.config }

    private var filteredItems: [ManagementItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { config.titleReader($0.raw).lowercased().contains(query) }
    }

    var body: some View {
        content
            .navigationTitle(L10n.string(entity.titleKey))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await loadIfNeeded() }
            .refreshable { await load() }
            .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
                ManagementFormView(entity: entity, apiClient: apiClient, existing: nil)
            }
            .sheet(item: $editItem, onDismiss: { Task { await load() } }) { item in
                if entity == .fieldsets {
                    FieldsetDetailView(
                        fieldsetId: item.id,
                        fieldsetName: config.titleReader(item.raw),
                        apiClient: apiClient
                    )
                } else {
                    ManagementFormView(entity: entity, apiClient: apiClient, existing: item)
                }
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: deleteBinding,
                titleVisibility: .visible
            ) {
                Button(L10n.string("delete"), role: .destructive) {
                    if let item = pendingDelete { Task { await delete(item) } }
                }
                Button(L10n.string("cancel"), role: .cancel) { pendingDelete = nil }
            } message: {
                if let item = pendingDelete {
                    Text(L10n.string("mgmt_delete_message", config.titleReader(item.raw)))
                }
            }
            .overlay(alignment: .bottom) {
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
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty {
            ProgressView(L10n.string("loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, items.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("mgmt_load_failed"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button(L10n.string("retry")) { Task { await load() } }
            }
        } else if items.isEmpty {
            ContentUnavailableView {
                Label(L10n.string("mgmt_empty"), systemImage: entity.icon)
            } description: {
                Text(L10n.string("mgmt_empty_desc"))
            } actions: {
                Button(L10n.string("create")) { showAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(filteredItems) { item in
                    Button {
                        editItem = item
                    } label: {
                        row(for: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = item
                        } label: {
                            Label(L10n.string("delete"), systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text(L10n.string("mgmt_item_count", items.count))
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: Text(L10n.string("search")))
    }

    private func row(for item: ManagementItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(entity.iconColor.gradient)
                .frame(width: 29, height: 29)
                .overlay(
                    Image(systemName: entity.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(config.titleReader(item.raw))
                    .foregroundStyle(.primary)
                if let subtitle = config.subtitleReader?(item.raw), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Delete confirmation binding

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil && !isDeleting },
            set: { newValue in if !newValue { pendingDelete = nil } }
        )
    }

    private var deleteTitle: String {
        guard let item = pendingDelete else { return L10n.string("delete") }
        return L10n.string("mgmt_delete_title", config.titleReader(item.raw))
    }

    // MARK: - Data

    private func loadIfNeeded() async {
        if items.isEmpty { await load() }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        let result = await apiClient.managementFetchRows(path: config.path)
        isLoading = false
        if let rows = result.rows {
            items = rows.compactMap { row in
                guard let id = row["id"] as? Int else { return nil }
                return ManagementItem(id: id, raw: row)
            }
            .sorted { config.titleReader($0.raw).localizedCaseInsensitiveCompare(config.titleReader($1.raw)) == .orderedAscending }
        } else {
            loadError = result.error
        }
    }

    private func delete(_ item: ManagementItem) async {
        isDeleting = true
        let result = await apiClient.managementDelete(path: config.path, id: item.id)
        isDeleting = false
        pendingDelete = nil
        if result.success {
            items.removeAll { $0.id == item.id }
            await showNotice(L10n.string("mgmt_deleted"))
        } else {
            await showNotice(result.message ?? L10n.string("mgmt_save_failed"))
        }
    }

    @MainActor
    private func showNotice(_ message: String) async {
        withAnimation { notice = message }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        withAnimation { notice = nil }
    }
}
