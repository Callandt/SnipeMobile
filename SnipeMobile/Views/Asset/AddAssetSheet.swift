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
    @State private var showingDellScanner = false
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true

    private var canSave: Bool {
        !assetTag.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedModelId != 0
            && selectedStatusId != 0
    }

    /// Next asset tag. Zero padded.
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
        .sheet(isPresented: $showingDellScanner) {
            ZoomableQRScannerView(completion: handleDellScanResult)
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
        // No model preselected.
        selectedModelId = 0
        displayedFieldDefinitions = []
        customFields = [:]
        if apiClient.models.isEmpty {
            Task {
                await apiClient.fetchModels()
                await apiClient.fetchFieldsets()
            }
        }
        if apiClient.fieldsets == nil {
            Task { await apiClient.fetchFieldsets() }
        }
        if apiClient.statusLabels.isEmpty {
            Task { await apiClient.fetchStatusLabels() }
        }
        // Status stays unset
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
            if enableDellQrScan {
                Button {
                    showingDellScanner = true
                } label: {
                    Label(L10n.string("scan_dell_qr"), systemImage: "qrcode.viewfinder")
                }
            }

            // Models by name
            let sortedModels = apiClient.models.sorted {
                HTMLDecoder.decode($0.name).localizedCaseInsensitiveCompare(HTMLDecoder.decode($1.name)) == .orderedAscending
            }
            AdaptivePickerRow(
                title: L10n.string("model"),
                items: sortedModels.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: $selectedModelId,
                emptyOption: (0, L10n.string("choose_model"))
            )

            // Status list
            let sortedStatuses = apiClient.statusLabels.sorted {
                displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
            }
            AdaptivePickerRow(
                title: L10n.string("status"),
                items: sortedStatuses.map { (value: $0.id, label: displayName(for: $0)) },
                selection: $selectedStatusId,
                emptyOption: (0, L10n.string("choose_status"))
            )
            if !apiClient.locations.isEmpty {
                let sortedLocations = apiClient.locations.sorted {
                    $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("location_optional"),
                    items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                    selection: Binding(
                        get: { selectedLocationId ?? 0 },
                        set: { selectedLocationId = $0 == 0 ? nil : $0 }
                    ),
                    emptyOption: (0, L10n.string("choose_location"))
                )
            }
            if !apiClient.companies.isEmpty {
                let sortedCompanies = apiClient.companies.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("company_optional"),
                    items: sortedCompanies.map { (value: $0.id, label: $0.name) },
                    selection: Binding(
                        get: { selectedCompanyId ?? 0 },
                        set: { selectedCompanyId = $0 == 0 ? nil : $0 }
                    ),
                    emptyOption: (0, L10n.string("choose_company"))
                )
            }
            Toggle(L10n.string("byod"), isOn: $byod)
        }
    }

    private var purchaseSection: some View {
        Section(header: Text(L10n.string("purchase_warranty"))) {
            TextField(L10n.string("order_number_optional"), text: $orderNumber)
            TextField(L10n.string("purchase_price_optional"), text: $purchaseCost)
                .keyboardType(.decimalPad)
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
                let sortedSuppliers = suppliersFromAssets.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("supplier_optional"),
                    items: sortedSuppliers.map { (value: $0.id, label: $0.name) },
                    selection: Binding(
                        get: { selectedSupplierId ?? 0 },
                        set: { selectedSupplierId = $0 == 0 ? nil : $0 }
                    ),
                    emptyOption: (0, L10n.string("choose_supplier"))
                )
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
                            let sortedOptions = options.sorted {
                                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                            }
                            AdaptivePickerRow(
                                title: key,
                                items: sortedOptions.map { (value: $0, label: $0) },
                                selection: Binding(
                                    get: { customFields[key] ?? "" },
                                    set: { customFields[key] = $0 }
                                ),
                                emptyOption: ("", "—")
                            )
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
        let mappedCustomFields: [String: String] = Dictionary(
            uniqueKeysWithValues: customFields.compactMap { key, rawValue in
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                let apiKey = resolveCustomFieldAPIKey(forDisplayName: key)
                return (apiKey, value)
            }
        )
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
            custom_fields: mappedCustomFields.isEmpty ? nil : mappedCustomFields,
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
            #if DEBUG
            print("AddAssetSheet.saveAsset: model_id=\(selectedModelId), status_id=\(selectedStatusId)")
            #endif
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

    private func resolveCustomFieldAPIKey(forDisplayName displayName: String) -> String {
        guard let def = displayedFieldDefinitions.first(where: { $0.name == displayName }) else {
            return displayName
        }
        if let key = def.field, !key.isEmpty { return key }
        if let key = def.db_field, !key.isEmpty { return key }
        if let key = def.db_column_name, !key.isEmpty { return key }
        if let key = def.db_column, !key.isEmpty { return key }
        let folded = def.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let slugScalars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        let slugRaw = String(slugScalars)
        let slug = slugRaw
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "_snipeit_\(slug)_\(def.id)"
    }

    private func handleDellScanResult(_ result: Result<ScanResult, ScanError>) {
        showingDellScanner = false
        switch result {
        case .success(let scanResult):
            guard let url = URL(string: scanResult.string) else {
                #if DEBUG
                print("Dell QR: invalid URL string")
                #endif
                resultMessage = L10n.string("invalid_dell_qr")
                showResult = true
                return
            }
            Task {
                await handleDellUrl(url)
            }
        case .failure(let error):
            resultMessage = String(format: L10n.string("scan_failed"), error.localizedDescription)
            showResult = true
        }
    }

    private func handleDellUrl(_ url: URL) async {
        // Dell URLs only. Fill serial.
        guard let host = url.host, host.lowercased().contains("dell") else {
            #if DEBUG
            print("Dell QR: not a Dell host")
            #endif
            await MainActor.run {
                resultMessage = L10n.string("invalid_dell_qr")
                showResult = true
            }
            return
        }

        let serviceTag = SnipeITAPIClient.extractDellServiceTag(from: url)

        await MainActor.run {
            guard let tag = serviceTag, !tag.isEmpty else {
                #if DEBUG
                print("Dell QR: no service tag in URL")
                #endif
                resultMessage = L10n.string("invalid_dell_qr")
                showResult = true
                return
            }
            self.serial = tag
        }

        // TechDirect: ship date + warranty if configured
        let clientId = UserDefaults.standard.string(forKey: "dellTechDirectClientId")?.trimmingCharacters(in: .whitespaces) ?? ""
        let clientSecret = UserDefaults.standard.string(forKey: "dellTechDirectClientSecret") ?? ""
        if !clientId.isEmpty, !clientSecret.isEmpty, let tag = serviceTag, !tag.isEmpty {
            do {
                let info = try await DellTechDirectClient.fetchWarrantyInfo(serviceTag: tag, clientId: clientId, clientSecret: clientSecret)
                await MainActor.run {
                    if let ship = info.shipDate {
                        hasPurchaseDate = true
                        purchaseDate = ship
                    }
                    if let months = info.warrantyMonths, months > 0 {
                        warrantyMonths = "\(months)"
                    }
                }
            } catch {
                #if DEBUG
                print("Dell TechDirect: \(error)")
                #endif
            }
        }
    }

    private func extractDellModelName(fromHTML html: String) -> String? {
        guard let titleStart = html.range(of: "<title>")?.upperBound,
              let titleEndSearchRange = html.range(of: "</title>", range: titleStart..<html.endIndex) else {
            return nil
        }
        let title = String(html[titleStart..<titleEndSearchRange.lowerBound])
        let loweredTitle = title.lowercased()
        guard let dellRange = loweredTitle.range(of: "dell ") else { return nil }
        let startIndex = title.index(title.startIndex, offsetBy: title.distance(from: loweredTitle.startIndex, to: dellRange.upperBound))
        let remainder = title[startIndex...]
        let endIndex = remainder.firstIndex(of: "|") ?? remainder.endIndex
        let model = remainder[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? nil : model
    }
}
