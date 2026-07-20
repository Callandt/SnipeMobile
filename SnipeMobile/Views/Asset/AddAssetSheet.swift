import SwiftUI

struct AddAssetSheet: View {
    private enum CheckoutTargetType: String, CaseIterable, Identifiable {
        case user
        case location
        var id: String { rawValue }
    }

    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    /// Dell QR URL to pre-fill serial (+ purchase date and warranty via TechDirect when set).
    var prefilledDellURL: URL? = nil
    /// Plain serial pre-fill when no Dell URL is available.
    var prefilledSerial: String? = nil
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
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var checkOutAfterCreate = false
    @State private var checkoutTargetType: CheckoutTargetType = .user
    @State private var selectedCheckoutUserId: Int?
    @State private var selectedCheckoutLocationId: Int?
    @State private var customFields: [String: String] = [:]
    @State private var displayedFieldDefinitions: [SnipeITAPIClient.FieldDefinition] = []
    @State private var isSaving = false
    @State private var resultMessage = ""
    @State private var showResult = false
    @State private var showingDellScanner = false
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true
    @AppStorage("autoFillAssetTag") private var autoFillAssetTag: Bool = true

    private var selectedModelRequiresSerial: Bool {
        guard selectedModelId != 0 else { return false }
        return apiClient.models.first { $0.id == selectedModelId }?.requireSerial ?? false
    }

    private var canSave: Bool {
        !assetTag.trimmingCharacters(in: .whitespaces).isEmpty
            && selectedModelId != 0
            && selectedStatusId != 0
            && (!selectedModelRequiresSerial || !serial.trimmingCharacters(in: .whitespaces).isEmpty)
            && (!checkOutAfterCreate || checkoutSelectionIsValid)
    }

    /// Next asset tag. Uses Snipe-IT prefix/zerofill when configured.
    private var nextAvailableAssetTag: String {
        apiClient.nextAvailableAssetTag()
    }

    private var selectedStatusIsDeployable: Bool {
        guard let status = apiClient.statusLabels.first(where: { $0.id == selectedStatusId }) else { return false }
        let type = status.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !type.isEmpty { return type == "deployable" }
        let meta = status.statusMeta?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return meta == "deployable"
    }

