import SwiftUI

// MARK: - Picker item
private struct PickableItem<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

// MARK: - Searchable sheet
private struct SearchablePickerSheetContent<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?
    var addNewLabel: String? = nil
    var onAddNew: (() -> Void)? = nil

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var allOptions: [PickableItem<Value>] {
        let empty: [PickableItem<Value>] = emptyOption.map { [PickableItem(value: $0.value, label: $0.label)] } ?? []
        return empty + items.map { PickableItem(value: $0.value, label: $0.label) }
    }

    private var filteredOptions: [PickableItem<Value>] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return allOptions }
        return allOptions.filter { $0.label.lowercased().contains(q) }
    }

    var body: some View {
        List {
            if let onAddNew, let addNewLabel {
                Section {
                    Button(action: onAddNew) {
                        Label(addNewLabel, systemImage: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            Section {
                ForEach(filteredOptions) { option in
                    Button {
                        selection = option.value
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.label)
                                .foregroundStyle(.primary)
                            if option.value == selection {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: Text(L10n.string("search")))
    }
}

/// Tap opens searchable sheet. No NavigationLink.
struct SearchablePickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?
    var addNewLabel: String? = nil
    var onAddNew: (() -> Void)? = nil

    @State private var showSheet = false

    private func displayLabel(for value: Value) -> String {
        if let e = emptyOption, e.value == value { return e.label }
        return items.first(where: { $0.value == value })?.label ?? "—"
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(displayLabel(for: selection))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                SearchablePickerSheetContent(
                    title: title,
                    items: items,
                    selection: $selection,
                    emptyOption: emptyOption,
                    addNewLabel: addNewLabel,
                    onAddNew: {
                        showSheet = false
                        DispatchQueue.main.async {
                            onAddNew?()
                        }
                    }
                )
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("cancel")) { showSheet = false }
                    }
                    if let onAddNew {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showSheet = false
                                DispatchQueue.main.async {
                                    onAddNew()
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(addNewLabel ?? L10n.string("create"))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Size threshold
private let kLargeListThreshold = 12

/// Small list = Picker. Large = sheet.
struct AdaptivePickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?
    var addNewLabel: String? = nil
    var onAddNew: (() -> Void)? = nil

    private var totalCount: Int {
        items.count + (emptyOption != nil ? 1 : 0)
    }

    private var useSearchable: Bool {
        totalCount > kLargeListThreshold || onAddNew != nil
    }

    var body: some View {
        if useSearchable {
            SearchablePickerRow(
                title: title,
                items: items,
                selection: $selection,
                emptyOption: emptyOption,
                addNewLabel: addNewLabel,
                onAddNew: onAddNew
            )
        } else {
            Picker(title, selection: $selection) {
                if let e = emptyOption {
                    Text(e.label).tag(e.value)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Text(item.label).tag(item.value)
                }
            }
        }
    }
}

// MARK: - Inline management create

/// Picker row with optional inline create via management forms, locations, or users.
struct CreatableAdaptivePickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?
    @ObservedObject var apiClient: SnipeITAPIClient
    var creatableEntity: ManagementEntity? = nil
    var creatableLocation: Bool = false
    var creatableUser: Bool = false
    var createDefaults: [String: String] = [:]

    @State private var showManagementForm = false
    @State private var showLocationForm = false
    @State private var showUserForm = false

    private var canCreate: Bool { creatableEntity != nil || creatableLocation || creatableUser }

    private var addNewLabel: String? {
        if let creatableEntity {
            return L10n.string("mgmt_new_title", L10n.string(creatableEntity.config.singularKey))
        }
        if creatableLocation { return L10n.string("new_location") }
        if creatableUser { return L10n.string("new_user") }
        return nil
    }

    var body: some View {
        AdaptivePickerRow(
            title: title,
            items: items,
            selection: $selection,
            emptyOption: emptyOption,
            addNewLabel: addNewLabel,
            onAddNew: canCreate ? { openCreateForm() } : nil
        )
        .sheet(isPresented: $showManagementForm) {
            if let creatableEntity {
                ManagementFormView(
                    entity: creatableEntity,
                    apiClient: apiClient,
                    existing: nil,
                    initialDefaults: createDefaults,
                    onCreated: { newId in
                        applyCreatedId(newId)
                    }
                )
            }
        }
        .sheet(isPresented: $showLocationForm) {
            AddLocationSheet(
                apiClient: apiClient,
                isPresented: $showLocationForm,
                onCreated: { newId in
                    applyCreatedId(newId)
                }
            )
        }
        .sheet(isPresented: $showUserForm) {
            AddUserSheet(
                apiClient: apiClient,
                isPresented: $showUserForm,
                onCreated: { newId in
                    applyCreatedId(newId)
                }
            )
        }
    }

    private func openCreateForm() {
        if creatableEntity != nil {
            showManagementForm = true
        } else if creatableLocation {
            showLocationForm = true
        } else if creatableUser {
            showUserForm = true
        }
    }

    private func applyCreatedId(_ newId: Int?) {
        guard let newId else { return }
        if Value.self == String.self {
            selection = (String(newId) as! Value)
        } else if Value.self == Int.self {
            selection = (newId as! Value)
        }
    }
}

/// Searchable picker row with optional inline create (for large lists in forms).
struct CreatableSearchablePickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?
    @ObservedObject var apiClient: SnipeITAPIClient
    var creatableEntity: ManagementEntity? = nil
    var creatableLocation: Bool = false
    var creatableUser: Bool = false
    var createDefaults: [String: String] = [:]

    @State private var showManagementForm = false
    @State private var showLocationForm = false
    @State private var showUserForm = false

    private var canCreate: Bool { creatableEntity != nil || creatableLocation || creatableUser }

    private var addNewLabel: String? {
        if let creatableEntity {
            return L10n.string("mgmt_new_title", L10n.string(creatableEntity.config.singularKey))
        }
        if creatableLocation { return L10n.string("new_location") }
        if creatableUser { return L10n.string("new_user") }
        return nil
    }

    var body: some View {
        SearchablePickerRow(
            title: title,
            items: items,
            selection: $selection,
            emptyOption: emptyOption,
            addNewLabel: addNewLabel,
            onAddNew: canCreate ? { openCreateForm() } : nil
        )
        .sheet(isPresented: $showManagementForm) {
            if let creatableEntity {
                ManagementFormView(
                    entity: creatableEntity,
                    apiClient: apiClient,
                    existing: nil,
                    initialDefaults: createDefaults,
                    onCreated: { newId in
                        applyCreatedId(newId)
                    }
                )
            }
        }
        .sheet(isPresented: $showLocationForm) {
            AddLocationSheet(
                apiClient: apiClient,
                isPresented: $showLocationForm,
                onCreated: { newId in
                    applyCreatedId(newId)
                }
            )
        }
        .sheet(isPresented: $showUserForm) {
            AddUserSheet(
                apiClient: apiClient,
                isPresented: $showUserForm,
                onCreated: { newId in
                    applyCreatedId(newId)
                }
            )
        }
    }

    private func openCreateForm() {
        if creatableEntity != nil {
            showManagementForm = true
        } else if creatableLocation {
            showLocationForm = true
        } else if creatableUser {
            showUserForm = true
        }
    }

    private func applyCreatedId(_ newId: Int?) {
        guard let newId else { return }
        if Value.self == String.self {
            selection = (String(newId) as! Value)
        } else if Value.self == Int.self {
            selection = (newId as! Value)
        }
    }
}
