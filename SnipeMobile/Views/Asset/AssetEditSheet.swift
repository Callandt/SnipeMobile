import SwiftUI

struct IdNamePair: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct AssetEditSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
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

    /// Asset is uitgecheckt (toegewezen aan gebruiker of locatie); status is dan niet bewerkbaar.
    private var isAssetCheckedOut: Bool {
        asset.assignedTo != nil || asset.location != nil
    }

    /// Weergavenaam voor statuslabel: Snipe-IT vult soms alleen `name`, soms `status_meta`.
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
            .navigationTitle(L10n.string("edit_asset"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("save")) {
                            // Check for archive status while assigned
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
                                let nextAuditDateString = hasNextAuditDate ? formatter.string(from: editNextAuditDate) : nil
                                let expectedCheckinString = hasExpectedCheckin ? formatter.string(from: editExpectedCheckin) : nil
                                let eolDateString = hasEolDate ? formatter.string(from: editEolDate) : nil
                                let trim: (String) -> String? = { s in
                                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                                    return t.isEmpty ? nil : t
                                }
                                let update = SnipeITAPIClient.AssetUpdateRequest(
                                    name: trim(editName) ?? asset.name,
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
                                    purchase_cost: NumberFormatHelpers.normalizeDecimalForAPI(editPurchaseCost) ?? "",
                                    book_value: NumberFormatHelpers.normalizeDecimalForAPI(editBookValue) ?? "",
                                    custom_fields: editCustomFields,
                                    purchase_date: purchaseDateString,
                                    next_audit_date: nextAuditDateString,
                                    expected_checkin: expectedCheckinString,
                                    eol_date: eolDateString
                                )
                                let success = await apiClient.updateAsset(assetId: asset.id, update: update)
                                if success {
                                    await apiClient.fetchAssets()
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
                    Picker("Supplier", selection: $selectedSupplierId) {
                        ForEach(supplierPairs) { pair in
                            Text(pair.name).tag(pair.id)
                        }
                    }
                }
            }
            if !apiClient.assets.isEmpty {
                let companyPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { $0.company?.id })).compactMap { id in
                    apiClient.assets.first(where: { $0.company?.id == id })?.company.map {
                        IdNamePair(id: $0.id, name: $0.name)
                    }
                }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !companyPairs.isEmpty {
                    Picker("Company", selection: $selectedCompanyId) {
                        ForEach(companyPairs) { pair in
                            Text(pair.name).tag(pair.id)
                        }
                    }
                }
            }
            // Status alleen tonen als asset niet uitgecheckt is en we statuslabels hebben (voorkomt Picker-crash)
            if !isAssetCheckedOut, !apiClient.statusLabels.isEmpty {
                let sortedStatuses = apiClient.statusLabels.sorted {
                    displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
                }
                let validStatusIds = Set(apiClient.statusLabels.map(\.id))
                Picker("Status", selection: Binding(
                    get: { validStatusIds.contains(selectedStatusId) ? selectedStatusId : (sortedStatuses.first?.id ?? 0) },
                    set: { selectedStatusId = $0 }
                )) {
                    ForEach(sortedStatuses, id: \.id) { label in
                        Text(displayName(for: label)).tag(label.id)
                    }
                }
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
            }
            // Purchase Date
            HStack {
                Toggle(L10n.string("set_purchase_date"), isOn: $hasPurchaseDate)
                    .font(.caption)
                if hasPurchaseDate {
                    DatePicker("", selection: $editPurchaseDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            // EOL Date (moved after Purchase Date)
            HStack {
                Toggle(L10n.string("set_eol_date"), isOn: $hasEolDate)
                    .font(.caption)
                if hasEolDate {
                    DatePicker("", selection: $editEolDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            // Next Audit Date
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
                        Picker(key, selection: Binding(
                            get: { editCustomFields[key] ?? "" },
                            set: { editCustomFields[key] = $0 }
                        )) {
                            let sortedOptions = options.sorted {
                                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                            }
                            ForEach(sortedOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
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