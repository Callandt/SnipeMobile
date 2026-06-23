import SwiftUI

// Create/edit form from entity field schema.
struct ManagementFormView: View {
    let entity: ManagementEntity
    @ObservedObject var apiClient: SnipeITAPIClient
    // nil == create
    let existing: ManagementItem?

    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]
    @State private var customRegex = ""
    @State private var isSaving = false
    @State private var resultMessage = ""
    @State private var showResult = false
    @State private var didSucceed = false

    private var customRegexSentinel: String { ManagementOptionSource.customRegexFormat }

    private var config: ManagementEntityConfig { entity.config }
    private var isEdit: Bool { existing != nil }

    private var navigationTitle: String {
        let noun = L10n.string(config.singularKey)
        return isEdit ? L10n.string("mgmt_edit_title", noun) : L10n.string("mgmt_new_title", noun)
    }

    private var visibleFields: [ManagementFormField] {
        config.fields.filter { !($0.createOnly && isEdit) }
    }

    private var canSave: Bool {
        for field in visibleFields where field.required {
            let value = (values[field.bodyKey] ?? "").trimmingCharacters(in: .whitespaces)
            if value.isEmpty { return false }
            if field.optionSource?.isFieldFormat == true,
               value == customRegexSentinel,
               customRegex.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(visibleFields) { field in
                    fieldRow(field)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task(id: existing?.id) { await loadFormValues() }
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok")) {
                    if didSucceed { dismiss() }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.string("cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button(L10n.string(isEdit ? "save" : "create")) {
                    Task { await save() }
                }
                .disabled(!canSave)
            }
        }
    }

    // MARK: - Field rendering

    @ViewBuilder
    private func fieldRow(_ field: ManagementFormField) -> some View {
        let label = L10n.fieldLabel(field.titleKey, required: field.required)
        switch field.kind {
        case .text:
            TextField(label, text: stringBinding(field.bodyKey))
        case .url:
            TextField(label, text: stringBinding(field.bodyKey))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        case .email:
            TextField(label, text: stringBinding(field.bodyKey))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        case .phone:
            TextField(label, text: stringBinding(field.bodyKey))
                .keyboardType(.phonePad)
        case .number:
            TextField(label, text: stringBinding(field.bodyKey))
                .keyboardType(.numberPad)
        case .multiline:
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(label, text: stringBinding(field.bodyKey), axis: .vertical)
                    .lineLimit(3...6)
            }
        case .toggle:
            Toggle(label, isOn: boolBinding(field.bodyKey))
        case .colorHex:
            HexColorRow(title: label, hex: stringBinding(field.bodyKey))
        case .picker(let source):
            AdaptivePickerRow(
                title: label,
                items: pickerItems(for: field, source: source),
                selection: stringBinding(field.bodyKey),
                emptyOption: (value: "", label: L10n.string("mgmt_none"))
            )
            if source.isFieldFormat, (values[field.bodyKey] ?? "") == customRegexSentinel {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("regex:/^[0-9]{15}$/", text: $customRegex)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text(L10n.string("mgmt_custom_regex_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // Keep the current value selectable while its list is still loading.
    private func pickerItems(for field: ManagementFormField, source: ManagementOptionSource) -> [(value: String, label: String)] {
        var options = source.options(client: apiClient)
        let current = values[field.bodyKey] ?? ""
        if !current.isEmpty, !options.contains(where: { $0.id == current }) {
            let nestedKey = field.bodyKey.hasSuffix("_id") ? String(field.bodyKey.dropLast(3)) : field.bodyKey
            let label = existing.flatMap { ManagementValue.nestedName($0.raw, nestedKey) } ?? current
            options.append(ManagementOption(id: current, label: label))
        }
        return options.map { (value: $0.id, label: $0.label) }
    }

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { values[key] == "1" || values[key]?.lowercased() == "true" },
            set: { values[key] = $0 ? "1" : "0" }
        )
    }

    // MARK: - Lifecycle

    private func loadFormValues() async {
        var row = existing?.raw
        if let existing {
            if let fresh = await apiClient.managementFetchRow(path: config.path, id: existing.id) {
                row = fresh
            }
        }

        var initial: [String: String] = [:]
        for field in config.fields {
            if let row {
                initial[field.bodyKey] = field.currentValue(from: row)
            } else if let defaultValue = field.defaultValue {
                initial[field.bodyKey] = defaultValue
            } else if field.isToggle {
                initial[field.bodyKey] = "0"
            }
        }
        if config.optionSources.contains(where: { $0.isFieldFormat }) {
            let format = initial["format"] ?? ""
            if format.lowercased().hasPrefix("regex:") {
                customRegex = format
                initial["format"] = customRegexSentinel
            }
        }
        values = initial

        for source in config.optionSources {
            source.ensureLoaded(client: apiClient)
        }
    }

    // MARK: - Save

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        var body: [String: Any] = [:]
        for field in visibleFields {
            let raw = (values[field.bodyKey] ?? "").trimmingCharacters(in: .whitespaces)
            switch field.kind {
            case .toggle:
                body[field.bodyKey] = (raw == "1")
            case .colorHex:
                let normalized = raw.replacingOccurrences(of: "#", with: "")
                if normalized.isEmpty {
                    if isEdit { body[field.bodyKey] = "" }
                } else {
                    body[field.bodyKey] = "#\(normalized)"
                }
            case .number:
                if let number = Int(raw) {
                    body[field.bodyKey] = number
                } else if isEdit && raw.isEmpty {
                    body[field.bodyKey] = NSNull()
                }
            case .picker(let source):
                if source.isFieldFormat, raw == customRegexSentinel {
                    var regex = customRegex.trimmingCharacters(in: .whitespaces)
                    if !regex.isEmpty, !regex.lowercased().hasPrefix("regex:") {
                        regex = "regex:\(regex)"
                    }
                    body[field.bodyKey] = regex
                } else if !raw.isEmpty {
                    body[field.bodyKey] = Int(raw) ?? raw
                } else if isEdit {
                    body[field.bodyKey] = NSNull()
                }
            default:
                if !raw.isEmpty {
                    body[field.bodyKey] = raw
                } else if isEdit {
                    // send empty so cleared fields stick
                    body[field.bodyKey] = ""
                }
            }
        }

        let result: SnipeITAPIClient.ManagementWriteResult
        if let existing {
            result = await apiClient.managementUpdate(path: config.path, id: existing.id, body: body)
        } else {
            result = await apiClient.managementCreate(path: config.path, body: body)
        }

        didSucceed = result.success
        if result.success {
            resultMessage = result.message ?? L10n.string(isEdit ? "saved" : "mgmt_created")
            await refreshBackingList()
        } else {
            resultMessage = result.message ?? L10n.string("mgmt_save_failed")
        }
        showResult = true
    }

    // refresh the cached list so other screens stay current
    private func refreshBackingList() async {
        switch entity {
        case .companies: await apiClient.fetchCompanies()
        case .manufacturers: await apiClient.fetchManufacturers()
        case .suppliers: await apiClient.fetchSuppliers()
        case .categories: await apiClient.fetchCategories()
        case .models: await apiClient.fetchModels()
        case .statusLabels: await apiClient.fetchStatusLabels()
        case .groups: await apiClient.fetchGroups()
        case .fields: await apiClient.fetchFieldDefinitions()
        case .fieldsets: await apiClient.fetchFieldsets()
        case .departments: break
        }
    }
}

