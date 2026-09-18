import SwiftUI

enum CardKind: String, CaseIterable, Identifiable, Hashable {
    case asset
    case user
    case accessory
    case license
    case consumable
    case component

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .asset: return "tab_assets"
        case .user: return "tab_users"
        case .accessory: return "tab_accessories"
        case .license: return "tab_licenses"
        case .consumable: return "tab_consumables"
        case .component: return "tab_components"
        }
    }

    var settingsIcon: String {
        switch self {
        case .asset: return "laptopcomputer"
        case .user: return "person.2.fill"
        case .accessory: return "mediastick"
        case .license: return "doc.text.fill"
        case .consumable: return "shippingbox.fill"
        case .component: return "cpu"
        }
    }

    var settingsIconColor: Color {
        switch self {
        case .asset: return .blue
        case .user: return .teal
        case .accessory: return .purple
        case .license: return .orange
        case .consumable: return .green
        case .component: return .indigo
        }
    }
}

enum CardFieldID {
    static let name = "name"
    static let model = "model"
    static let tag = "tag"
    static let serial = "serial"
    static let status = "status"
    static let location = "location"
    static let assignedTo = "assignedTo"
    static let email = "email"
    static let jobTitle = "jobTitle"
    static let username = "username"
    static let manufacturer = "manufacturer"
    static let category = "category"
    static let expiration = "expiration"
    static let licensedTo = "licensedTo"
    static let licensedEmail = "licensedEmail"
    static let company = "company"
    static let supplier = "supplier"
    static let defaultLocation = "defaultLocation"
    static let notes = "notes"
    static let purchaseDate = "purchaseDate"
    static let purchaseCost = "purchaseCost"
    static let orderNumber = "orderNumber"
    static let bookValue = "bookValue"
    static let eolDate = "eolDate"
    static let warrantyExpires = "warrantyExpires"
    static let warrantyMonths = "warrantyMonths"
    static let lastAudit = "lastAudit"
    static let nextAudit = "nextAudit"
    static let expectedCheckin = "expectedCheckin"
    static let lastCheckout = "lastCheckout"
    static let lastCheckin = "lastCheckin"
    static let modelNumber = "modelNumber"
    static let firstName = "firstName"
    static let lastName = "lastName"
    static let phone = "phone"
    static let employeeNumber = "employeeNumber"
    static let groups = "groups"
    static let itemNo = "itemNo"
    static let reassignable = "reassignable"
    static let maintained = "maintained"
    static let productKey = "productKey"
    static let none = ""
}

struct CardSlotLayout: Codable, Equatable {
    var title: String
    var subtitle: String?
    var details: [String]?
    var meta: [String]?
    var icons: [String: String]?

    static func `default`(for kind: CardKind) -> CardSlotLayout {
        CardKindSpec.spec(for: kind).defaultLayout
    }

    var isLegacy: Bool { details == nil && meta == nil }

    func resolved(against spec: CardKindSpec) -> CardSlotLayout {
        let filled: CardSlotLayout
        if !isLegacy {
            filled = CardSlotLayout(
                title: title,
                subtitle: subtitle,
                details: details ?? [],
                meta: meta ?? [],
                icons: icons
            )
        } else {
            var used: [String] = [title]
            var detailIDs: [String] = []
            if let subtitle, !subtitle.isEmpty {
                detailIDs.append(subtitle)
                used.append(subtitle)
            }
            if let defaultSubtitle = spec.defaultSubtitle, !used.contains(defaultSubtitle) {
                detailIDs.append(defaultSubtitle)
                used.append(defaultSubtitle)
            }
            for id in spec.headerFields where !used.contains(id) {
                detailIDs.append(id)
                used.append(id)
            }
            var metaIDs: [String] = []
            if !used.contains(spec.defaultTitle) {
                metaIDs.append(spec.defaultTitle)
                used.append(spec.defaultTitle)
            }
            for id in spec.metaFields where !used.contains(id) {
                metaIDs.append(id)
            }
            filled = CardSlotLayout(
                title: title,
                subtitle: subtitle,
                details: detailIDs,
                meta: metaIDs,
                icons: icons
            )
        }
        return filled.foldingSubtitleIntoDetails()
    }

    private func foldingSubtitleIntoDetails() -> CardSlotLayout {
        guard let subtitle, !subtitle.isEmpty else {
            return CardSlotLayout(
                title: title,
                subtitle: nil,
                details: details ?? [],
                meta: meta ?? [],
                icons: icons
            )
        }
        var detailIDs = (details ?? []).filter { $0 != subtitle }
        if subtitle != title {
            detailIDs.insert(subtitle, at: 0)
        }
        return CardSlotLayout(
            title: title,
            subtitle: nil,
            details: detailIDs,
            meta: meta ?? [],
            icons: icons
        )
    }

