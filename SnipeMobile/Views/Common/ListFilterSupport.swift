import SwiftUI

// one filterable dimension: a title and how to read its value off an item
struct FilterDimension<Item> {
    let title: String
    let value: (Item) -> String
}

// selected value per dimension title
struct ListFilter: Equatable {
    var selections: [String: String] = [:]

    var isActive: Bool { !selections.isEmpty }
    var activeCount: Int { selections.count }

    mutating func clear() { selections.removeAll() }

    func matches<Item>(_ item: Item, dimensions: [FilterDimension<Item>]) -> Bool {
        for dim in dimensions {
            if let selected = selections[dim.title], dim.value(item) != selected {
                return false
            }
        }
        return true
    }
}

// distinct, sorted values per dimension, derived from the loaded items
func listFilterOptions<Item>(_ items: [Item], dimensions: [FilterDimension<Item>]) -> [(title: String, values: [String])] {
    dimensions.map { dim in
        let cleaned = items
            .map { dim.value($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let values = Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return (dim.title, values)
    }
}

// header menu with a submenu per dimension, matching the assets filter
struct ListFilterMenu: View {
    @Binding var filter: ListFilter
    let options: [(title: String, values: [String])]

    var hasOptions: Bool {
        options.contains { !$0.values.isEmpty }
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.title) { option in
                dimensionPicker(title: option.title, values: option.values)
            }
            if filter.isActive {
                Divider()
                Button(role: .destructive) {
                    filter.clear()
                } label: {
                    Label(L10n.string("filter_clear"), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(filter.isActive ? L10n.string("filter_active_count", filter.activeCount) : L10n.string("filter"))
                Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private func dimensionPicker(title: String, values: [String]) -> some View {
        if !values.isEmpty {
            Menu {
                Picker(title, selection: Binding(
                    get: { filter.selections[title] },
                    set: { filter.selections[title] = $0 }
                )) {
                    Text(L10n.string("filter_all")).tag(String?.none)
                    ForEach(values, id: \.self) { value in
                        Text(value).tag(String?.some(value))
                    }
                }
            } label: {
                if let current = filter.selections[title] {
                    Label("\(title): \(current)", systemImage: "checkmark.circle.fill")
                } else {
                    Text(title)
                }
            }
        }
    }
}
