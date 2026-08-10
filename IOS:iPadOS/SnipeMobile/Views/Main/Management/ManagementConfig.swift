import SwiftUI

// MARK: - Raw value helpers

// Helpers for raw list-endpoint JSON rows.
enum ManagementValue {
    static func scalarString(_ any: Any?) -> String {
        switch any {
        case let s as String: return s
        case let i as Int: return String(i)
        case let b as Bool: return b ? "1" : "0"
        case let d as Double:
            if d == d.rounded() { return String(Int(d)) }
            return String(d)
        default: return ""
        }
    }

    /// User-facing text from raw API values (decodes `&quot;`, `&#039;`, etc.).
    static func displayString(_ any: Any?) -> String {
        HTMLDecoder.decode(scalarString(any))
    }

    // id from a nested object or a flat value
    static func nestedId(_ row: [String: Any], _ key: String) -> String {
        if let dict = row[key] as? [String: Any] {
            if let id = dict["id"] as? Int { return String(id) }
            if let id = dict["id"] as? String { return id }
        }
        if let id = row[key] as? Int { return String(id) }
        if let id = row[key] as? String { return id }
        return ""
    }

    // name from a nested object
    static func nestedName(_ row: [String: Any], _ key: String) -> String? {
        if let dict = row[key] as? [String: Any], let name = dict["name"] as? String, !name.isEmpty {
            return HTMLDecoder.decode(name)
        }
        return nil
    }

    static func boolString(_ any: Any?) -> String {
        switch any {
        case let b as Bool: return b ? "1" : "0"
        case let i as Int: return i == 1 ? "1" : "0"
        case let s as String:
            let lower = s.lowercased()
            return (lower == "true" || lower == "1") ? "1" : "0"
        default: return "0"
        }
    }
}

// MARK: - Picker option sources

struct ManagementOption: Identifiable, Hashable {
    // empty id == none
    let id: String
    let label: String
}

enum ManagementOptionSource {
    case categories(type: String?)
    case manufacturers
    case companies
    case locations
    case users
    case fieldsets
    case depreciations
    case statusType
    case categoryType
    case fieldElement
    case fieldFormat

    @MainActor
    func options(client: SnipeITAPIClient) -> [ManagementOption] {
        switch self {
        case .categories(let type):
            let rows = type.map { client.categories(for: $0) } ?? client.categories
            return rows.map { ManagementOption(id: String($0.id), label: HTMLDecoder.decode($0.name)) }
        case .manufacturers:
            return client.manufacturers.map { ManagementOption(id: String($0.id), label: HTMLDecoder.decode($0.name)) }
        case .companies:
            return client.companies.map { ManagementOption(id: String($0.id), label: HTMLDecoder.decode($0.name)) }
        case .locations:
            return client.locations.map { ManagementOption(id: String($0.id), label: $0.decodedName) }
        case .users:
            return client.users.map { ManagementOption(id: String($0.id), label: $0.decodedName) }
        case .fieldsets:
            return (client.fieldsets ?? []).map { ManagementOption(id: String($0.id), label: HTMLDecoder.decode($0.name)) }
        case .depreciations:
            return client.depreciations.map { ManagementOption(id: String($0.id), label: HTMLDecoder.decode($0.name)) }
        case .statusType:
            return ["deployable", "pending", "undeployable", "archived"]
                .map { ManagementOption(id: $0, label: L10n.string("status_type_\($0)")) }
        case .categoryType:
            return ["asset", "accessory", "consumable", "component", "license"]
                .map { ManagementOption(id: $0, label: L10n.string("category_type_\($0)")) }
        case .fieldElement:
            return ["text", "textarea", "markdown-textarea", "listbox", "checkbox", "radio"]
                .map { ManagementOption(id: $0, label: ManagementOptionSource.fieldElementLabel($0)) }
        case .fieldFormat:
            // Friendly keys accepted by Snipe-IT's CustomField::PREDEFINED_FORMATS.
            return ["ANY", ManagementOptionSource.customRegexFormat, "ALPHA", "ALPHA-DASH",
                    "NUMERIC", "ALPHA-NUMERIC", "EMAIL", "DATE", "URL", "IP", "IPV4", "IPV6", "MAC", "BOOLEAN"]
                .map { ManagementOption(id: $0, label: $0) }
        }
    }