// Color picker + hex field; sends "RRGGBB" to the API.
private struct HexColorRow: View {
    let title: String
    @Binding var hex: String

    @State private var color: Color = .gray
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ColorPicker(title, selection: $color, supportsOpacity: false)
            HStack(spacing: 6) {
                Text("#").foregroundStyle(.secondary)
                TextField("RRGGBB", text: $text)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                if let preview = Color(hexString: HexColor.normalize(text)) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(preview)
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 1)
                        )
                }
            }
        }
        .onChange(of: hex, initial: true) { _, newHex in
            syncFromHex(newHex)
        }
        .onChange(of: color) { _, newColor in
            let newHex = newColor.toHexString()
            if newHex.caseInsensitiveCompare(HexColor.normalize(text)) != .orderedSame {
                text = newHex
                hex = newHex
            }
        }
        .onChange(of: text) { _, newText in
            let normalized = HexColor.normalize(newText)
            if normalized != newText {
                text = normalized
                return
            }
            hex = normalized
            if normalized.count == 6, let parsed = Color(hexString: normalized) {
                color = parsed
            }
        }
    }

    private func syncFromHex(_ raw: String) {
        let normalized = HexColor.normalize(raw)
        if text != normalized { text = normalized }
        if normalized.count == 6, let parsed = Color(hexString: normalized) {
            color = parsed
        }
    }
}

private enum HexColor {
    // Strip leading '#', keep hex chars, uppercase, cap at 6.
    static func normalize(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
            .filter { $0.isHexDigit }
        return String(cleaned.prefix(6))
    }
}

private extension Color {
    init?(hexString: String) {
        let hex = HexColor.normalize(hexString)
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    func toHexString() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let clamp: (CGFloat) -> Int = { max(0, min(255, Int(($0 * 255).rounded()))) }
        return String(format: "%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }
}
