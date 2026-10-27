import SwiftUI

// One option list for every picklist in the app: search, selection mark, same sheet.

struct PickerSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.string("search"), text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("close"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }
}

struct PickerOptionRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .listRowSeparator(.visible, edges: .bottom)
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground)
        )
    }
}

private struct PickableItem<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

struct OptionPickerSheet<Value: Hashable>: View {
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
        NavigationStack {
            VStack(spacing: 0) {
                PickerSearchField(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                if let onAddNew, let addNewLabel {
                    Button(action: onAddNew) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                            Text(addNewLabel)
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }

                if filteredOptions.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(filteredOptions) { option in
                                PickerOptionRow(label: option.label, isSelected: option.value == selection) {
                                    selection = option.value
                                    dismiss()
                                }
                                .id(option.id)
                            }
                        }
                        .listStyle(.plain)
                        .scrollDismissesKeyboard(.interactively)
                        .onAppear {
                            guard filteredOptions.contains(where: { $0.value == selection }) else { return }
                            DispatchQueue.main.async {
                                proxy.scrollTo(selection, anchor: .center)
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { dismiss() }
                }
                if let onAddNew {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: onAddNew) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(addNewLabel ?? L10n.string("create"))
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Closed row that always opens the shared option sheet.
struct SearchablePickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?
    var addNewLabel: String? = nil
    var onAddNew: (() -> Void)? = nil
    /// Puts the current value under the title so long listbox labels stay readable.
    var stackValue: Bool = false
    /// Shows only the current value. The title is still the sheet title.
    var valueOnly: Bool = false
    var leadingSymbol: String? = nil
    var leadingTint: Color = .accentColor

    @State private var showSheet = false

    private func displayLabel(for value: Value) -> String {
        if let e = emptyOption, e.value == value { return e.label }
        return items.first(where: { $0.value == value })?.label ?? "—"
    }

    private var selectionIsEmpty: Bool {
        emptyOption?.value == selection
    }

    private var usesStack: Bool {
        leadingSymbol == nil && !valueOnly && (stackValue || displayLabel(for: selection).count > 42)
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            rowLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(displayLabel(for: selection))
        .sheet(isPresented: $showSheet) {
            OptionPickerSheet(
                title: title,
                items: items,
                selection: $selection,
                emptyOption: emptyOption,
                addNewLabel: addNewLabel,
                onAddNew: onAddNew.map { add in
                    {
                        showSheet = false
                        DispatchQueue.main.async {
                            add()
                        }
                    }
                }
            )
        }
    }

    @ViewBuilder
    private var rowLabel: some View {
        if valueOnly {
            HStack(alignment: .center, spacing: 12) {
                Text(displayLabel(for: selection))
                    .foregroundStyle(selectionIsEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                pickerChevron
            }
        } else if usesStack {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(displayLabel(for: selection))
                        .foregroundStyle(selectionIsEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                pickerChevron
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                if let leadingSymbol {
                    PickerLeadingIcon(symbol: leadingSymbol, tint: leadingTint)
                }
                Text(title)
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                Text(displayLabel(for: selection))
                    .foregroundStyle(selectionIsEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                pickerChevron
            }
        }
    }

    private var pickerChevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

private struct PickerLeadingIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 29, height: 29)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

/// Every list size opens the same option sheet.
struct AdaptivePickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?
    var addNewLabel: String? = nil
    var onAddNew: (() -> Void)? = nil
    /// Long option labels stay readable under the title.
    var stackValue: Bool = false
    var valueOnly: Bool = false
    var leadingSymbol: String? = nil
    var leadingTint: Color = .accentColor

    /// Keeps a selection that is not in the loaded options visible.
    private var taggedItems: [(value: Value, label: String)] {
        var result = items
        let known = result.map(\.value)
        if !known.contains(selection), emptyOption?.value != selection {
            result.append((selection, "—"))
        }
        return result
    }

    var body: some View {
        SearchablePickerRow(
            title: title,
            items: taggedItems,
            selection: $selection,
            emptyOption: emptyOption,
            addNewLabel: addNewLabel,
            onAddNew: onAddNew,
            stackValue: stackValue,
            valueOnly: valueOnly,
            leadingSymbol: leadingSymbol,
            leadingTint: leadingTint
        )
    }
}

// MARK: - Inline management create

private func mergingPendingPickerItem<Value: Hashable>(
    _ items: [(value: Value, label: String)],
    pending: (value: Value, label: String)?
) -> [(value: Value, label: String)] {
    guard let pending else { return items }
    if items.contains(where: { $0.value == pending.value }) { return items }
    return items + [pending]
}

private func pickerValue<Value: Hashable>(fromCreatedId newId: Int) -> Value? {
    if Value.self == String.self { return String(newId) as? Value }
    if Value.self == Int.self { return newId as? Value }
    return nil
}

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
    @State private var pendingCreated: (value: Value, label: String)? = nil

    private var canCreate: Bool { creatableEntity != nil || creatableLocation || creatableUser }

    private var displayedItems: [(value: Value, label: String)] {
        mergingPendingPickerItem(items, pending: pendingCreated)
    }

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
            items: displayedItems,
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
        guard let newId, let newValue: Value = pickerValue(fromCreatedId: newId) else { return }
        let label = displayedItems.first(where: { $0.value == newValue })?.label
            ?? createdLabel(for: newId)
            ?? "#\(newId)"
        pendingCreated = (newValue, label)
        selection = newValue
    }

    private func createdLabel(for id: Int) -> String? {
        if creatableEntity == .categories {
            return apiClient.categories.first(where: { $0.id == id }).map { HTMLDecoder.decode($0.name) }
        }
        if creatableLocation {
            return apiClient.locations.first(where: { $0.id == id })?.decodedName
        }
        if creatableUser {
            return apiClient.users.first(where: { $0.id == id })?.decodedName
        }
        return nil
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
    @State private var pendingCreated: (value: Value, label: String)? = nil

    private var canCreate: Bool { creatableEntity != nil || creatableLocation || creatableUser }

    private var displayedItems: [(value: Value, label: String)] {
        mergingPendingPickerItem(items, pending: pendingCreated)
    }

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
            items: displayedItems,
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
        guard let newId, let newValue: Value = pickerValue(fromCreatedId: newId) else { return }
        let label = displayedItems.first(where: { $0.value == newValue })?.label
            ?? createdLabel(for: newId)
            ?? "#\(newId)"
        pendingCreated = (newValue, label)
        selection = newValue
    }

    private func createdLabel(for id: Int) -> String? {
        if creatableEntity == .categories {
            return apiClient.categories.first(where: { $0.id == id }).map { HTMLDecoder.decode($0.name) }
        }
        if creatableLocation {
            return apiClient.locations.first(where: { $0.id == id })?.decodedName
        }
        if creatableUser {
            return apiClient.users.first(where: { $0.id == id })?.decodedName
        }
        return nil
    }
}