    // Sentinel matching Snipe-IT's "CUSTOM REGEX" format option.
    static let customRegexFormat = "CUSTOM REGEX"

    var isFieldFormat: Bool {
        if case .fieldFormat = self { return true }
        return false
    }

    static func fieldElementLabel(_ id: String) -> String {
        id == "markdown-textarea" ? "Markdown" : id.capitalized
    }

    /// Management entity that can be created inline from this picker, if any.
    var creatableEntity: ManagementEntity? {
        switch self {
        case .categories: return .categories
        case .manufacturers: return .manufacturers
        case .companies: return .companies
        case .locations: return nil
        case .fieldsets: return .fieldsets
        case .statusType, .categoryType, .fieldElement, .fieldFormat, .users, .depreciations:
            return nil
        }
    }

    /// Opens `AddLocationSheet` instead of a management form.
    var creatableLocation: Bool {
        if case .locations = self { return true }
        return false
    }

    /// Opens `AddUserSheet` instead of a management form.
    var creatableUser: Bool {
        if case .users = self { return true }
        return false
    }

    /// Default field values when creating a related item from this picker.
    func createDefaultValues() -> [String: String] {
        switch self {
        case .categories(let type):
            if let type { return ["category_type": type] }
            return [:]
        default:
            return [:]
        }
    }

    // load the list before the picker needs it
    @MainActor
    func ensureLoaded(client: SnipeITAPIClient) {
        switch self {
        case .categories:
            if client.categories.isEmpty { Task { await client.fetchCategories() } }
        case .manufacturers:
            if client.manufacturers.isEmpty { Task { await client.fetchManufacturers() } }
        case .companies:
            if client.companies.isEmpty { Task { await client.fetchCompanies() } }
        case .locations:
            if client.locations.isEmpty { Task { await client.fetchLocations() } }
        case .users:
            if client.users.isEmpty { Task { await client.fetchUsers() } }
        case .fieldsets:
            if client.fieldsets == nil { Task { await client.fetchFieldsets() } }
        case .depreciations:
            if client.depreciations.isEmpty { Task { await client.fetchDepreciations() } }
        default:
            break
        }
    }
}

// MARK: - Form fields

enum ManagementFieldKind {
    case text
    case url
    case email
    case phone
    case number
    case multiline
    case toggle
    case colorHex
    case picker(ManagementOptionSource)
}

struct ManagementFormField: Identifiable {
    let bodyKey: String
    let titleKey: String
    let kind: ManagementFieldKind
    var required: Bool = false
    // only shown when creating a new item
    var createOnly: Bool = false
    // value pre-selected when creating a new item
    var defaultValue: String? = nil
    // override for reading the current value when editing
    var rowValueReader: (([String: Any]) -> String)? = nil

    var id: String { bodyKey }

    func currentValue(from row: [String: Any]) -> String {
        let raw: String
        if let reader = rowValueReader { raw = reader(row) }
        else { raw = ManagementValue.scalarString(row[bodyKey]) }
        switch kind {
        case .text, .multiline, .url, .email, .phone:
            return HTMLDecoder.decode(raw)
        default:
            return raw
        }
    }

    var isToggle: Bool {
        if case .toggle = kind { return true }
        return false
    }

    var optionSource: ManagementOptionSource? {
        if case .picker(let source) = kind { return source }
        return nil
    }
}

// MARK: - Entity configuration

struct ManagementEntityConfig {
    let path: String
    // plural title for the list screen
    let titleKey: String
    // singular noun for "New X" / "Edit X"
    let singularKey: String
    let fields: [ManagementFormField]
    var titleReader: ([String: Any]) -> String = {
        let name = ManagementValue.displayString($0["name"])
        return name.isEmpty ? "—" : name
    }
    var subtitleReader: (([String: Any]) -> String?)? = nil

