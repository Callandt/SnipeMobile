import SwiftUI

enum ListSortOrder: String, Hashable {
    case ascending
    case descending
}

enum ListSortField: String, Identifiable, Hashable {
    case name
    case updatedAt
    case createdAt
    case assetTag
    case purchaseDate
    case remaining
    case location
    case eolDate
    case warrantyExpires
    case nextAuditDate
    case lastAuditDate
    case lastCheckout
    case lastCheckin
    case expectedCheckin
    case expirationDate
    case terminationDate
    case startDate
    case completionDate

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .name: return L10n.string("name")
        case .updatedAt: return L10n.string("sort_last_modified")
        case .createdAt: return L10n.string("created_date")
        case .assetTag: return L10n.string("asset_tag")
        case .purchaseDate: return L10n.string("purchase_date")
        case .remaining: return L10n.string("remaining")
        case .location: return L10n.string("location")
        case .eolDate: return L10n.string("eol_date")
        case .warrantyExpires: return L10n.string("warranty_expires")
        case .nextAuditDate: return L10n.string("next_audit_date")
        case .lastAuditDate: return L10n.string("last_audit_date")
        case .lastCheckout: return L10n.string("last_checkout")
        case .lastCheckin: return L10n.string("last_checkin")
        case .expectedCheckin: return L10n.string("expected_checkin")
        case .expirationDate: return L10n.string("expiration_date")
        case .terminationDate: return L10n.string("termination_date")
        case .startDate: return L10n.string("start_date")
        case .completionDate: return L10n.string("completion_date")
        }
    }

    var kind: Kind {
        switch self {
        case .name, .location: return .text
        case .assetTag, .remaining: return .number
        default: return .date
        }
    }

    /// Deadlines default to soonest-first; recency fields to newest-first.
    var defaultOrder: ListSortOrder {
        switch self {
        case .name, .location:
            return .ascending
        case .assetTag:
            return .descending
        case .eolDate, .warrantyExpires, .nextAuditDate, .expirationDate, .terminationDate, .expectedCheckin:
            return .ascending
        default:
            return .descending
        }
    }

    var isDeadline: Bool {
        switch self {
        case .eolDate, .warrantyExpires, .nextAuditDate, .expirationDate, .terminationDate, .expectedCheckin:
            return true
        default:
            return false
        }
    }

    var ascendingTitle: String {
        switch kind {
        case .text: return "A–Z"
        case .date: return L10n.string("sort_oldest")
        case .number: return L10n.string("sort_low_high")
        }
    }

    var descendingTitle: String {
        switch kind {
        case .text: return "Z–A"
        case .date: return L10n.string("sort_newest")
        case .number: return L10n.string("sort_high_low")
        }
    }

    enum Kind {
        case text, date, number
    }
}

struct ListSort: Equatable {
    var field: ListSortField
    var order: ListSortOrder

    static let nameAscending = ListSort(field: .name, order: .ascending)
    static let assetTagDescending = ListSort(field: .assetTag, order: .descending)
    static let updatedDescending = ListSort(field: .updatedAt, order: .descending)
    static let startDateDescending = ListSort(field: .startDate, order: .descending)
}

enum ListSortComparable {
    case text(String)
    case numericText(String)
    case date(Date?)
    case number(Double?)

    /// -1 / 0 / 1. Missing dates and numbers always sort last.
    func compare(_ other: ListSortComparable, order: ListSortOrder) -> Int {
        switch (self, other) {
        case let (.text(lhs), .text(rhs)):
            return signed(Self.compareText(lhs, rhs), order: order)
        case let (.numericText(lhs), .numericText(rhs)):
            return signed(Self.compareNumericText(lhs, rhs), order: order)
        case let (.date(lhs), .date(rhs)):
            return compareOptional(Self.finiteInterval(lhs), Self.finiteInterval(rhs), order: order)
        case let (.number(lhs), .number(rhs)):
            return compareOptional(Self.finiteNumber(lhs), Self.finiteNumber(rhs), order: order)
        default:
            return 0
        }
    }

