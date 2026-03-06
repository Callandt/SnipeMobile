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
        List(filteredOptions) { option in
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
        .searchable(text: $searchText, prompt: Text(L10n.string("search")))
    }
}

/// Tap opens searchable sheet. No NavigationLink.
struct SearchablePickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Value
    let emptyOption: (value: Value, label: String)?

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
                    emptyOption: emptyOption
                )
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("cancel")) { showSheet = false }
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

    private var totalCount: Int {
        items.count + (emptyOption != nil ? 1 : 0)
    }

    private var useSearchable: Bool {
        totalCount > kLargeListThreshold
    }

    var body: some View {
        if useSearchable {
            SearchablePickerRow(title: title, items: items, selection: $selection, emptyOption: emptyOption)
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
