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

    /// Computes the next available asset tag, zero-padded like bestaande tags (bijv. 00581).
    private var nextAvailableAssetTag: String {
        let tags = apiClient.assets.map { $0.assetTag.trimmingCharacters(in: .whitespaces) }
        let numbers = tags.compactMap { tag -> Int? in
            let digits = tag.filter(\.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
        let nextNum = (numbers.max() ?? 0) + 1
        let digitLengths = tags.compactMap { tag -> Int? in
            let digits = tag.filter(\.isNumber)
            return digits.isEmpty ? nil : digits.count
        }
        let width = digitLengths.max() ?? 5
        return String(format: "%0*d", width, nextNum)
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                purchaseSection
                notesSection
                customFieldsSection
            }
            .navigationTitle(L10n.string("new_asset"))
            .toolbar { toolbarContent }
            .onAppear(perform: setupOnAppear)
            .onChange(of: apiClient.assets) { _, _ in
                assetTag = nextAvailableAssetTag
            }
            .task(id: selectedModelId) {
                await loadAndDisplayCustomFieldsForModel()
            }
            .alert(L10n.string("error"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(resultMessage)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.string("cancel")) { isPresented = false }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
            } else {
                Button(L10n.string("create")) { saveAsset() }
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
        // Status blijft standaard op "Kies status" (geen auto-select)
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
        Section(header: Text(L10n.string("general"))) {
            TextField(L10n.string("name_optional"), text: $name)
            HStack {
                Text(L10n.string("asset_tag"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(assetTag.isEmpty ? nextAvailableAssetTag : assetTag)
                    .foregroundStyle(.primary)
            }
            TextField(L10n.string("serial_optional"), text: $serial)

            // Model alfabetisch op naam
            Picker("Model", selection: $selectedModelId) {
                Text(L10n.string("choose_model")).tag(0)
                let sortedModels = apiClient.models.sorted {
                    HTMLDecoder.decode($0.name).localizedCaseInsensitiveCompare(HTMLDecoder.decode($1.name)) == .orderedAscending
                }
                ForEach(sortedModels) { model in
                    Text(HTMLDecoder.decode(model.name)).tag(model.id)
                }
            }

            // Status alfabetisch op weergavenaam
            Picker("Status", selection: $selectedStatusId) {
                Text(L10n.string("choose_status")).tag(0)
                let sortedStatuses = apiClient.statusLabels.sorted {
                    displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
                }
                ForEach(sortedStatuses, id: \.id) { label in
                    Text(displayName(for: label)).tag(label.id)
                }
            }
            if !apiClient.locations.isEmpty {
                Picker(L10n.string("location_optional"), selection: Binding(
                    get: { selectedLocationId ?? 0 },
                    set: { selectedLocationId = $0 == 0 ? nil : $0 }
                )) {
                    Text(L10n.string("choose_location")).tag(0)
                    let sortedLocations = apiClient.locations.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    ForEach(sortedLocations) { loc in
                        Text(loc.name).tag(loc.id)
                    }
                }
            }
            if !apiClient.companies.isEmpty {
                Picker(L10n.string("company_optional"), selection: Binding(
                    get: { selectedCompanyId ?? 0 },
                    set: { selectedCompanyId = $0 == 0 ? nil : $0 }
                )) {
                    Text(L10n.string("choose_company")).tag(0)
                    let sortedCompanies = apiClient.companies.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    ForEach(sortedCompanies) { company in
                        Text(company.name).tag(company.id)
                    }
                }
            }
            Toggle(L10n.string("byod"), isOn: $byod)
        }
    }

    private var purchaseSection: some View {
        Section(header: Text(L10n.string("purchase_warranty"))) {
            TextField(L10n.string("order_number_optional"), text: $orderNumber)
            TextField(L10n.string("purchase_price_optional"), text: $purchaseCost)
                .keyboardType(.numbersAndPunctuation)
            Toggle(L10n.string("purchase_date"), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
            }
            Toggle(L10n.string("eol_date"), isOn: $hasEolDate)
            if hasEolDate {
                DatePicker("", selection: $eolDate, displayedComponents: .date)
            }
            TextField(L10n.string("warranty_months_optional"), text: $warrantyMonths)
                .keyboardType(.numberPad)
            if !suppliersFromAssets.isEmpty {
                Picker(L10n.string("supplier_optional"), selection: Binding(
                    get: { selectedSupplierId ?? 0 },
                    set: { selectedSupplierId = $0 == 0 ? nil : $0 }
                )) {
                    Text(L10n.string("choose_supplier")).tag(0)
                    let sortedSuppliers = suppliersFromAssets.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    ForEach(sortedSuppliers, id: \.id) { sup in
                        Text(sup.name).tag(sup.id)
                    }
                }
            }
        }
    }

    private var suppliersFromAssets: [(id: Int, name: String)] {
        let ids = Set(apiClient.assets.compactMap { $0.supplier?.id })
        return ids.compactMap { id in
            apiClient.assets.first(where: { $0.supplier?.id == id }).flatMap { a in
                a.supplier.map { (id: $0.id, name: $0.name) }
            }
        }
    }

    private var notesSection: some View {
        Section(header: Text(L10n.string("notes"))) {
            TextEditor(text: $notes)
                .frame(minHeight: 80)
        }
    }

    private var customFieldsSection: some View {
        Group {
            if !displayedFieldDefinitions.isEmpty {
                Section(header: Text(L10n.string("custom_fields"))) {
                    ForEach(displayedFieldDefinitions, id: \.name) { fieldDef in
                        let key = fieldDef.name
                        if fieldDef.type == "listbox", let options = fieldDef.field_values_array, !options.isEmpty {
                            Picker(key, selection: Binding(
                                get: { customFields[key] ?? "" },
                                set: { customFields[key] = $0 }
                            )) {
                                Text("—").tag("")
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
        let nameToSend = nameValue
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
            purchase_cost: NumberFormatHelpers.normalizeDecimalForAPI(purchaseCost.trimmingCharacters(in: .whitespaces)),
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
            if success {
                await apiClient.fetchAssets()
            }
            await MainActor.run {
                isSaving = false
                if success {
                    isPresented = false
                } else {
                    resultMessage = apiClient.lastApiMessage ?? "Create failed."
                    showResult = true
                }
            }
        }
    }
}