    func matchesDefault(of spec: CardKindSpec) -> Bool {
        let current = resolved(against: spec)
        let expected = spec.defaultLayout
        let iconsMatch = (current.icons ?? [:]).isEmpty
            || current.icons?.allSatisfy { $0.value == CardKindSpec.icon(for: $0.key) } == true
        return current.title == expected.title
            && (current.details ?? []) == (expected.details ?? [])
            && (current.meta ?? []) == (expected.meta ?? [])
            && iconsMatch
    }

    func usedIDs() -> Set<String> {
        var ids: Set<String> = [title]
        if let subtitle, !subtitle.isEmpty { ids.insert(subtitle) }
        (details ?? []).forEach { ids.insert($0) }
        (meta ?? []).forEach { ids.insert($0) }
        return ids
    }

    func unusedFields(in spec: CardKindSpec) -> [String] {
        let used = usedIDs()
        return spec.fields.filter { !used.contains($0) }
    }

    func removing(_ id: String, clearingTitle: Bool = false) -> CardSlotLayout {
        var next = self
        if clearingTitle, next.title == id {
            next.title = ""
        }
        if next.subtitle == id { next.subtitle = nil }
        next.details = (next.details ?? []).filter { $0 != id }
        next.meta = (next.meta ?? []).filter { $0 != id }
        return next
    }

    func placingTitle(_ id: String) -> CardSlotLayout {
        moving(id, to: .title)
    }

    func placingSubtitle(_ id: String?) -> CardSlotLayout {
        var next = self
        if let id, !id.isEmpty {
            next = next.removing(id)
            next.subtitle = id
        } else {
            next.subtitle = nil
        }
        return next
    }

    func replacingDetail(at index: Int, with id: String) -> CardSlotLayout {
        moving(id, to: .detail(index))
    }

    func replacingMeta(at index: Int, with id: String) -> CardSlotLayout {
        moving(id, to: .meta(index))
    }

    private enum Occupancy: Equatable {
        case title
        case detail(Int)
        case meta(Int)
    }

    private func occupancy(of id: String) -> Occupancy? {
        if title == id { return .title }
        if let index = details?.firstIndex(of: id) { return .detail(index) }
        if let index = meta?.firstIndex(of: id) { return .meta(index) }
        return nil
    }

    private func setting(_ id: String, at slot: Occupancy) -> CardSlotLayout {
        var next = self
        switch slot {
        case .title:
            next.title = id
        case .detail(let index):
            var items = next.details ?? []
            if items.indices.contains(index) { items[index] = id }
            next.details = items
        case .meta(let index):
            var items = next.meta ?? []
            if items.indices.contains(index) { items[index] = id }
            next.meta = items
        }
        return next
    }

    private func moving(_ id: String, to dest: Occupancy) -> CardSlotLayout {
        let displaced: String
        switch dest {
        case .title: displaced = title
        case .detail(let index): displaced = details?[index] ?? ""
        case .meta(let index): displaced = meta?[index] ?? ""
        }
        if displaced == id { return self }
        let origin = occupancy(of: id)
        var next = setting(id, at: dest)
        if let origin, !displaced.isEmpty {
            next = next.setting(displaced, at: origin)
        }
        return next
    }

    func appendingDetail(_ id: String) -> CardSlotLayout {
        var next = removing(id)
        var items = next.details ?? []
        guard items.count < CardKindSpec.maxDetailLines else { return self }
        items.append(id)
        next.details = items
        return next
    }

    func appendingMeta(_ id: String) -> CardSlotLayout {
        var next = removing(id)
        var items = next.meta ?? []
        items.append(id)
        next.meta = items
        return next
    }

    func removingDetail(at index: Int) -> CardSlotLayout {
        var next = self
        var items = next.details ?? []
        guard items.indices.contains(index) else { return next }
        items.remove(at: index)
        next.details = items
        return next
    }

    func removingMeta(at index: Int) -> CardSlotLayout {
        var next = self
        var items = next.meta ?? []
        guard items.indices.contains(index) else { return next }
        items.remove(at: index)
        next.meta = items
        return next
    }

    func icon(for fieldID: String) -> String {
        icons?[fieldID] ?? CardKindSpec.icon(for: fieldID)
    }

    func settingIcon(_ icon: String, for fieldID: String) -> CardSlotLayout {
        var next = self
        var map = next.icons ?? [:]
        if icon == CardKindSpec.icon(for: fieldID) {
            map.removeValue(forKey: fieldID)
        } else {
            map[fieldID] = icon
        }
        next.icons = map.isEmpty ? nil : map
        return next
    }
}