    var optionSources: [ManagementOptionSource] {
        fields.compactMap { $0.optionSource }
    }
}

// MARK: - Per-entity configuration

extension ManagementEntity {
    var config: ManagementEntityConfig {
        switch self {
        case .fields:
            return ManagementEntityConfig(
                path: "/api/v1/fields",
                titleKey: titleKey,
                singularKey: "mgmt_field_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "element", titleKey: "mgmt_element", kind: .picker(.fieldElement), required: true,
                                        defaultValue: "text",
                                        rowValueReader: { ManagementValue.scalarString($0["type"] ?? $0["element"]).lowercased() }),
                    ManagementFormField(bodyKey: "field_values", titleKey: "mgmt_field_values", kind: .multiline),
                    ManagementFormField(bodyKey: "format", titleKey: "mgmt_field_format", kind: .picker(.fieldFormat), required: true,
                                        defaultValue: "ANY",
                                        rowValueReader: { ManagementValue.scalarString($0["format"] ?? $0["field_format"]) }),
                    ManagementFormField(bodyKey: "help_text", titleKey: "mgmt_help_text", kind: .text),
                    ManagementFormField(bodyKey: "field_encrypted", titleKey: "mgmt_field_encrypted", kind: .toggle, createOnly: true,
                                        rowValueReader: { ManagementValue.boolString($0["field_encrypted"]) }),
                    ManagementFormField(bodyKey: "auto_add_to_fieldsets", titleKey: "mgmt_auto_add_to_fieldsets", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["auto_add_to_fieldsets"]) }),
                    ManagementFormField(bodyKey: "show_in_listview", titleKey: "mgmt_show_in_listview", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["show_in_listview"]) }),
                    ManagementFormField(bodyKey: "show_in_requestable_list", titleKey: "mgmt_show_in_requestable_list", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["show_in_requestable_list"]) }),
                    ManagementFormField(bodyKey: "show_in_email", titleKey: "mgmt_show_in_email", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["show_in_email"]) }),
                    ManagementFormField(bodyKey: "is_unique", titleKey: "mgmt_is_unique", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["is_unique"]) }),
                    ManagementFormField(bodyKey: "display_checkout", titleKey: "mgmt_display_checkout", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["display_checkout"]) }),
                    ManagementFormField(bodyKey: "display_checkin", titleKey: "mgmt_display_checkin", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["display_checkin"]) }),
                    ManagementFormField(bodyKey: "display_audit", titleKey: "mgmt_display_audit", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["display_audit"]) }),
                    ManagementFormField(bodyKey: "display_in_user_view", titleKey: "mgmt_display_in_user_view", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["display_in_user_view"]) })
                ],
                subtitleReader: { row in
                    let element = ManagementValue.scalarString(row["type"] ?? row["element"]).capitalized
                    return element.isEmpty ? nil : element
                }
            )

        case .fieldsets:
            return ManagementEntityConfig(
                path: "/api/v1/fieldsets",
                titleKey: titleKey,
                singularKey: "mgmt_fieldset_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true)
                ],
                subtitleReader: { row in
                    if let fields = row["fields"] as? [String: Any], let rows = fields["rows"] as? [[String: Any]] {
                        return L10n.string("mgmt_fieldset_field_count", rows.count)
                    }
                    return nil
                }
            )

        case .companies:
            return ManagementEntityConfig(
                path: "/api/v1/companies",
                titleKey: titleKey,
                singularKey: "mgmt_company_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "phone", titleKey: "phone", kind: .phone),
                    ManagementFormField(bodyKey: "fax", titleKey: "mgmt_fax", kind: .phone),
                    ManagementFormField(bodyKey: "email", titleKey: "email", kind: .email),
                    ManagementFormField(bodyKey: "notes", titleKey: "notes", kind: .multiline)
                ]
            )

        case .statusLabels:
            return ManagementEntityConfig(
                path: "/api/v1/statuslabels",
                titleKey: titleKey,
                singularKey: "mgmt_status_label_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "type", titleKey: "mgmt_status_type", kind: .picker(.statusType), required: true,
                                        defaultValue: "deployable",
                                        rowValueReader: { ManagementValue.scalarString($0["type"]).lowercased() }),
                    ManagementFormField(bodyKey: "color", titleKey: "mgmt_color", kind: .colorHex, defaultValue: "AA3399"),
                    ManagementFormField(bodyKey: "show_in_nav", titleKey: "mgmt_show_in_nav", kind: .toggle),
                    ManagementFormField(bodyKey: "default_label", titleKey: "mgmt_default_label", kind: .toggle),
                    ManagementFormField(bodyKey: "notes", titleKey: "notes", kind: .multiline)
                ],
                subtitleReader: { row in
                    let type = ManagementValue.scalarString(row["type"]).lowercased()
                    return type.isEmpty ? nil : L10n.string("status_type_\(type)")
                }
            )

        case .models:
            return ManagementEntityConfig(
                path: "/api/v1/models",
                titleKey: titleKey,
                singularKey: "mgmt_model_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "category_id", titleKey: "category", kind: .picker(.categories(type: "asset")), required: true,
                                        rowValueReader: { ManagementValue.nestedId($0, "category") }),
                    ManagementFormField(bodyKey: "manufacturer_id", titleKey: "manufacturer", kind: .picker(.manufacturers),
                                        rowValueReader: { ManagementValue.nestedId($0, "manufacturer") }),
                    ManagementFormField(bodyKey: "model_number", titleKey: "model_number", kind: .text),
                    ManagementFormField(bodyKey: "fieldset_id", titleKey: "mgmt_fieldset", kind: .picker(.fieldsets),
                                        rowValueReader: { ManagementValue.nestedId($0, "fieldset") }),
                    ManagementFormField(bodyKey: "depreciation_id", titleKey: "mgmt_depreciation", kind: .picker(.depreciations),
                                        rowValueReader: { ManagementValue.nestedId($0, "depreciation") }),
                    ManagementFormField(bodyKey: "eol", titleKey: "mgmt_eol", kind: .number),
                    ManagementFormField(bodyKey: "min_amt", titleKey: "mgmt_min_amt", kind: .number),
                    ManagementFormField(bodyKey: "requestable", titleKey: "mgmt_requestable", kind: .toggle),
                    ManagementFormField(bodyKey: "require_serial", titleKey: "mgmt_require_serial", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["require_serial"]) }),
                    ManagementFormField(bodyKey: "notes", titleKey: "notes", kind: .multiline)
                ],
                subtitleReader: { row in
                    let number = ManagementValue.displayString(row["model_number"])
                    if !number.isEmpty { return number }
                    return ManagementValue.nestedName(row, "category")
                }
            )

        case .categories:
            return ManagementEntityConfig(
                path: "/api/v1/categories",
                titleKey: titleKey,
                singularKey: "mgmt_category_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "category_type", titleKey: "mgmt_category_type", kind: .picker(.categoryType), required: true,
                                        rowValueReader: { ManagementValue.scalarString($0["category_type"]).lowercased() }),
                    ManagementFormField(bodyKey: "use_default_eula", titleKey: "mgmt_use_default_eula", kind: .toggle,
                                        rowValueReader: { ManagementValue.boolString($0["use_default_eula"]) }),
                    ManagementFormField(bodyKey: "eula_text", titleKey: "mgmt_eula_text", kind: .multiline),
                    ManagementFormField(bodyKey: "require_acceptance", titleKey: "mgmt_require_acceptance", kind: .toggle),
                    ManagementFormField(bodyKey: "checkin_email", titleKey: "mgmt_checkin_email", kind: .toggle)
                ],
                subtitleReader: { row in
                    let type = ManagementValue.scalarString(row["category_type"]).lowercased()
                    return type.isEmpty ? nil : L10n.string("category_type_\(type)")
                }
            )

        case .manufacturers:
            return ManagementEntityConfig(
                path: "/api/v1/manufacturers",
                titleKey: titleKey,
                singularKey: "mgmt_manufacturer_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "url", titleKey: "url", kind: .url),
                    ManagementFormField(bodyKey: "support_url", titleKey: "mgmt_support_url", kind: .url),
                    ManagementFormField(bodyKey: "support_phone", titleKey: "mgmt_support_phone", kind: .phone),
                    ManagementFormField(bodyKey: "support_email", titleKey: "mgmt_support_email", kind: .email),
                    ManagementFormField(bodyKey: "warranty_lookup_url", titleKey: "mgmt_warranty_lookup_url", kind: .url),
                    ManagementFormField(bodyKey: "notes", titleKey: "notes", kind: .multiline)
                ]
            )

        case .suppliers:
            return ManagementEntityConfig(
                path: "/api/v1/suppliers",
                titleKey: titleKey,
                singularKey: "mgmt_supplier_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "contact", titleKey: "mgmt_contact", kind: .text),
                    ManagementFormField(bodyKey: "address", titleKey: "address", kind: .text),
                    ManagementFormField(bodyKey: "address2", titleKey: "mgmt_address2", kind: .text),
                    ManagementFormField(bodyKey: "city", titleKey: "city", kind: .text),
                    ManagementFormField(bodyKey: "state", titleKey: "mgmt_state", kind: .text),
                    ManagementFormField(bodyKey: "country", titleKey: "mgmt_country", kind: .text),
                    ManagementFormField(bodyKey: "zip", titleKey: "mgmt_zip", kind: .text),
                    ManagementFormField(bodyKey: "phone", titleKey: "phone", kind: .phone),
                    ManagementFormField(bodyKey: "fax", titleKey: "mgmt_fax", kind: .phone),
                    ManagementFormField(bodyKey: "email", titleKey: "email", kind: .email),
                    ManagementFormField(bodyKey: "url", titleKey: "url", kind: .url),
                    ManagementFormField(bodyKey: "notes", titleKey: "notes", kind: .multiline)
                ],
                subtitleReader: { row in
                    let city = ManagementValue.displayString(row["city"])
                    return city.isEmpty ? nil : city
                }
            )

        case .departments:
            return ManagementEntityConfig(
                path: "/api/v1/departments",
                titleKey: titleKey,
                singularKey: "mgmt_department_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "company_id", titleKey: "company", kind: .picker(.companies),
                                        rowValueReader: { ManagementValue.nestedId($0, "company") }),
                    ManagementFormField(bodyKey: "location_id", titleKey: "location", kind: .picker(.locations),
                                        rowValueReader: { ManagementValue.nestedId($0, "location") }),
                    ManagementFormField(bodyKey: "manager_id", titleKey: "mgmt_manager", kind: .picker(.users),
                                        rowValueReader: { ManagementValue.nestedId($0, "manager") }),
                    ManagementFormField(bodyKey: "phone", titleKey: "phone", kind: .phone),
                    ManagementFormField(bodyKey: "fax", titleKey: "mgmt_fax", kind: .phone),
                    ManagementFormField(bodyKey: "notes", titleKey: "notes", kind: .multiline)
                ],
                subtitleReader: { row in ManagementValue.nestedName(row, "company") }
            )

        case .groups:
            return ManagementEntityConfig(
                path: "/api/v1/groups",
                titleKey: titleKey,
                singularKey: "mgmt_group_one",
                fields: [
                    ManagementFormField(bodyKey: "name", titleKey: "name", kind: .text, required: true),
                    ManagementFormField(bodyKey: "notes", titleKey: "notes", kind: .multiline)
                ],
                subtitleReader: { row in
                    if let count = row["users_count"] as? Int { return L10n.string("mgmt_group_user_count", count) }
                    return nil
                }
            )
        }
    }
}
