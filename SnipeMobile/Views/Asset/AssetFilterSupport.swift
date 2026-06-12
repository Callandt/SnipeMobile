import SwiftUI

// status choice; "deployed" is synthetic (matched on assignment, not a label)
enum AssetStatusSelection: Hashable {
    case all
    case deployed
    case status(Int)
}

// multi-dimension filter for the assets overview
struct AssetFilter: Equatable {
    var statusSelection: AssetStatusSelection = .all
    var category: String? = nil
    var model: String? = nil
    var manufacturer: String? = nil
    var location: String? = nil

    var isStatusActive: Bool {
        statusSelection != .all
    }

    var isActive: Bool {
        isStatusActive || category != nil || model != nil || manufacturer != nil || location != nil
    }

    var activeCount: Int {
        var count = [category, model, manufacturer, location].compactMap { $0 }.count
        if isStatusActive { count += 1 }
        return count
    }

    mutating func clear() {
        statusSelection = .all
        category = nil
        model = nil
        manufacturer = nil
        location = nil
    }

    func matches(_ asset: Asset) -> Bool {
        switch statusSelection {
        case .all:
            break
        case .deployed:
            if asset.assignedTo == nil { return false }
        case .status(let id):
            if asset.statusLabel.id != id { return false }
        }
        if let category, asset.decodedCategoryName != category { return false }
        if let model, asset.decodedModelName != model { return false }
        if let manufacturer, asset.decodedManufacturerName != manufacturer { return false }
        if let location, asset.decodedLocationName != location { return false }
        return true
    }
}

// distinct values per dimension, derived from the loaded assets
struct AssetFilterOptions {
    let statusLabels: [StatusLabel]
    let categories: [String]
    let models: [String]
    let manufacturers: [String]
    let locations: [String]

    var isEmpty: Bool {
        statusLabels.isEmpty && categories.isEmpty && models.isEmpty && manufacturers.isEmpty && locations.isEmpty
    }

    init(assets: [Asset], statusLabels: [StatusLabel]) {
        self.statusLabels = AssetStatusFilterSupport.sortedStatusLabels(statusLabels)
        categories = AssetFilterOptions.distinct(assets.map(\.decodedCategoryName))
        models = AssetFilterOptions.distinct(assets.map(\.decodedModelName))
        manufacturers = AssetFilterOptions.distinct(assets.map(\.decodedManufacturerName))
        locations = AssetFilterOptions.distinct(assets.map(\.decodedLocationName))
    }

    private static func distinct(_ values: [String]) -> [String] {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

// header menu with a submenu per dimension, like the maintenance filter
struct AssetFilterMenu: View {
    @Binding var filter: AssetFilter
    let options: AssetFilterOptions

    var body: some View {
        Menu {
            statusPicker
            dimensionPicker(
                title: L10n.string("category"),
                values: options.categories,
                selection: $filter.category
            )
            dimensionPicker(
                title: L10n.string("model"),
                values: options.models,
                selection: $filter.model
            )
            dimensionPicker(
                title: L10n.string("manufacturer"),
                values: options.manufacturers,
                selection: $filter.manufacturer
            )
            dimensionPicker(
                title: L10n.string("location"),
                values: options.locations,
                selection: $filter.location
            )

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
    private var statusPicker: some View {
        Menu {
            Picker(L10n.string("status"), selection: $filter.statusSelection) {
                Text(L10n.string("filter_all")).tag(AssetStatusSelection.all)
                Text(L10n.statusLabel("deployed")).tag(AssetStatusSelection.deployed)
                ForEach(options.statusLabels, id: \.id) { label in
                    Text(AssetStatusFilterSupport.displayName(for: label))
                        .tag(AssetStatusSelection.status(label.id))
                }
            }
        } label: {
            if filter.isStatusActive {
                Label("\(L10n.string("status")): \(statusSelectionLabel)", systemImage: "checkmark.circle.fill")
            } else {
                Text(L10n.string("status"))
            }
        }
    }

    private var statusSelectionLabel: String {
        switch filter.statusSelection {
        case .all:
            return L10n.string("filter_all")
        case .deployed:
            return L10n.statusLabel("deployed")
        case .status(let id):
            if let label = options.statusLabels.first(where: { $0.id == id }) {
                return AssetStatusFilterSupport.displayName(for: label)
            }
            return L10n.string("status")
        }
    }

    @ViewBuilder
    private func dimensionPicker(
        title: String,
        values: [String],
        selection: Binding<String?>
    ) -> some View {
        if !values.isEmpty {
            Menu {
                Picker(title, selection: selection) {
                    Text(L10n.string("filter_all")).tag(String?.none)
                    ForEach(values, id: \.self) { value in
                        Text(value).tag(String?.some(value))
                    }
                }
            } label: {
                if let current = selection.wrappedValue {
                    Label("\(title): \(current)", systemImage: "checkmark.circle.fill")
                } else {
                    Text(title)
                }
            }
        }
    }
}

enum AssetStatusFilterSupport {
    static func displayName(for label: StatusLabel) -> String {
        if let meta = label.statusMeta?.trimmingCharacters(in: .whitespacesAndNewlines), !meta.isEmpty {
            return L10n.statusLabel(meta)
        }
        return HTMLDecoder.decode(label.name)
    }

    static func sortedStatusLabels(_ labels: [StatusLabel]) -> [StatusLabel] {
        labels.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
    }
}