enum CardIcon {
    static let all: [String] = [
        "tag", "barcode", "model", "serial", "status", "location",
        "person", "email", "job", "username", "manufacturer",
        "category", "calendar", "info", "number", "pin", "phone"
    ]

    static func systemName(_ id: String) -> String {
        switch id {
        case "tag": return "tag"
        case "barcode": return "barcode"
        case "model": return "laptopcomputer"
        case "serial", "number": return "number"
        case "status": return "circle.lefthalf.filled"
        case "location": return "mappin.circle"
        case "person": return "person.circle"
        case "email": return "envelope"
        case "job": return "briefcase"
        case "username": return "at"
        case "manufacturer": return "building.2"
        case "category": return "square.grid.2x2"
        case "calendar": return "calendar"
        case "info": return "info.circle"
        case "pin": return "pin"
        case "phone": return "phone"
        default:
            return id.contains(".") ? id : "info.circle"
        }
    }

    static func labelKey(_ id: String) -> String {
        switch id {
        case "tag": return "name"
        case "barcode": return "asset_tag"
        case "model": return "model"
        case "serial": return "serial"
        case "status": return "status"
        case "location": return "location"
        case "person": return "assigned_to"
        case "email": return "email"
        case "job": return "job_title"
        case "username": return "username"
        case "manufacturer": return "manufacturer"
        case "category": return "category"
        case "calendar": return "expiration_date"
        case "info": return "card_icon_info"
        case "number": return "card_icon_number"
        case "pin": return "card_icon_pin"
        case "phone": return "phone"
        default: return id
        }
    }
}

struct CardFieldContent {
    let id: String
    let raw: String
    var formatted: String? = nil
    var icon: String = "info"

    static func value(_ id: String, _ raw: String, formatted: String? = nil) -> CardFieldContent {
        CardFieldContent(id: id, raw: raw, formatted: formatted, icon: CardKindSpec.icon(for: id))
    }

    static func labeled(_ id: String, _ raw: String) -> CardFieldContent {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatted = trimmed.isEmpty ? nil : "\(L10n.string(CardKindSpec.labelKey(for: id))): \(trimmed)"
        return value(id, raw, formatted: formatted)
    }

    static func date(_ id: String, _ info: DateInfo?) -> CardFieldContent {
        let raw = {
            if let formatted = info?.formatted?.trimmingCharacters(in: .whitespacesAndNewlines), !formatted.isEmpty {
                return formatted
            }
            return info?.date ?? ""
        }()
        return labeled(id, raw)
    }

    static func yesNo(_ id: String, _ value: Bool?) -> CardFieldContent {
        guard let value else { return self.value(id, "") }
        return labeled(id, L10n.string(value ? "yes" : "no"))
    }
}

struct ResolvedCardMeta: Equatable {
    let icon: String
    let text: String
}

struct ResolvedCardLayout: Equatable {
    let title: String
    let subtitle: String?
    let headerLines: [String]
    let meta: [ResolvedCardMeta]
}

struct CardKindSpec {
    static let maxDetailLines = 3

    let kind: CardKind
    let fields: [String]
    let defaultTitle: String
    let defaultSubtitle: String?
    let headerFields: [String]
    let metaFields: [String]
    let titleFallbacks: [String]

    var defaultLayout: CardSlotLayout {
        var detailIDs = headerFields
        if let defaultSubtitle, !defaultSubtitle.isEmpty, !detailIDs.contains(defaultSubtitle) {
            detailIDs.insert(defaultSubtitle, at: 0)
        }
        if detailIDs.count > Self.maxDetailLines {
            detailIDs = Array(detailIDs.prefix(Self.maxDetailLines))
        }
        return CardSlotLayout(
            title: defaultTitle,
            subtitle: nil,
            details: detailIDs,
            meta: metaFields
        )
    }

