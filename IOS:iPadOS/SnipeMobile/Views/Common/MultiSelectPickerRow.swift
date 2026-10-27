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
        VStack(spacing: 0) {
            PickerSearchField(text: $searchText)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

            if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(filteredItems.enumerated()), id: \.offset) { _, item in
                        PickerOptionRow(label: item.label, isSelected: selection.contains(item.value)) {
                            if selection.contains(item.value) {
                                selection.remove(item.value)
                            } else {
                                selection.insert(item.value)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
            .map(\.label)
        if selectedLabels.isEmpty { return L10n.string("none") }
        return selectedLabels.joined(separator: ", ")
    }

    private var selectionIsEmpty: Bool {
        items.allSatisfy { !selection.contains($0.value) }
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                Text(summary)
                    .foregroundStyle(selectionIsEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                MultiSelectSheetContent(title: title, items: items, selection: $selection)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.string("done")) { showSheet = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