    private func compareOptional<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?,
        order: ListSortOrder
    ) -> Int {
        switch (lhs, rhs) {
        case (nil, nil):
            return 0
        case (nil, _):
            return 1
        case (_, nil):
            return -1
        case let (lhs?, rhs?):
            if lhs < rhs { return signed(-1, order: order) }
            if lhs > rhs { return signed(1, order: order) }
            return 0
        }
    }

    private func signed(_ raw: Int, order: ListSortOrder) -> Int {
        if raw == 0 { return 0 }
        let sign = raw < 0 ? -1 : 1
        return order == .ascending ? sign : -sign
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static func compareText(_ lhs: String, _ rhs: String) -> Int {
        signum(lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive], locale: posixLocale))
    }

    private static func compareNumericText(_ lhs: String, _ rhs: String) -> Int {
        signum(lhs.compare(rhs, options: [.numeric, .caseInsensitive, .diacriticInsensitive], locale: posixLocale))
    }

    private static func signum(_ result: ComparisonResult) -> Int {
        switch result {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }

    private static func finiteInterval(_ date: Date?) -> Double? {
        guard let date else { return nil }
        let value = date.timeIntervalSinceReferenceDate
        return value.isFinite ? value : nil
    }

    private static func finiteNumber(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}

struct ListSortKey<Item> {
    let field: ListSortField
    let value: (Item) -> ListSortComparable
}

struct EquatablePair<A: Equatable, B: Equatable>: Equatable {
    var first: A
    var second: B
}

/// Cached sort for the current list, search and sort.
final class ListSortMemo<Item> {
    private var sourcePointer = 0
    private var sourceCount = -1
    private var search = "\u{0}"
    private var sort: ListSort?
    private var extraEquals: ((Any) -> Bool)?
    private var items: [Item] = []

    func cached(
        from source: [Item],
        search: String,
        sort: ListSort,
        make: ([Item]) -> [Item]
    ) -> [Item] {
        cached(from: source, search: search, sort: sort, extra: true, make: make)
    }

    func cached<Extra: Equatable>(
        from source: [Item],
        search: String,
        sort: ListSort,
        extra: Extra,
        make: ([Item]) -> [Item]
    ) -> [Item] {
        let pointer = source.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map { Int(bitPattern: $0) } ?? 0
        }
        if pointer == sourcePointer,
           source.count == sourceCount,
           search == self.search,
           sort == self.sort,
           extraEquals?(extra) == true {
            return items
        }
        let result = make(source)
        sourcePointer = pointer
        sourceCount = source.count
        self.search = search
        self.sort = sort
        extraEquals = { ($0 as? Extra) == extra }
        items = result
        return result
    }
}

func applyListSort<Item: Identifiable>(
    _ items: [Item],
    sort: ListSort,
    keys: [ListSortKey<Item>]
) -> [Item] where Item.ID: Comparable {
    guard let key = keys.first(where: { $0.field == sort.field }) else { return items }
    // Sort indices so large `Asset` values are not copied on every TimSort swap.
    let probes = items.map { (value: key.value($0), id: $0.id) }
    let order = items.indices.sorted { lhs, rhs in
        let comparison = probes[lhs].value.compare(probes[rhs].value, order: sort.order)
        if comparison != 0 { return comparison < 0 }
        if probes[lhs].id != probes[rhs].id { return probes[lhs].id < probes[rhs].id }
        return lhs < rhs
    }
    return order.map { items[$0] }
}

