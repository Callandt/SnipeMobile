import SwiftUI

struct IdNamePair: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct AssetEditSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @AppStorage("auditNotificationsEnabled") private var auditNotificationsEnabled: Bool = false
    @AppStorage("auditNotificationHour") private var auditNotificationHour: Int = 9
    @AppStorage("auditNotificationMinute") private var auditNotificationMinute: Int = 0
    let asset: Asset
    @Binding var isPresented: Bool
    @Binding var editName: String
    @Binding var editAssetTag: String
    @Binding var editSerial: String
    @Binding var editNotes: String
    @Binding var editOrderNumber: String
    @Binding var editPurchaseCost: String
    @Binding var editBookValue: String
    @Binding var editCustomFields: [String: String]
    @Binding var isSaving: Bool
    @Binding var selectedModelId: Int
    @Binding var selectedStatusId: Int
    @Binding var selectedCategoryId: Int
    @Binding var selectedManufacturerId: Int
    @Binding var selectedSupplierId: Int
    @Binding var selectedCompanyId: Int
    @Binding var selectedLocationId: Int
    @Binding var editPurchaseDate: Date
    @Binding var editNextAuditDate: Date
    @Binding var editWarrantyExpires: Date
    @Binding var hasPurchaseDate: Bool
    @Binding var hasNextAuditDate: Bool
    @Binding var hasWarrantyExpires: Bool
    @Binding var editExpectedCheckin: Date
    @Binding var editEolDate: Date
    @Binding var editWarrantyMonths: String
    @Binding var hasExpectedCheckin: Bool
    @Binding var hasEolDate: Bool
    @Binding var showPurchaseDate: Bool
    @Binding var showNextAuditDate: Bool
    @Binding var showWarrantyExpires: Bool
    @Binding var showExpectedCheckin: Bool
    @Binding var showEolDate: Bool
    @State private var showArchiveError = false
    @State private var showResult = false
    @State private var resultMessage = ""

    /// Checked out. Status read only.
    private var isAssetCheckedOut: Bool {
        asset.assignedTo != nil || asset.location != nil
    }

    /// Status label. name or status_meta.
    private func displayName(for label: StatusLabel) -> String {
        let meta = label.statusMeta?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meta.isEmpty ? label.name : meta
    }

    var body: some View {
        NavigationView {
            Form {
                generalSection
                financialSection
                notesSection
                customFieldsSection
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("save")) {
                            // Block archive if assigned
                            let archiveStatus = apiClient.statusLabels.first { $0.name.lowercased() == "archived" }?.id
                            let isArchiving = selectedStatusId == archiveStatus
                            let isAssigned = (asset.assignedTo != nil) || (asset.location != nil)
                            if isArchiving && isAssigned {
                                showArchiveError = true
                                return
                            }
                            isSaving = true
                            Task {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd"
                                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                                let purchaseDateString = hasPurchaseDate ? formatter.string(from: editPurchaseDate) : nil
                                let nextAuditDateRequest: SnipeITAPIClient.AssetUpdateRequest.NullableString? =
                                    hasNextAuditDate
                                    ? .value(formatter.string(from: editNextAuditDate))
                                    : .null
                                let expectedCheckinString = hasExpectedCheckin ? formatter.string(from: editExpectedCheckin) : nil
                                let eolDateString = hasEolDate ? formatter.string(from: editEolDate) : nil
                                let trim: (String) -> String? = { s in
                                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                    return t.isEmpty ? nil : t
                                }
                                let normalizedPurchaseCost = NumberFormatHelpers.normalizeDecimalForAPI(editPurchaseCost)
                                let normalizedBookValue = NumberFormatHelpers.normalizeDecimalForAPI(editBookValue)
                                let originalBookValue = NumberFormatHelpers.normalizeDecimalForAPI(asset.bookValue)
                                let purchaseCostRequest: SnipeITAPIClient.AssetUpdateRequest.NullableString? =
                                    normalizedPurchaseCost.map { .value($0) } ?? .null
                                // Als aankoopprijs leeg is en boekwaarde niet gewijzigd werd in de UI,
                                // wis boekwaarde expliciet zodat "legacy" restwaarden niet blijven hangen.
                                let shouldClearUnchangedBookValue = normalizedPurchaseCost == nil && normalizedBookValue == originalBookValue
                                let bookValueRequest: SnipeITAPIClient.AssetUpdateRequest.NullableString? =
                                    shouldClearUnchangedBookValue
                                    ? .null
                                    : (normalizedBookValue.map { .value($0) } ?? .null)
                                // Snipe-IT verwacht voor custom_fields meestal de interne veldsleutel
                                // (bijv. "_snipeit_xxx_1"), niet altijd de zichtbare labelnaam.
                                let customFieldsPayload: [String: SnipeITAPIClient.AssetUpdateRequest.CustomFieldValue] = Dictionary(
                                    uniqueKeysWithValues: editCustomFields.map { key, value in
                                        let apiKey = asset.customFields?[key]?.field ?? key
                                        return (apiKey, .init(value: value))
                                    }
                                )
                                let update = SnipeITAPIClient.AssetUpdateRequest(
                                    name: trim(editName),
                                    asset_tag: trim(editAssetTag) ?? asset.assetTag,
                                    serial: trim(editSerial) ?? "",
                                    model_id: selectedModelId,
                                    status_id: selectedStatusId,
                                    category_id: selectedCategoryId,
                                    manufacturer_id: selectedManufacturerId,
                                    supplier_id: selectedSupplierId,
                                    notes: trim(editNotes) ?? "",
                                    order_number: trim(editOrderNumber) ?? "",
                                    location_id: asset.location?.id,
                                    purchase_cost: purchaseCostRequest,
                                    book_value: bookValueRequest,
                                    custom_fields: customFieldsPayload,
                                    purchase_date: purchaseDateString,
                                    next_audit_date: nextAuditDateRequest,
                                    expected_checkin: expectedCheckinString,
                                    eol_date: eolDateString
                                )
                                let success = await apiClient.updateAsset(assetId: asset.id, update: update)
                                if success {
                                    await apiClient.fetchAssets()
                                    if auditNotificationsEnabled {
                                        await AuditNotificationManager.shared.updateSchedule(
                                            enabled: true,
                                            hour: auditNotificationHour,
                                            minute: auditNotificationMinute,
                                            assets: apiClient.assets
                                        )
                                    }
                                }
                                isSaving = false
                                if success {
                                    isPresented = false
                                } else {
                                    resultMessage = apiClient.lastApiMessage ?? "Save failed."
                                    showResult = true
                                }
                            }
                        }
                    }
                }
            }
            .alert(isPresented: $showArchiveError) {
                Alert(title: Text(L10n.string("cannot_archive")), message: Text(L10n.string("cannot_archive_msg")), dismissButton: .default(Text(L10n.string("ok"))))
            }
            .alert(isPresented: $showResult) {
                Alert(title: Text(L10n.string("result")), message: Text(resultMessage), dismissButton: .default(Text(L10n.string("ok"))))
            }
        }
    }

    private var generalSection: some View {
        Section(header: Text(L10n.string("general"))) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("name"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(L10n.string("name"), text: $editName)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("serial"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(L10n.string("serial"), text: $editSerial)
            }
            if !apiClient.assets.isEmpty {
                let modelPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { asset in
                    guard let model = asset.model else { return nil }
                    return IdNamePair(id: model.id, name: HTMLDecoder.decode(model.name))
                })).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !modelPairs.isEmpty {
                    Picker("Model", selection: $selectedModelId) {
                        ForEach(modelPairs) { pair in
                            Text(pair.name).tag(pair.id)
                        }
                    }
                    .disabled(true)
                    .opacity(0.6)
                }
            }
            if !apiClient.assets.isEmpty {
                let supplierPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { $0.supplier?.id })).compactMap { id in
                    apiClient.assets.first(where: { $0.supplier?.id == id })?.supplier.map {
                        IdNamePair(id: $0.id, name: $0.name)
                    }
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !supplierPairs.isEmpty {
                    AdaptivePickerRow(
                        title: "Supplier",
                        items: supplierPairs.map { (value: $0.id, label: $0.name) },
                        selection: $selectedSupplierId,
                        emptyOption: (0, "—")
                    )
                }
            }
            if !apiClient.assets.isEmpty {
                let companyPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { $0.company?.id })).compactMap { id in
                    apiClient.assets.first(where: { $0.company?.id == id })?.company.map {
                        IdNamePair(id: $0.id, name: $0.name)
                    }
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !companyPairs.isEmpty {
                    AdaptivePickerRow(
                        title: "Company",
                        items: companyPairs.map { (value: $0.id, label: $0.name) },
                        selection: $selectedCompanyId,
                        emptyOption: (0, "—")
                    )
                }
            }
            // Status only when not checked out. Avoids Picker crash.
            if !isAssetCheckedOut, !apiClient.statusLabels.isEmpty {
                let sortedStatuses = apiClient.statusLabels.sorted {
                    displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
                }
                let validStatusIds = Set(apiClient.statusLabels.map(\.id))
                AdaptivePickerRow(
                    title: "Status",
                    items: sortedStatuses.map { (value: $0.id, label: displayName(for: $0)) },
                    selection: Binding(
                        get: { validStatusIds.contains(selectedStatusId) ? selectedStatusId : (sortedStatuses.first?.id ?? 0) },
                        set: { selectedStatusId = $0 }
                    ),
                    emptyOption: nil
                )
                .onAppear {
                    if !validStatusIds.contains(selectedStatusId), let first = sortedStatuses.first?.id {
                        selectedStatusId = first
                    }
                }
            }
        }
    }

    private var financialSection: some View {
        Section(header: Text(L10n.string("financial"))) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("purchase_cost"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(L10n.string("purchase_cost"), text: $editPurchaseCost)
                    .keyboardType(.decimalPad)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("order_number"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(L10n.string("order_number"), text: $editOrderNumber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("warranty_months"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(L10n.string("warranty_months"), text: $editWarrantyMonths)
                    .keyboardType(.numberPad)
            }
            // Purchase
            HStack {
                Toggle(L10n.string("set_purchase_date"), isOn: $hasPurchaseDate)
                    .font(.caption)
                if hasPurchaseDate {
                    DatePicker("", selection: $editPurchaseDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            // EOL date
            HStack {
                Toggle(L10n.string("set_eol_date"), isOn: $hasEolDate)
                    .font(.caption)
                if hasEolDate {
                    DatePicker("", selection: $editEolDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            // Next audit
            HStack {
                Toggle(L10n.string("set_next_audit"), isOn: $hasNextAuditDate)
                    .font(.caption)
                if hasNextAuditDate {
                    DatePicker("", selection: $editNextAuditDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    private var notesSection: some View {
        Section(header: Text(L10n.string("notes"))) {
            TextEditor(text: $editNotes)
                .frame(minHeight: 120)
        }
    }

    private func debugCustomFields(customFieldDefs: [SnipeITAPIClient.FieldDefinition], editCustomFields: [String: String]) {
        #if DEBUG
        let defsString = customFieldDefs.map { "\($0.name):\($0.type ?? "")" }.joined(separator: ", ")
        let fieldsString = editCustomFields.map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        print("DEBUG: customFieldDefs: \(defsString)")
        print("DEBUG: editCustomFields: \(fieldsString)")
        for key in editCustomFields.keys.sorted() {
            if let def = customFieldDefs.first(where: { $0.name == key }) {
                let type = def.type ?? "(geen type)"
                let options = def.field_values_array?.joined(separator: ", ") ?? "(geen opties)"
                print("DEBUG: veld \(key): type=\(type), opties=\(options)")
            } else {
                print("DEBUG: veld \(key): GEEN definitie gevonden")
            }
        }
        #endif
    }

    private var customFieldsSection: some View {
        Section(header: Text(L10n.string("custom_fields"))) {
            let customFieldDefs = apiClient.modelFieldDefinitions ?? apiClient.fieldDefinitions
            if editCustomFields.isEmpty {
                Text(L10n.string("no_custom_fields"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(editCustomFields.keys.sorted()), id: \.self) { key in
                    let fieldDef = customFieldDefs.first(where: { $0.name == key })
                    if let fieldDef = fieldDef, fieldDef.type == "listbox", let options = fieldDef.field_values_array {
                        let sortedOptions = options.sorted {
                            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                        }
                        AdaptivePickerRow(
                            title: key,
                            items: sortedOptions.map { (value: $0, label: $0) },
                            selection: Binding(
                                get: { editCustomFields[key] ?? "" },
                                set: { editCustomFields[key] = $0 }
                            ),
                            emptyOption: ("", "—")
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField(key, text: Binding(
                                get: { editCustomFields[key] ?? "" },
                                set: { editCustomFields[key] = $0 }
                            ))
                        }
                    }
                }
            }
        }
        .onAppear {
            let customFieldDefs = apiClient.modelFieldDefinitions ?? apiClient.fieldDefinitions
            debugCustomFields(customFieldDefs: customFieldDefs, editCustomFields: editCustomFields)
        }
    }

    private func updateCustomFieldsForModel(_ modelId: Int) {
        guard let fieldsets = apiClient.fieldsets else { return }
        guard let fieldset = fieldsets.first(where: { fs in
            (fs.models?.rows.contains { $0.id == modelId }) ?? false
        }) else { return }
        var newCustomFields: [String: String] = [:]
        for field in fieldset.fields.rows {
            newCustomFields[field.name] = editCustomFields[field.name] ?? ""
        }
        editCustomFields = newCustomFields
    }
} 