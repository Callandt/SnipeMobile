import SwiftUI

struct AddAssetSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var assetTag = ""
    @State private var serial = ""
    @State private var notes = ""
    @State private var selectedModelId: Int = 0
    @State private var selectedStatusId: Int = 0
    @State private var selectedLocationId: Int?
    @State private var selectedCompanyId: Int?
    @State private var selectedSupplierId: Int?
    @State private var orderNumber = ""
    @State private var purchaseCost = ""
    @State private var purchaseDate = Date()
    @State private var hasPurchaseDate = false
    @State private var eolDate = Date()
    @State private var hasEolDate = false
    @State private var warrantyMonths = ""
    @State private var byod = false
    @State private var customFields: [String: String] = [:]
    @State private var displayedFieldDefinitions: [SnipeITAPIClient.FieldDefinition] = []
    @State private var isSaving = false
    @State private var resultMessage = ""
    @State private var showResult = false

    private var canSave: Bool {
        !assetTag.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedModelId != 0
            && selectedStatusId != 0
    }

    /// Computes the next available asset tag from existing assets (max numeric value + 1).
    private var nextAvailableAssetTag: String {
        let tags = apiClient.assets.map { $0.assetTag.trimmingCharacters(in: .whitespaces) }
        let numbers = tags.compactMap { tag -> Int? in
            // Support both plain numbers and prefix+number (e.g. "ASSET-123" → 123)
            let digits = tag.filter(\.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
        let nextNum = (numbers.max() ?? 0) + 1
        return "\(nextNum)"
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                purchaseSection
                notesSection
                customFieldsSection
            }
            .navigationTitle("New asset")
            .toolbar { toolbarContent }
            .onAppear(perform: setupOnAppear)
            .onChange(of: apiClient.assets) { _, _ in
                assetTag = nextAvailableAssetTag
            }
            .task(id: selectedModelId) {
                await loadAndDisplayCustomFieldsForModel()
            }
            .alert("Result", isPresented: $showResult) {
                Button("OK") {
                    if resultMessage.contains("created") {
                        isPresented = false
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { isPresented = false }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button("Create") { saveAsset() }
                    .disabled(!canSave)
            }
        }
    }

    private func setupOnAppear() {
        assetTag = nextAvailableAssetTag
        if apiClient.models.isEmpty {
            Task {
                await apiClient.fetchModels()
                await apiClient.fetchFieldsets()
                if selectedModelId == 0, let first = apiClient.models.first {
                    selectedModelId = first.id
                    await apiClient.fetchModelFieldDefinitions(modelId: first.id)
                    loadCustomFieldsForModel(first.id)
                }
            }
        }
        if apiClient.fieldsets == nil {
            Task { await apiClient.fetchFieldsets() }
        }
        if apiClient.statusLabels.isEmpty {
            Task { await apiClient.fetchStatusLabels() }
        }
        if selectedStatusId == 0, let first = apiClient.statusLabels.first {
            selectedStatusId = first.id
        }
        if apiClient.companies.isEmpty {
            Task { await apiClient.fetchCompanies() }
        }
    }

    private func loadAndDisplayCustomFieldsForModel() async {
        let modelId = selectedModelId
        guard modelId != 0 else {
            displayedFieldDefinitions = []
            customFields = [:]
            return
        }
        if apiClient.fieldsets == nil {
            await apiClient.fetchFieldsets()
        }
        let fromFieldsets = await MainActor.run {
            apiClient.modelFieldDefinitionsFromFieldsets(modelId: modelId)
        }
        await MainActor.run {
            displayedFieldDefinitions = fromFieldsets
            var next: [String: String] = [:]
            for d in fromFieldsets {
                next[d.name] = customFields[d.name] ?? ""
            }
            customFields = next
        }
        await apiClient.fetchModelFieldDefinitions(modelId: modelId)
        let fromApi = await MainActor.run { apiClient.modelFieldDefinitions ?? [] }
        if !fromApi.isEmpty {
            await MainActor.run {
                displayedFieldDefinitions = fromApi
                var next: [String: String] = [:]
                for d in fromApi {
                    next[d.name] = customFields[d.name] ?? ""
                }
                customFields = next
            }
        }
    }

    private var generalSection: some View {
        Section(header: Text("General")) {
            TextField("Name (optional)", text: $name)
            HStack {
                Text("Asset tag")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(assetTag.isEmpty ? nextAvailableAssetTag : assetTag)
                    .foregroundStyle(.primary)
            }
            TextField("Serial (optional)", text: $serial)
            Picker("Model", selection: $selectedModelId) {
                Text("Choose model…").tag(0)
                ForEach(apiClient.models) { model in
                    Text(HTMLDecoder.decode(model.name)).tag(model.id)
                }
            }
            Picker("Status", selection: $selectedStatusId) {
                Text("Choose status…").tag(0)
                ForEach(apiClient.statusLabels, id: \.id) { label in
                    Text(displayName(for: label)).tag(label.id)
                }
            }
            if !apiClient.locations.isEmpty {
                Picker("Location (optional)", selection: Binding(
                    get: { selectedLocationId ?? -1 },
                    set: { selectedLocationId = $0 == -1 ? nil : $0 }
                )) {
                    Text("None").tag(-1)
                    ForEach(apiClient.locations) { loc in
                        Text(loc.name).tag(loc.id)
                    }
                }
            }
            if !apiClient.companies.isEmpty {
                Picker("Company (optional)", selection: Binding(
                    get: { selectedCompanyId ?? -1 },
                    set: { selectedCompanyId = $0 == -1 ? nil : $0 }
                )) {
                    Text("None").tag(-1)
                    ForEach(apiClient.companies) { company in
                        Text(company.name).tag(company.id)
                    }
                }
            }
            Toggle("BYOD?", isOn: $byod)
        }
    }

    private var purchaseSection: some View {
        Section(header: Text("Purchase & warranty")) {
            TextField("Order number (optional)", text: $orderNumber)
            TextField("Purchase price (optional)", text: $purchaseCost)
                .keyboardType(.decimalPad)
            Toggle("Purchase date", isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
            }
            Toggle("EOL date", isOn: $hasEolDate)
            if hasEolDate {
                DatePicker("", selection: $eolDate, displayedComponents: .date)
            }
            TextField("Warranty (months, optional)", text: $warrantyMonths)
                .keyboardType(.numberPad)
            if !suppliersFromAssets.isEmpty {
                Picker("Supplier (optional)", selection: Binding(
                    get: { selectedSupplierId ?? -1 },
                    set: { selectedSupplierId = $0 == -1 ? nil : $0 }
                )) {
                    Text("None").tag(-1)
                    ForEach(suppliersFromAssets, id: \.id) { sup in
                        Text(sup.name).tag(sup.id)
                    }
                }
            }
        }
    }

    private var suppliersFromAssets: [(id: Int, name: String)] {
        let ids = Set(apiClient.assets.compactMap { $0.supplier?.id })
        return ids.sorted().compactMap { id in
            apiClient.assets.first(where: { $0.supplier?.id == id }).flatMap { a in
                a.supplier.map { (id: $0.id, name: $0.name) }
            }
        }
    }

    private var notesSection: some View {
        Section(header: Text("Notes")) {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
        }
    }

    private var customFieldsSection: some View {
        Group {
            if !displayedFieldDefinitions.isEmpty {
                Section(header: Text("Custom fields")) {
                    ForEach(displayedFieldDefinitions, id: \.name) { fieldDef in
                        let key = fieldDef.name
                        if fieldDef.type == "listbox", let options = fieldDef.field_values_array, !options.isEmpty {
                            Picker(key, selection: Binding(
                                get: { customFields[key] ?? "" },
                                set: { customFields[key] = $0 }
                            )) {
                                Text("—").tag("")
                                ForEach(options, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(key, text: Binding(
                                    get: { customFields[key] ?? "" },
                                    set: { customFields[key] = $0 }
                                ))
                            }
                        }
                    }
                }
            }
        }
    }

    private func displayName(for label: StatusLabel) -> String {
        let meta = label.statusMeta?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meta.isEmpty ? label.name : meta
    }

    private func loadCustomFieldsForModel(_ modelId: Int) {
        guard let fieldsets = apiClient.fieldsets else { return }
        guard let fieldset = fieldsets.first(where: { fs in
            (fs.models?.rows.contains { $0.id == modelId }) ?? false
        }) else {
            customFields = [:]
            return
        }
        var newFields: [String: String] = [:]
        for field in fieldset.fields.rows {
            newFields[field.name] = customFields[field.name] ?? ""
        }
        customFields = newFields
    }

    private func saveAsset() {
        guard selectedModelId != 0, selectedStatusId != 0 else { return }
        isSaving = true
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f
        }()
        let nameValue = name.trimmingCharacters(in: .whitespaces)
        let nameToSend = nameValue.isEmpty ? assetTag.trimmingCharacters(in: .whitespaces) : nameValue
        let purchaseDateStr = hasPurchaseDate ? formatter.string(from: purchaseDate) : nil
        let eolDateStr = hasEolDate ? formatter.string(from: eolDate) : nil
        let req = SnipeITAPIClient.AssetCreateRequest(
            name: nameToSend,
            asset_tag: assetTag.trimmingCharacters(in: .whitespaces),
            model_id: selectedModelId,
            status_id: selectedStatusId,
            serial: serial.isEmpty ? nil : serial,
            location_id: selectedLocationId,
            notes: notes.isEmpty ? nil : notes,
            order_number: orderNumber.isEmpty ? nil : orderNumber.trimmingCharacters(in: .whitespaces),
            purchase_cost: purchaseCost.isEmpty ? nil : purchaseCost.trimmingCharacters(in: .whitespaces),
            book_value: nil,
            custom_fields: customFields.isEmpty ? nil : customFields,
            purchase_date: purchaseDateStr,
            next_audit_date: nil,
            expected_checkin: nil,
            eol_date: eolDateStr,
            category_id: nil,
            manufacturer_id: nil,
            supplier_id: selectedSupplierId,
            company_id: selectedCompanyId,
            warranty_months: warrantyMonths.isEmpty ? nil : warrantyMonths.trimmingCharacters(in: .whitespaces),
            warranty_expires: nil,
            byod: byod
        )
        Task {
            let success = await apiClient.createAsset(req)
            isSaving = false
            resultMessage = apiClient.lastApiMessage ?? (success ? "Asset created!" : "Create failed.")
            showResult = true
        }
    }
}