enum ListSortCatalog {
    static let assets: [ListSortKey<Asset>] = [
        ListSortKey(field: .name) {
            .text($0.decodedName.isEmpty ? $0.decodedAssetTag : $0.decodedName)
        },
        ListSortKey(field: .assetTag) { .numericText($0.decodedAssetTag) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) },
        ListSortKey(field: .purchaseDate) { .date($0.purchaseDate?.parsedDate) },
        ListSortKey(field: .eolDate) { .date($0.assetEolDate?.parsedDate) },
        ListSortKey(field: .warrantyExpires) { .date($0.warrantyExpires?.parsedDate) },
        ListSortKey(field: .nextAuditDate) { .date($0.nextAuditDate?.parsedDate) },
        ListSortKey(field: .lastAuditDate) { .date($0.lastAuditDate?.parsedDate) },
        ListSortKey(field: .lastCheckout) { .date($0.lastCheckout?.parsedDate) },
        ListSortKey(field: .lastCheckin) { .date($0.lastCheckin?.parsedDate) },
        ListSortKey(field: .expectedCheckin) { .date($0.expectedCheckin?.parsedDate) }
    ]

    static let licenses: [ListSortKey<License>] = [
        ListSortKey(field: .name) { .text($0.decodedName) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) },
        ListSortKey(field: .purchaseDate) { .date($0.purchaseDate?.parsedDate) },
        ListSortKey(field: .expirationDate) { .date($0.expirationDate?.parsedDate) },
        ListSortKey(field: .terminationDate) { .date($0.terminationDate?.parsedDate) },
        ListSortKey(field: .remaining) { .number(Self.double(from: $0.remaining ?? $0.freeSeatsCount)) }
    ]

    static let accessories: [ListSortKey<Accessory>] = [
        ListSortKey(field: .name) { .text($0.decodedName) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) },
        ListSortKey(field: .purchaseDate) { .date(DateInfo.parseAPIDate($0.purchaseDate)) },
        ListSortKey(field: .remaining) { .number(Self.double(from: $0.remaining ?? $0.qty)) },
        ListSortKey(field: .location) { .text($0.decodedLocationName) }
    ]

    static let consumables: [ListSortKey<Consumable>] = [
        ListSortKey(field: .name) { .text($0.decodedName) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) },
        ListSortKey(field: .purchaseDate) { .date(DateInfo.parseAPIDate($0.purchaseDate)) },
        ListSortKey(field: .remaining) { .number(Self.double(from: $0.remaining ?? $0.qty)) },
        ListSortKey(field: .location) { .text($0.decodedLocationName) }
    ]

    static let components: [ListSortKey<Component>] = [
        ListSortKey(field: .name) { .text($0.decodedName) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) },
        ListSortKey(field: .purchaseDate) { .date(DateInfo.parseAPIDate($0.purchaseDate)) },
        ListSortKey(field: .remaining) { .number(Self.double(from: $0.remaining ?? $0.qty)) },
        ListSortKey(field: .location) { .text($0.decodedLocationName) }
    ]

    static let users: [ListSortKey<User>] = [
        ListSortKey(field: .name) { .text($0.decodedName) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) },
        ListSortKey(field: .location) { .text($0.decodedLocationName) }
    ]

    static let locations: [ListSortKey<Location>] = [
        ListSortKey(field: .name) { .text($0.decodedName) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) }
    ]

    static let maintenances: [ListSortKey<AssetMaintenance>] = [
        ListSortKey(field: .name) { .text($0.decodedTitle) },
        ListSortKey(field: .startDate) { .date($0.startDate?.parsedDate) },
        ListSortKey(field: .updatedAt) { .date($0.updatedAt?.parsedDate) },
        ListSortKey(field: .createdAt) { .date($0.createdAt?.parsedDate) },
        ListSortKey(field: .completionDate) { .date($0.completedAt?.parsedDate ?? $0.completionDate?.parsedDate) }
    ]

    private static func double(from value: Int?) -> Double? {
        value.map { Double($0) }
    }
}

struct ListSortMenu<Item>: View {
    @Binding var sort: ListSort
    let keys: [ListSortKey<Item>]

    private var fields: [ListSortField] { keys.map(\.field) }

    var body: some View {
        Menu {
            Section {
                sortChoice(sort.field.ascendingTitle, selected: sort.order == .ascending) {
                    applySort(ListSort(field: sort.field, order: .ascending))
                }
                sortChoice(sort.field.descendingTitle, selected: sort.order == .descending) {
                    applySort(ListSort(field: sort.field, order: .descending))
                }
            }
            Section {
                ForEach(fields) { field in
                    sortChoice(field.localizedTitle, selected: sort.field == field) {
                        applySort(ListSort(field: field, order: field.defaultOrder))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(L10n.string("sort"))
                Image(systemName: "arrow.up.arrow.down.circle")
            }
            .font(.subheadline)
        }
        .fixedSize()
        .accessibilityLabel(L10n.string("sort"))
        .accessibilityValue(sort.field.localizedTitle)
    }

    private func sortChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func applySort(_ next: ListSort) {
        guard next != sort else { return }
        DispatchQueue.main.async {
            sort = next
        }
    }
}