    static func spec(for kind: CardKind) -> CardKindSpec {
        switch kind {
        case .asset:
            return CardKindSpec(
                kind: .asset,
                fields: [
                    CardFieldID.model, CardFieldID.name, CardFieldID.tag, CardFieldID.serial, CardFieldID.status,
                    CardFieldID.location, CardFieldID.defaultLocation, CardFieldID.assignedTo, CardFieldID.manufacturer,
                    CardFieldID.category, CardFieldID.supplier, CardFieldID.company, CardFieldID.modelNumber,
                    CardFieldID.purchaseDate, CardFieldID.purchaseCost, CardFieldID.orderNumber, CardFieldID.bookValue,
                    CardFieldID.eolDate, CardFieldID.warrantyExpires, CardFieldID.warrantyMonths,
                    CardFieldID.lastAudit, CardFieldID.nextAudit, CardFieldID.expectedCheckin,
                    CardFieldID.lastCheckout, CardFieldID.lastCheckin, CardFieldID.notes
                ],
                defaultTitle: CardFieldID.model,
                defaultSubtitle: CardFieldID.tag,
                headerFields: [CardFieldID.serial, CardFieldID.status],
                metaFields: [CardFieldID.name, CardFieldID.location],
                titleFallbacks: [CardFieldID.model, CardFieldID.name, CardFieldID.tag]
            )
        case .user:
            return CardKindSpec(
                kind: .user,
                fields: [
                    CardFieldID.name, CardFieldID.firstName, CardFieldID.lastName, CardFieldID.username,
                    CardFieldID.email, CardFieldID.phone, CardFieldID.jobTitle, CardFieldID.employeeNumber,
                    CardFieldID.company, CardFieldID.location, CardFieldID.status, CardFieldID.groups, CardFieldID.notes
                ],
                defaultTitle: CardFieldID.name,
                defaultSubtitle: CardFieldID.email,
                headerFields: [],
                metaFields: [CardFieldID.jobTitle, CardFieldID.location],
                titleFallbacks: [CardFieldID.name, CardFieldID.username, CardFieldID.email]
            )
        case .accessory:
            return CardKindSpec(
                kind: .accessory,
                fields: [
                    CardFieldID.name, CardFieldID.tag, CardFieldID.modelNumber, CardFieldID.status,
                    CardFieldID.manufacturer, CardFieldID.category, CardFieldID.supplier, CardFieldID.company,
                    CardFieldID.assignedTo, CardFieldID.location, CardFieldID.purchaseDate, CardFieldID.purchaseCost,
                    CardFieldID.orderNumber, CardFieldID.notes
                ],
                defaultTitle: CardFieldID.name,
                defaultSubtitle: CardFieldID.tag,
                headerFields: [CardFieldID.manufacturer],
                metaFields: [CardFieldID.assignedTo, CardFieldID.location],
                titleFallbacks: [CardFieldID.name, CardFieldID.tag]
            )
        case .license:
            return CardKindSpec(
                kind: .license,
                fields: [
                    CardFieldID.name, CardFieldID.manufacturer, CardFieldID.category, CardFieldID.productKey,
                    CardFieldID.expiration, CardFieldID.licensedTo, CardFieldID.licensedEmail, CardFieldID.purchaseDate,
                    CardFieldID.purchaseCost, CardFieldID.orderNumber, CardFieldID.supplier, CardFieldID.company,
                    CardFieldID.reassignable, CardFieldID.maintained, CardFieldID.notes
                ],
                defaultTitle: CardFieldID.name,
                defaultSubtitle: CardFieldID.manufacturer,
                headerFields: [CardFieldID.expiration],
                metaFields: [CardFieldID.licensedTo, CardFieldID.licensedEmail],
                titleFallbacks: [CardFieldID.name, CardFieldID.licensedTo]
            )
        case .consumable:
            return CardKindSpec(
                kind: .consumable,
                fields: [
                    CardFieldID.name, CardFieldID.itemNo, CardFieldID.modelNumber, CardFieldID.category,
                    CardFieldID.manufacturer, CardFieldID.supplier, CardFieldID.company, CardFieldID.location,
                    CardFieldID.purchaseDate, CardFieldID.purchaseCost, CardFieldID.orderNumber, CardFieldID.notes
                ],
                defaultTitle: CardFieldID.name,
                defaultSubtitle: CardFieldID.category,
                headerFields: [CardFieldID.manufacturer],
                metaFields: [CardFieldID.location],
                titleFallbacks: [CardFieldID.name]
            )
        case .component:
            return CardKindSpec(
                kind: .component,
                fields: [
                    CardFieldID.name, CardFieldID.serial, CardFieldID.modelNumber, CardFieldID.category,
                    CardFieldID.manufacturer, CardFieldID.supplier, CardFieldID.company, CardFieldID.location,
                    CardFieldID.purchaseDate, CardFieldID.purchaseCost, CardFieldID.orderNumber, CardFieldID.notes
                ],
                defaultTitle: CardFieldID.name,
                defaultSubtitle: CardFieldID.category,
                headerFields: [CardFieldID.manufacturer],
                metaFields: [CardFieldID.location],
                titleFallbacks: [CardFieldID.name]
            )
        }
    }

