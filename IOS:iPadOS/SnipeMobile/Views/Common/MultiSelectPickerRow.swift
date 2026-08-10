import SwiftUI

private struct MultiSelectSheetContent<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Set<Value>

    @State private var searchText = ""

    private var filteredItems: [(value: Value, label: String)] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return items }
        return items.filter { $0.label.lowercased().contains(q) }
    }

    var body: some View {
        List {
            ForEach(Array(filteredItems.enumerated()), id: \.offset) { _, item in
                Button {
                    if selection.contains(item.value) {
                        selection.remove(item.value)
                    } else {
                        selection.insert(item.value)
                    }
                } label: {
                    HStack {
                        Text(item.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(item.value) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: Text(L10n.string("search")))
    }
}

struct MultiSelectPickerRow<Value: Hashable>: View {
    let title: String
    let items: [(value: Value, label: String)]
    @Binding var selection: Set<Value>

    @State private var showSheet = false

    private var summary: String {
        let selectedLabels = items
            .filter { selection.contains($0.value) }
            .map { $0.label }
        if selectedLabels.isEmpty { return L10n.string("none") }
        return selectedLabels.joined(separator: ", ")
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                MultiSelectSheetContent(title: title, items: items, selection: $selection)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.string("done")) { showSheet = false }
                        }
                    }
            }
        }
    }
}