    private var checkoutSelectionIsValid: Bool {
        guard selectedStatusIsDeployable else { return true }
        switch checkoutTargetType {
        case .user: return selectedCheckoutUserId != nil
        case .location: return selectedCheckoutLocationId != nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                if selectedStatusIsDeployable {
                    checkoutSection
                }
                purchaseSection
                AssetPhotoSection(selectedImage: $selectedImage, showCamera: $showCamera)
                notesSection
                customFieldsSection
            }
            .navigationTitle(L10n.string("new_asset"))
            .toolbar { toolbarContent }
            .onAppear(perform: setupOnAppear)
            .onChange(of: apiClient.assets) { _, _ in
                if autoFillAssetTag {
                    assetTag = nextAvailableAssetTag
                }
            }
            .task(id: selectedModelId) {
                await loadAndDisplayCustomFieldsForModel()
            }
            .onChange(of: selectedStatusId) { _, _ in
                if !selectedStatusIsDeployable {
                    checkOutAfterCreate = false
                    selectedCheckoutUserId = nil
                    selectedCheckoutLocationId = nil
                }
            }
            .alert(L10n.string("error"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(resultMessage)
            }
            .assetCameraCover(isPresented: $showCamera, image: $selectedImage)
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
        // Only prefill the tag when auto-fill is enabled; otherwise the user types it.
        assetTag = autoFillAssetTag ? nextAvailableAssetTag : ""
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
        Task { await apiClient.fetchAssetTagSettings() }
        // Status stays unset
        if apiClient.companies.isEmpty {
            Task { await apiClient.fetchCompanies() }
        }
        if apiClient.locations.isEmpty {
            Task { await apiClient.fetchLocations() }
        }
        if apiClient.suppliers.isEmpty {
            Task { await apiClient.fetchSuppliers() }
        }
        if apiClient.users.isEmpty {
            Task { await apiClient.fetchUsers() }
        }

        // Reuse handleDellUrl so pre-fill matches the in-sheet scan flow.
        if let dellURL = prefilledDellURL {
            Task { await handleDellUrl(dellURL) }
        } else if let s = prefilledSerial?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            serial = s
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
                next[d.name] = SnipeITAPIClient.initialCustomFieldValue(
                    existing: customFields[d.name],
                    defaultValue: d.default_value
                )
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
                    next[d.name] = SnipeITAPIClient.initialCustomFieldValue(
                        existing: customFields[d.name],
                        defaultValue: d.default_value
                    )
                }
                customFields = next
            }
        }
    }

    private var generalSection: some View {
        Section(header: Text(L10n.string("general"))) {
            TextField(L10n.string("name"), text: $name)
            if autoFillAssetTag {
                HStack {
                    Text(L10n.fieldLabel("asset_tag", required: true))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(assetTag.isEmpty ? nextAvailableAssetTag : assetTag)
                        .foregroundStyle(.primary)
                }
            } else {
                TextField(L10n.fieldLabel("asset_tag", required: true), text: $assetTag)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            TextField(
                L10n.fieldLabel("serial", required: selectedModelRequiresSerial),
                text: $serial
            )
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
            CreatableAdaptivePickerRow(
                title: L10n.fieldLabel("model", required: true),
                items: sortedModels.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: $selectedModelId,
                emptyOption: (0, L10n.string("choose_model")),
                apiClient: apiClient,
                creatableEntity: .models
            )

            // Status list
            let sortedStatuses = apiClient.statusLabels.sorted {
                displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
            }
            CreatableAdaptivePickerRow(
                title: L10n.fieldLabel("status", required: true),
                items: sortedStatuses.map { (value: $0.id, label: displayName(for: $0)) },
                selection: $selectedStatusId,
                emptyOption: (0, L10n.string("choose_status")),
                apiClient: apiClient,
                creatableEntity: .statusLabels
            )

            let sortedLocations = apiClient.locations.sorted {
                $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending
            }
            CreatableAdaptivePickerRow(
                title: L10n.string("default_location"),
                items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                selection: Binding(
                    get: { selectedLocationId ?? 0 },
                    set: { selectedLocationId = $0 == 0 ? nil : $0 }
                ),
                emptyOption: (0, L10n.string("choose_default_location")),
                apiClient: apiClient,
                creatableLocation: true
            )
            let sortedCompanies = apiClient.companies.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            CreatableAdaptivePickerRow(
                title: L10n.string("company"),
                items: sortedCompanies.map { (value: $0.id, label: $0.name) },
                selection: Binding(
                    get: { selectedCompanyId ?? 0 },
                    set: { selectedCompanyId = $0 == 0 ? nil : $0 }
                ),
                emptyOption: (0, L10n.string("choose_company")),
                apiClient: apiClient,
                creatableEntity: .companies
            )
            Toggle(L10n.string("byod"), isOn: $byod)
        }
    }

    private var checkoutSection: some View {
        Section {
            Toggle(L10n.string("check_out"), isOn: $checkOutAfterCreate)

            if checkOutAfterCreate {
                Picker("", selection: $checkoutTargetType) {
                    Text(L10n.string("user")).tag(CheckoutTargetType.user)
                    Text(L10n.string("location")).tag(CheckoutTargetType.location)
                }
                .pickerStyle(.segmented)

                if checkoutTargetType == .user {
                    let sortedUsers = apiClient.users.sorted {
                        $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending
                    }
                    AdaptivePickerRow(
                        title: L10n.string("select_user_short"),
                        items: sortedUsers.map { (value: $0.id, label: $0.decodedName) },
                        selection: Binding(
                            get: { selectedCheckoutUserId ?? 0 },
                            set: { selectedCheckoutUserId = $0 == 0 ? nil : $0 }
                        ),
                        emptyOption: (0, L10n.string("select_user"))
                    )
                } else {
                    let sortedLocations = apiClient.locations.sorted {
                        $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending
                    }
                    AdaptivePickerRow(
                        title: L10n.string("select_location_short"),
                        items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                        selection: Binding(
                            get: { selectedCheckoutLocationId ?? 0 },
                            set: { selectedCheckoutLocationId = $0 == 0 ? nil : $0 }
                        ),
                        emptyOption: (0, L10n.string("choose_location"))
                    )
                }
            }
        }
    }

    private var purchaseSection: some View {
        Section(header: Text(L10n.string("purchase_warranty"))) {
            TextField(L10n.string("order_number"), text: $orderNumber)
            TextField(L10n.string("purchase_price"), text: $purchaseCost)
                .keyboardType(.decimalPad)
            Toggle(L10n.string("purchase_date"), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
            }
            Toggle(L10n.string("eol_date"), isOn: $hasEolDate)
            if hasEolDate {
                DatePicker("", selection: $eolDate, displayedComponents: .date)
            }
            TextField(L10n.string("warranty_months"), text: $warrantyMonths)
                .keyboardType(.numberPad)
            let sortedSuppliers = apiClient.suppliers.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            CreatableAdaptivePickerRow(
                title: L10n.string("supplier"),
                items: sortedSuppliers.map { (value: $0.id, label: $0.name) },
                selection: Binding(
                    get: { selectedSupplierId ?? 0 },
                    set: { selectedSupplierId = $0 == 0 ? nil : $0 }
                ),
                emptyOption: (0, L10n.string("choose_supplier")),
                apiClient: apiClient,
                creatableEntity: .suppliers
            )
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
            newFields[field.name] = SnipeITAPIClient.initialCustomFieldValue(
                existing: customFields[field.name],
                defaultValue: nil
            )
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
            let createResult = await apiClient.createAsset(req, image: selectedImage)
            let assetCreated = createResult.success
            var success = assetCreated
            let tagSent = assetTag.trimmingCharacters(in: .whitespaces)

            if assetCreated, checkOutAfterCreate, selectedStatusIsDeployable {
                let createdAssetId = createResult.assetId
                    ?? apiClient.assets.first(where: {
                        $0.decodedAssetTag.caseInsensitiveCompare(tagSent) == .orderedSame
                    })?.id
                if let createdAssetId {
                    var checkoutBody: [String: Any] = [
                        "name": nameToSend,
                        "note": notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    ]
                    switch checkoutTargetType {
                    case .user:
                        if let userId = selectedCheckoutUserId {
                            checkoutBody["assigned_user"] = userId
                            checkoutBody["checkout_to_type"] = "user"
                            success = await apiClient.checkoutAssetCustom(assetId: createdAssetId, body: checkoutBody)
                        } else {
                            success = false
                        }
                    case .location:
                        if let locationId = selectedCheckoutLocationId {
                            checkoutBody["assigned_location"] = locationId
                            checkoutBody["checkout_to_type"] = "location"
                            success = await apiClient.checkoutAssetCustom(assetId: createdAssetId, body: checkoutBody)
                        } else {
                            success = false
                        }
                    }
                    #if DEBUG
                    print("AddAssetSheet.checkout: assetId=\(createdAssetId) success=\(success) message=\(apiClient.lastApiMessage ?? "")")
                    #endif
                } else {
                    success = false
                    await MainActor.run {
                        apiClient.lastApiMessage = L10n.string("checkout_failed")
                    }
                }
            }
            if success {
                // Already inserted in memory by createAsset; sync the rest in the
                // background so the sheet can close right away.
                Task { await apiClient.fetchAssets() }
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
        let clientId = KeychainSecretStore.string(for: .dellTechDirectClientId).trimmingCharacters(in: .whitespaces)
        let clientSecret = KeychainSecretStore.string(for: .dellTechDirectClientSecret)
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