    static func labelKey(for fieldID: String) -> String {
        switch fieldID {
        case CardFieldID.name: return "name"
        case CardFieldID.model: return "model"
        case CardFieldID.tag: return "asset_tag"
        case CardFieldID.serial: return "serial"
        case CardFieldID.status: return "status"
        case CardFieldID.location: return "location"
        case CardFieldID.assignedTo: return "assigned_to"
        case CardFieldID.email: return "email"
        case CardFieldID.jobTitle: return "job_title"
        case CardFieldID.username: return "username"
        case CardFieldID.manufacturer: return "manufacturer"
        case CardFieldID.category: return "category"
        case CardFieldID.expiration: return "expiration_date"
        case CardFieldID.licensedTo: return "licensed_to"
        case CardFieldID.licensedEmail: return "email"
        case CardFieldID.company: return "company"
        case CardFieldID.supplier: return "supplier"
        case CardFieldID.defaultLocation: return "default_location"
        case CardFieldID.notes: return "notes"
        case CardFieldID.purchaseDate: return "purchase_date"
        case CardFieldID.purchaseCost: return "purchase_cost"
        case CardFieldID.orderNumber: return "order_number"
        case CardFieldID.bookValue: return "book_value"
        case CardFieldID.eolDate: return "eol_date"
        case CardFieldID.warrantyExpires: return "warranty_expires"
        case CardFieldID.warrantyMonths: return "warranty_months"
        case CardFieldID.lastAudit: return "last_audit_date"
        case CardFieldID.nextAudit: return "next_audit_date"
        case CardFieldID.expectedCheckin: return "expected_checkin"
        case CardFieldID.lastCheckout: return "last_checkout"
        case CardFieldID.lastCheckin: return "last_checkin"
        case CardFieldID.modelNumber: return "model_number"
        case CardFieldID.firstName: return "first_name"
        case CardFieldID.lastName: return "last_name"
        case CardFieldID.phone: return "phone"
        case CardFieldID.employeeNumber: return "employee_number"
        case CardFieldID.groups: return "groups"
        case CardFieldID.itemNo: return "item_no"
        case CardFieldID.reassignable: return "reassignable"
        case CardFieldID.maintained: return "maintained"
        case CardFieldID.productKey: return "product_key"
        default: return fieldID
        }
    }

    static func icon(for fieldID: String) -> String {
        switch fieldID {
        case CardFieldID.name: return "tag"
        case CardFieldID.model: return "model"
        case CardFieldID.tag: return "barcode"
        case CardFieldID.serial: return "serial"
        case CardFieldID.status: return "status"
        case CardFieldID.location: return "location"
        case CardFieldID.assignedTo, CardFieldID.licensedTo: return "person"
        case CardFieldID.email, CardFieldID.licensedEmail: return "email"
        case CardFieldID.jobTitle: return "job"
        case CardFieldID.username: return "username"
        case CardFieldID.manufacturer: return "manufacturer"
        case CardFieldID.category: return "category"
        case CardFieldID.expiration: return "calendar"
        case CardFieldID.company: return "manufacturer"
        case CardFieldID.supplier: return "manufacturer"
        case CardFieldID.defaultLocation: return "location"
        case CardFieldID.notes: return "info"
        case CardFieldID.purchaseDate, CardFieldID.eolDate, CardFieldID.warrantyExpires,
             CardFieldID.lastAudit, CardFieldID.nextAudit, CardFieldID.expectedCheckin,
             CardFieldID.lastCheckout, CardFieldID.lastCheckin: return "calendar"
        case CardFieldID.purchaseCost, CardFieldID.bookValue, CardFieldID.orderNumber,
             CardFieldID.warrantyMonths, CardFieldID.employeeNumber: return "number"
        case CardFieldID.modelNumber, CardFieldID.itemNo, CardFieldID.productKey: return "serial"
        case CardFieldID.firstName, CardFieldID.lastName, CardFieldID.groups: return "person"
        case CardFieldID.phone: return "phone"
        case CardFieldID.reassignable, CardFieldID.maintained: return "status"
        default: return "info"
        }
    }
}

