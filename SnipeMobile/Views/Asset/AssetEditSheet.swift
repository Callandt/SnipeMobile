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
    @Binding var showSaveSuccess: Bool
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

    var body: some View {
        NavigationView {
            Form {
                generalSection
                financialSection
                notesSection
                customFieldsSection
            }
            .navigationTitle("Edit Asset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
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
                                let update = SnipeITAPIClient.AssetUpdateRequest(
                                    name: editName,
                                    asset_tag: editAssetTag,
                                    serial: editSerial,
                                    model_id: selectedModelId,
                                    status_id: selectedStatusId,
                                    category_id: selectedCategoryId,
                                    manufacturer_id: selectedManufacturerId,
                                    supplier_id: selectedSupplierId,
                                    notes: editNotes,
                                    order_number: editOrderNumber,
                                    location_id: selectedLocationId,
                                    purchase_cost: editPurchaseCost,
                                    book_value: editBookValue,
                                    custom_fields: editCustomFields,
                                    purchase_date: purchaseDateString,
                                    next_audit_date: nextAuditDateString,
                                    expected_checkin: expectedCheckinString,
                                    eol_date: eolDateString
                                )
                                let success = await apiClient.updateAsset(assetId: asset.id, update: update)
                                isSaving = false
                                resultMessage = apiClient.lastApiMessage ?? (success ? "Wijzigingen opgeslagen!" : "Opslaan mislukt.")
                                showResult = true
                                if success {
                                    isPresented = false
                                }
                            }
                        }
                    }
                }
            }
            .alert(isPresented: $showArchiveError) {
                Alert(title: Text("Kan niet archiveren"), message: Text("Deze asset is nog toegewezen aan een gebruiker of locatie. Check de asset eerst in voordat je deze op 'archived' zet."), dismissButton: .default(Text("OK")))
            }
            .alert(isPresented: $showResult) {
                Alert(title: Text("Resultaat"), message: Text(resultMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var generalSection: some View {
        Section(header: Text("General")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Name", text: $editName)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Serial")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Serial", text: $editSerial)
            }
            if !apiClient.assets.isEmpty {
                let modelPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { asset in
                    guard let model = asset.model else { return nil }
                    return IdNamePair(id: model.id, name: HTMLDecoder.decode(model.name))
                })).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                Picker("Model", selection: $selectedModelId) {
                    ForEach(modelPairs) { pair in
                        Text(pair.name).tag(pair.id)
                    }
                }
                .disabled(true)
                .opacity(0.6)
            }
            if !apiClient.assets.isEmpty {
                Picker("Supplier", selection: $selectedSupplierId) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.supplier?.id }).sorted()), id: \.self) { id in
                        if let sup = apiClient.assets.first(where: { $0.supplier?.id == id })?.supplier {
                            Text(sup.name).tag(sup.id)
                        }
                    }
                }
            }
            if !apiClient.assets.isEmpty {
                Picker("Company", selection: $selectedCompanyId) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.company?.id }).sorted()), id: \.self) { id in
                        if let comp = apiClient.assets.first(where: { $0.company?.id == id })?.company {
                            Text(comp.name).tag(comp.id)
                        }
                    }
                }
            }
            // Status Picker: huidige status eerst, dan de rest
            Picker("Status", selection: $selectedStatusId) {
                ForEach(apiClient.statusLabels, id: \.id) { label in
                    Text(label.name).tag(label.id)
                }
            }
        }
        .onAppear {
            print("DEBUG: aantal statusLabels: \(apiClient.statusLabels.count)")
            for label in apiClient.statusLabels {
                print("DEBUG: statusLabel: id=\(label.id), name=\(label.name)")
            }
            print("DEBUG: selectedStatusId: \(selectedStatusId)")
        }
    }

    private var financialSection: some View {
        Section(header: Text("Financial")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Purchase Cost")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Purchase Cost", text: $editPurchaseCost)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Order Number")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Order Number", text: $editOrderNumber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Warranty Months")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Warranty Months", text: $editWarrantyMonths)
            }
            // Purchase Date
            HStack {
                Toggle("Set Purchase Date", isOn: $hasPurchaseDate)
                    .font(.caption)
                if hasPurchaseDate {
                    DatePicker("", selection: $editPurchaseDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            // EOL Date (moved after Purchase Date)
            HStack {
                Toggle("Set EOL Date", isOn: $hasEolDate)
                    .font(.caption)
                if hasEolDate {
                    DatePicker("", selection: $editEolDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            // Next Audit Date
            HStack {
                Toggle("Set Next Audit Date", isOn: $hasNextAuditDate)
                    .font(.caption)
                if hasNextAuditDate {
                    DatePicker("", selection: $editNextAuditDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    private var notesSection: some View {
        Section(header: Text("Notes")) {
            TextEditor(text: $editNotes)
                .frame(minHeight: 120)
        }
    }

    private func debugCustomFields(customFieldDefs: [SnipeITAPIClient.FieldDefinition], editCustomFields: [String: String]) {
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
    }

    private var customFieldsSection: some View {
        Section(header: Text("Custom Fields")) {
            let customFieldDefs = apiClient.modelFieldDefinitions ?? apiClient.fieldDefinitions
            if editCustomFields.isEmpty {
                Text("No custom fields")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(editCustomFields.keys.sorted()), id: \.self) { key in
                    let fieldDef = customFieldDefs.first(where: { $0.name == key })
                    if let fieldDef = fieldDef, fieldDef.type == "listbox", let options = fieldDef.field_values_array {
                        Picker(key, selection: Binding(
                            get: { editCustomFields[key] ?? "" },
                            set: { editCustomFields[key] = $0 }
                        )) {
                            ForEach(options, id: \.self) { option in
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