enum CardLayoutResolver {
    static func resolve(
        kind: CardKind,
        layout: CardSlotLayout,
        fields: [CardFieldContent]
    ) -> ResolvedCardLayout {
        let spec = CardKindSpec.spec(for: kind)
        let byID = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0) })

        func trimmed(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func raw(_ id: String) -> String { trimmed(byID[id]?.raw) }
        func display(_ id: String) -> String {
            let formatted = trimmed(byID[id]?.formatted)
            return formatted.isEmpty ? raw(id) : formatted
        }
        func icon(_ id: String) -> String {
            layout.icons?[id] ?? byID[id]?.icon ?? CardKindSpec.icon(for: id)
        }

        var titleID = layout.title
        var titleText = raw(titleID)
        if titleText.isEmpty {
            for id in spec.titleFallbacks + spec.fields {
                let candidate = raw(id)
                if !candidate.isEmpty {
                    titleID = id
                    titleText = candidate
                    break
                }
            }
        }

        var used: Set<String> = titleText.isEmpty ? [] : [titleID]

        let explicit = !layout.isLegacy
        var detailIDs = explicit ? (layout.details ?? []) : {
            var ids: [String] = []
            if let defaultSubtitle = spec.defaultSubtitle, !used.contains(defaultSubtitle) {
                ids.append(defaultSubtitle)
            }
            ids.append(contentsOf: spec.headerFields.filter { !used.contains($0) && !ids.contains($0) })
            return ids
        }()
        if let subtitleID = layout.subtitle, !subtitleID.isEmpty, subtitleID != titleID, !detailIDs.contains(subtitleID) {
            detailIDs.insert(subtitleID, at: 0)
        }
        let metaIDs = explicit ? (layout.meta ?? []) : {
            var ids: [String] = []
            if !used.contains(spec.defaultTitle) {
                ids.append(spec.defaultTitle)
            }
            ids.append(contentsOf: spec.metaFields.filter { !used.contains($0) && !ids.contains($0) })
            return ids
        }()

        var headerLines: [String] = []
        for id in detailIDs where !used.contains(id) {
            let text = display(id)
            if !text.isEmpty, text != titleText {
                headerLines.append(text)
                used.insert(id)
            }
        }

        var meta: [ResolvedCardMeta] = []
        for id in metaIDs where !used.contains(id) {
            let text = display(id)
            if !text.isEmpty, text != titleText {
                meta.append(ResolvedCardMeta(icon: icon(id), text: text))
                used.insert(id)
            }
        }

        return ResolvedCardLayout(
            title: titleText,
            subtitle: nil,
            headerLines: headerLines,
            meta: meta
        )
    }
}

struct CardLayoutStore: Equatable {
    var layouts: [String: CardSlotLayout]

    static let empty = CardLayoutStore(layouts: [:])

    func layout(for kind: CardKind) -> CardSlotLayout {
        layouts[kind.rawValue] ?? CardSlotLayout.default(for: kind)
    }

    func replacing(_ kind: CardKind, with layout: CardSlotLayout) -> CardLayoutStore {
        var next = layouts
        let spec = CardKindSpec.spec(for: kind)
        if layout.matchesDefault(of: spec) {
            next.removeValue(forKey: kind.rawValue)
        } else {
            next[kind.rawValue] = layout
        }
        return CardLayoutStore(layouts: next)
    }

    static func decode(_ json: String, preferAssetNameInLists: Bool) -> CardLayoutStore {
        var store = CardLayoutStore(layouts: [:])
        if let data = json.data(using: .utf8), !json.isEmpty,
           let decoded = try? JSONDecoder().decode([String: CardSlotLayout].self, from: data) {
            store.layouts = decoded
        }
        if store.layouts["asset"] == nil, preferAssetNameInLists {
            store.layouts["asset"] = CardSlotLayout(title: CardFieldID.name, subtitle: CardFieldID.tag)
        }
        return store
    }

    func encodeJSON() -> String {
        guard !layouts.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(layouts),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}

private struct CardLayoutStoreKey: EnvironmentKey {
    static let defaultValue = CardLayoutStore.empty
}

extension EnvironmentValues {
    var cardLayouts: CardLayoutStore {
        get { self[CardLayoutStoreKey.self] }
        set { self[CardLayoutStoreKey.self] = newValue }
    }
}

struct CardLayoutEnvironment: ViewModifier {
    @AppStorage("cardLayoutsJSON") private var cardLayoutsJSON = ""
    @AppStorage("preferAssetNameInLists") private var preferAssetNameInLists = false

    func body(content: Content) -> some View {
        content.environment(
            \.cardLayouts,
            CardLayoutStore.decode(cardLayoutsJSON, preferAssetNameInLists: preferAssetNameInLists)
        )
    }
}

struct CardLayoutHeader: View {
    let resolved: ResolvedCardLayout
    var extraLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !resolved.title.isEmpty {
                Text(resolved.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            if let subtitle = resolved.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            ForEach(Array(resolved.headerLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            ForEach(Array(extraLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct CardLayoutMeta: View {
    let items: [ResolvedCardMeta]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: CardIcon.systemName(item.icon))
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Text(item.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }
}

enum AssetCardFields {
    static func contents(for asset: Asset, locationName: String?, status: String?) -> [CardFieldContent] {
        [
            .value(CardFieldID.model, asset.decodedModelName),
            .value(CardFieldID.name, asset.decodedName),
            .value(
                CardFieldID.tag,
                asset.decodedAssetTag,
                formatted: asset.decodedAssetTag.isEmpty ? nil : L10n.string("tag_label", asset.decodedAssetTag)
            ),
            .value(
                CardFieldID.serial,
                asset.decodedSerial,
                formatted: asset.decodedSerial.isEmpty ? nil : "\(L10n.string("sn_label")) \(asset.decodedSerial)"
            ),
            .value(CardFieldID.status, status ?? ""),
            .value(CardFieldID.location, locationName ?? ""),
            .labeled(CardFieldID.defaultLocation, HTMLDecoder.decode(asset.rtdLocation?.name ?? "")),
            .value(CardFieldID.assignedTo, asset.decodedAssignedToName),
            .value(CardFieldID.manufacturer, asset.decodedManufacturerName),
            .value(CardFieldID.category, asset.decodedCategoryName),
            .value(CardFieldID.supplier, asset.decodedSupplierName),
            .value(CardFieldID.company, asset.decodedCompanyName),
            .labeled(CardFieldID.modelNumber, asset.modelNumber ?? ""),
            .date(CardFieldID.purchaseDate, asset.purchaseDate),
            .labeled(CardFieldID.purchaseCost, asset.purchaseCost ?? ""),
            .labeled(CardFieldID.orderNumber, asset.orderNumber ?? ""),
            .labeled(CardFieldID.bookValue, asset.bookValue ?? ""),
            .date(CardFieldID.eolDate, asset.assetEolDate),
            .date(CardFieldID.warrantyExpires, asset.warrantyExpires),
            .labeled(CardFieldID.warrantyMonths, asset.decodedWarrantyMonths),
            .date(CardFieldID.lastAudit, asset.lastAuditDate),
            .date(CardFieldID.nextAudit, asset.nextAuditDate),
            .date(CardFieldID.expectedCheckin, asset.expectedCheckin),
            .date(CardFieldID.lastCheckout, asset.lastCheckout),
            .date(CardFieldID.lastCheckin, asset.lastCheckin),
            .labeled(CardFieldID.notes, asset.decodedNotes)
        ]
    }

    static func resolve(_ asset: Asset, layouts: CardLayoutStore, locationName: String?, status: String?) -> ResolvedCardLayout {
        CardLayoutResolver.resolve(
            kind: .asset,
            layout: layouts.layout(for: .asset),
            fields: contents(for: asset, locationName: locationName, status: status)
        )
    }
}

enum CardLayoutPreview {
    static func fields(for kind: CardKind) -> [CardFieldContent] {
        switch kind {
        case .asset:
            return [
                .value(CardFieldID.model, "MacBook Pro"),
                .value(CardFieldID.name, "MacBook Pro 16\""),
                .value(CardFieldID.tag, "MBP-1042", formatted: L10n.string("tag_label", "MBP-1042")),
                .value(CardFieldID.serial, "C02YV1ABJGH6", formatted: "\(L10n.string("sn_label")) C02YV1ABJGH6"),
                .value(CardFieldID.status, L10n.string("status_ready_to_deploy")),
                .value(CardFieldID.location, "Brussels"),
                .labeled(CardFieldID.defaultLocation, "Brussels"),
                .value(CardFieldID.assignedTo, "John Doe"),
                .value(CardFieldID.manufacturer, "Apple"),
                .value(CardFieldID.category, "Laptops"),
                .value(CardFieldID.supplier, "Amazon"),
                .value(CardFieldID.company, "Acme"),
                .labeled(CardFieldID.modelNumber, "A2991"),
                .labeled(CardFieldID.purchaseDate, "12 Jan 2024"),
                .labeled(CardFieldID.purchaseCost, "2.499"),
                .labeled(CardFieldID.orderNumber, "PO-1042"),
                .labeled(CardFieldID.bookValue, "1.890"),
                .labeled(CardFieldID.eolDate, "12 Jan 2028"),
                .labeled(CardFieldID.warrantyExpires, "12 Jan 2027"),
                .labeled(CardFieldID.warrantyMonths, "36"),
                .labeled(CardFieldID.lastAudit, "1 Sep 2026"),
                .labeled(CardFieldID.nextAudit, "1 Sep 2027"),
                .labeled(CardFieldID.expectedCheckin, "30 Sep 2026"),
                .labeled(CardFieldID.lastCheckout, "1 Mar 2026"),
                .labeled(CardFieldID.lastCheckin, "12 Feb 2026"),
                .labeled(CardFieldID.notes, "Company laptop")
            ]
        case .user:
            return [
                .value(CardFieldID.name, "John Doe"),
                .value(CardFieldID.firstName, "John"),
                .value(CardFieldID.lastName, "Doe"),
                .value(CardFieldID.email, "john.doe@example.com"),
                .value(CardFieldID.username, "jdoe"),
                .labeled(CardFieldID.phone, "+31 6 1234 5678"),
                .value(CardFieldID.jobTitle, "Designer"),
                .labeled(CardFieldID.employeeNumber, "E-204"),
                .value(CardFieldID.company, "Acme"),
                .value(CardFieldID.location, "Brussels"),
                .value(CardFieldID.status, L10n.string("activated")),
                .labeled(CardFieldID.groups, "Design"),
                .labeled(CardFieldID.notes, "MacBook assigned")
            ]
        case .accessory:
            return [
                .value(CardFieldID.name, "Magic Keyboard"),
                .value(CardFieldID.tag, "ACC-204", formatted: L10n.string("tag_label", "ACC-204")),
                .labeled(CardFieldID.modelNumber, "A1843"),
                .value(CardFieldID.status, L10n.string("status_ready_to_deploy")),
                .value(CardFieldID.manufacturer, "Apple"),
                .value(CardFieldID.category, "Keyboards"),
                .value(CardFieldID.supplier, "Amazon"),
                .value(CardFieldID.company, "Acme"),
                .value(CardFieldID.assignedTo, "John Doe"),
                .value(CardFieldID.location, "Brussels"),
                .labeled(CardFieldID.purchaseDate, "12 Jan 2024"),
                .labeled(CardFieldID.purchaseCost, "149"),
                .labeled(CardFieldID.orderNumber, "PO-204"),
                .labeled(CardFieldID.notes, "With numeric keypad")
            ]
        case .license:
            return [
                .value(CardFieldID.name, "Adobe Photoshop"),
                .value(CardFieldID.manufacturer, "Adobe"),
                .value(CardFieldID.category, "Software"),
                .labeled(CardFieldID.productKey, "1234-5678-90AB"),
                .value(CardFieldID.expiration, "31 Dec 2026", formatted: L10n.string("expires_value", "31 Dec 2026")),
                .value(CardFieldID.licensedTo, "John Doe"),
                .value(CardFieldID.licensedEmail, "john.doe@example.com"),
                .labeled(CardFieldID.purchaseDate, "1 Jan 2024"),
                .labeled(CardFieldID.purchaseCost, "263"),
                .labeled(CardFieldID.orderNumber, "PO-PS1"),
                .value(CardFieldID.supplier, "Amazon"),
                .value(CardFieldID.company, "Acme"),
                .yesNo(CardFieldID.reassignable, true),
                .yesNo(CardFieldID.maintained, true),
                .labeled(CardFieldID.notes, "Creative Cloud")
            ]
        case .consumable:
            return [
                .value(CardFieldID.name, "HP 205A Black Toner"),
                .labeled(CardFieldID.itemNo, "CF530A"),
                .labeled(CardFieldID.modelNumber, "LaserJet Pro M180"),
                .value(CardFieldID.category, "Printer supplies"),
                .value(CardFieldID.manufacturer, "HP"),
                .value(CardFieldID.supplier, "Amazon"),
                .value(CardFieldID.company, "Acme"),
                .value(CardFieldID.location, "Brussels"),
                .labeled(CardFieldID.purchaseDate, "12 Jan 2024"),
                .labeled(CardFieldID.purchaseCost, "89"),
                .labeled(CardFieldID.orderNumber, "PO-TNR"),
                .labeled(CardFieldID.notes, "Black")
            ]
        case .component:
            return [
                .value(CardFieldID.name, "Samsung 980 PRO 1TB"),
                .labeled(CardFieldID.serial, "S6B0NS0R123456"),
                .labeled(CardFieldID.modelNumber, "MZ-V8P1T0"),
                .value(CardFieldID.category, "Storage"),
                .value(CardFieldID.manufacturer, "Samsung"),
                .value(CardFieldID.supplier, "Amazon"),
                .value(CardFieldID.company, "Acme"),
                .value(CardFieldID.location, "Brussels"),
                .labeled(CardFieldID.purchaseDate, "12 Jan 2024"),
                .labeled(CardFieldID.purchaseCost, "129"),
                .labeled(CardFieldID.orderNumber, "PO-SSD"),
                .labeled(CardFieldID.notes, "NVMe SSD")
            ]
        }
    }
}

struct CardLayoutPreviewCard: View {
    let kind: CardKind
    let layout: CardSlotLayout

    var body: some View {
        let resolved = CardLayoutResolver.resolve(
            kind: kind,
            layout: layout,
            fields: CardLayoutPreview.fields(for: kind)
        )
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: kind.settingsIcon)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                CardLayoutHeader(resolved: resolved)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CardLayoutMeta(items: resolved.meta)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.primary.opacity(0.08), radius: 8, y: 2)
        }
    }
}
