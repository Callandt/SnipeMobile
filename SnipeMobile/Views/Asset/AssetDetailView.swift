import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenLocation: ((Location) -> Void)? = nil
    var onOpenLicense: ((License) -> Void)? = nil
    var onOpenAccessory: ((Accessory) -> Void)? = nil
    var onOpenComponent: ((Component) -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    @State private var userId: String = ""
    @State private var assetLicenses: [License] = []
    @State private var assetAccessories: [Accessory] = []
    @State private var assetComponents: [SnipeITAPIClient.AssetAssignedComponent] = []
    @State private var assignedChildAssets: [Asset] = []
    @State private var hasLoggedAppearance = false
    @State private var showEditSheet = false
    @State private var editName: String = ""
    @State private var editAssetTag: String = ""
    @State private var editSerial: String = ""
    @State private var editNotes: String = ""
    @State private var editOrderNumber: String = ""
    @State private var editPurchaseCost: String = ""
    @State private var editBookValue: String = ""
    @State private var editCustomFields: [String: String] = [:]
    @State private var isSaving = false
    @State private var selectedModelId: Int = 0
    @State private var selectedStatusId: Int = 0
    @State private var selectedCategoryId: Int = 0
    @State private var selectedManufacturerId: Int = 0
    @State private var selectedSupplierId: Int = 0
    @State private var selectedCompanyId: Int = 0
    @State private var selectedLocationId: Int = 0
    @State private var editPurchaseDate: Date = Date()
    @State private var editNextAuditDate: Date = Date()
    @State private var editWarrantyExpires: Date = Date()
    @State private var hasPurchaseDate: Bool = false
    @State private var hasNextAuditDate: Bool = false
    @State private var hasWarrantyExpires: Bool = false
    @State private var editExpectedCheckin: Date = Date()
    @State private var editEolDate: Date = Date()
    @State private var editWarrantyMonths: String = ""
    @State private var hasExpectedCheckin: Bool = false
    @State private var hasEolDate: Bool = false
    @State private var showPurchaseDate: Bool = false
    @State private var showNextAuditDate: Bool = false
    @State private var showWarrantyExpires: Bool = false
    @State private var showExpectedCheckin: Bool = false
    @State private var showEolDate: Bool = false
    @State private var showUserPicker = false
    @State private var selectedCheckoutUserId: Int? = nil
    @State private var showCheckoutSheet = false
    @State private var isCheckingIn = false
    @State private var detailImageURL: String? = nil
    @State private var imageDisplayToken = UUID()
    @State private var ephemeralNotice: EphemeralNotice?
    @State private var isGeneratingLabel = false
    @State private var labelPdfURL: URL?
    @State private var showLabelPdf = false
    @State private var showLabelError = false
    @State private var labelErrorMessage = ""
    @AppStorage("showMaintenance") private var showMaintenance: Bool = true

    /// From apiClient or passed in.
    private var currentAsset: Asset {
        apiClient.assets.first { $0.id == asset.id } ?? asset
    }

    private var isDeployed: Bool {
        currentAsset.statusLabel.statusMeta?.lowercased() == "deployed"
    }

    private var resolvedStatusLabel: String? {
        let name = currentAsset.decodedStatusLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawType = currentAsset.statusLabel.type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let localizedType = rawType.isEmpty ? "" : L10n.string("status_type_\(rawType)")
        if !name.isEmpty {
            if !localizedType.isEmpty {
                return "\(name) (\(localizedType))"
            }
            return name
        }
        let meta = currentAsset.statusLabel.statusMeta?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meta.isEmpty ? nil : L10n.statusLabel(meta)
    }

    /// Only deployable statuses can be checked out (matches Snipe-IT).
    private var canCheckOut: Bool {
        if let label = apiClient.statusLabels.first(where: { $0.id == currentAsset.statusLabel.id }) {
            return (label.type?.lowercased() ?? "deployable") == "deployable"
        }
        // fallback before labels load: meta is "deployable" for an assignable, unassigned asset
        return currentAsset.statusLabel.statusMeta?.lowercased() == "deployable"
    }

    private var resolvedImageURL: URL? {
        let fromCache = currentAsset.image?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fromDetail = detailImageURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Cache first; detail fetch may add image URL.
        let rawValue = fromCache.isEmpty ? fromDetail : fromCache
        let cacheBuster = currentAsset.updatedAt?.datetime ?? currentAsset.updatedAt?.date
        return Self.snipeImageURL(baseURL: apiClient.baseURL, path: rawValue, cacheBuster: cacheBuster)
    }

    private static func snipeImageURL(baseURL: String, path: String, cacheBuster: String?) -> URL? {
        guard !path.isEmpty else { return nil }
        let base: URL?
        if let absolute = URL(string: path), absolute.scheme != nil {
            base = absolute
        } else if path.hasPrefix("/") {
            base = URL(string: "\(baseURL)\(path)")
        } else {
            base = nil
        }
        guard let base else { return nil }
        guard let cacheBuster, !cacheBuster.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "v" }
        query.append(URLQueryItem(name: "v", value: cacheBuster))
        components.queryItems = query
        return components.url ?? base
    }

    private var assignedUser: User? {
        guard currentAsset.assignedTo?.isUser == true, let id = currentAsset.assignedTo?.id else { return nil }
        return apiClient.users.first { $0.id == id }
    }

    private var assignedLocation: Location? {
        guard currentAsset.assignedTo?.isLocation == true, let id = currentAsset.assignedTo?.id else { return nil }
        return apiClient.locations.first { $0.id == id }
    }

    private var assignedAsset: Asset? {
        guard currentAsset.assignedTo?.isAsset == true, let id = currentAsset.assignedTo?.id else { return nil }
        return apiClient.assets.first { $0.id == id }
    }

    private var computedWarrantyExpires: String? {
        guard
            let purchaseDateString = currentAsset.purchaseDate?.date,
            let warrantyMonthsRaw = currentAsset.warrantyMonths,
            let warrantyMonths = Int(warrantyMonthsRaw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()),
            warrantyMonths > 0
        else {
            return nil
        }

        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let purchaseDate = inputFormatter.date(from: purchaseDateString) else { return nil }

        guard let expiresDate = Calendar.current.date(byAdding: .month, value: warrantyMonths, to: purchaseDate) else {
            return nil
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .none
        return outputFormatter.string(from: expiresDate)
    }

    private func displayDate(_ dateInfo: DateInfo?) -> String? {
        displayDate(dateInfo, includeTimeWhenAvailable: true)
    }

    private func displayDate(_ dateInfo: DateInfo?, includeTimeWhenAvailable: Bool) -> String? {
        guard let dateInfo = dateInfo else { return nil }
        let sourceValue = (dateInfo.date?.isEmpty == false ? dateInfo.date : dateInfo.formatted) ?? ""
        guard !sourceValue.isEmpty else { return nil }

        let dateFormats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]

        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)

        var parsedDate: Date?
        var includesTime = false
        for format in dateFormats {
            inputFormatter.dateFormat = format
            if let date = inputFormatter.date(from: sourceValue) {
                parsedDate = date
                includesTime = format.contains("H")
                break
            }
        }

        guard let parsedDate = parsedDate else {
            return dateInfo.formatted ?? sourceValue
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .none
        let datePart = outputFormatter.string(from: parsedDate)

        guard includesTime, includeTimeWhenAvailable else { return datePart }

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let timePart = timeFormatter.string(from: parsedDate)
        return "\(datePart) \(L10n.string("date_time_connector")) \(timePart)"
    }

    private var editSheet: some View {
        AssetEditSheet(
            apiClient: apiClient,
            asset: currentAsset,
            isPresented: $showEditSheet,
            editName: $editName,
            editAssetTag: $editAssetTag,
            editSerial: $editSerial,
            editNotes: $editNotes,
            editOrderNumber: $editOrderNumber,
            editPurchaseCost: $editPurchaseCost,
            editBookValue: $editBookValue,
            editCustomFields: $editCustomFields,
            isSaving: $isSaving,
            selectedModelId: $selectedModelId,
            selectedStatusId: $selectedStatusId,
            selectedCategoryId: $selectedCategoryId,
            selectedManufacturerId: $selectedManufacturerId,
            selectedSupplierId: $selectedSupplierId,
            selectedCompanyId: $selectedCompanyId,
            selectedLocationId: $selectedLocationId,
            editPurchaseDate: $editPurchaseDate,
            editNextAuditDate: $editNextAuditDate,
            editWarrantyExpires: $editWarrantyExpires,
            hasPurchaseDate: $hasPurchaseDate,
            hasNextAuditDate: $hasNextAuditDate,
            hasWarrantyExpires: $hasWarrantyExpires,
            editExpectedCheckin: $editExpectedCheckin,
            editEolDate: $editEolDate,
            editWarrantyMonths: $editWarrantyMonths,
            hasExpectedCheckin: $hasExpectedCheckin,
            hasEolDate: $hasEolDate,
            showPurchaseDate: $showPurchaseDate,
            showNextAuditDate: $showNextAuditDate,
            showWarrantyExpires: $showWarrantyExpires,
            showExpectedCheckin: $showExpectedCheckin,
            showEolDate: $showEolDate
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Details", selection: $selectedTab) {
                Text(L10n.string("details")).tag(0)
                Text(L10n.string("history")).tag(1)
                if showMaintenance {
                    Text(L10n.string("maintenance")).tag(2)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 2)

            if selectedTab == 0 {
                detailsView
            } else if selectedTab == 1 {
                HistoryView(itemType: "asset", itemId: currentAsset.id, apiClient: apiClient)
            } else if showMaintenance {
                MaintenanceTab(assetId: currentAsset.id, apiClient: apiClient)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button(action: prepareAndShowEditSheet) {
                    Label(L10n.string("edit"), systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .opacity(isCheckingIn ? 0.5 : 1)
                .allowsHitTesting(!isCheckingIn)
                if isDeployed || isCheckingIn {
                    Button(action: {
                        guard !isCheckingIn else { return }
                        Task { await performCheckin() }
                    }) {
                        Label(L10n.string("check_in"), systemImage: "arrow.down.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .opacity(isCheckingIn ? 0 : 1)
                            .overlay {
                                if isCheckingIn {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                }
                            }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(!isCheckingIn)
                } else if canCheckOut {
                    Button(action: { showCheckoutSheet = true }) {
                        Label(L10n.string("check_out"), systemImage: "arrow.up.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .onAppear { isDetailViewActive = true }
        .onDisappear { isDetailViewActive = false }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(currentAsset.decodedModelName.isEmpty ? currentAsset.decodedName : currentAsset.decodedModelName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if !currentAsset.decodedAssetTag.isEmpty {
                        Button {
                            Task { await generateLabel() }
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                        }
                        .disabled(isGeneratingLabel)
                        .accessibilityLabel(L10n.string("print_label"))
                    }
                    if let url = URL(string: "\(apiClient.baseURL)/hardware/\(currentAsset.id)") {
                        Link(destination: url) {
                            Image(systemName: "safari")
                        }
                    }
                }
            }
        }
        .onAppear {
            selectedTab = 0
            if !hasLoggedAppearance {
                hasLoggedAppearance = true
            }
            Task {
                await apiClient.fetchFieldDefinitions()
                await apiClient.fetchStatusLabels()
                if let fullAsset = await apiClient.fetchHardwareDetails(assetId: currentAsset.id),
                   let image = fullAsset.image,
                   !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailImageURL = image
                }
            }
            Task { await reloadAssignedRelations() }
            selectedModelId = currentAsset.model?.id ?? 0
            // Date init
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let purchaseDateStr = currentAsset.purchaseDate?.date, let d = formatter.date(from: purchaseDateStr) {
                editPurchaseDate = d
                hasPurchaseDate = true
                showPurchaseDate = true
            } else {
                hasPurchaseDate = false
                showPurchaseDate = false
            }
            if let nextAuditDateStr = currentAsset.nextAuditDate?.date, let d = formatter.date(from: nextAuditDateStr) {
                editNextAuditDate = d
                hasNextAuditDate = true
                showNextAuditDate = true
            } else {
                hasNextAuditDate = false
                showNextAuditDate = false
            }
            if let expectedCheckinStr = currentAsset.expectedCheckin?.date, let d = formatter.date(from: expectedCheckinStr) {
                editExpectedCheckin = d
                hasExpectedCheckin = true
                showExpectedCheckin = true
            } else {
                hasExpectedCheckin = false
                showExpectedCheckin = false
            }
            if let eolDateStr = currentAsset.assetEolDate?.date, let d = formatter.date(from: eolDateStr) {
                editEolDate = d
                hasEolDate = true
                showEolDate = true
            } else {
                hasEolDate = false
                showEolDate = false
            }
            // Digits only
            editWarrantyMonths = (currentAsset.warrantyMonths ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        }
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
        .onChange(of: showEditSheet) { _, isShowing in
            if !isShowing {
                Task { await refreshDetailImage() }
            }
        }
        .sheet(isPresented: $showCheckoutSheet) {
            AssetCheckoutSheet(apiClient: apiClient, asset: currentAsset, isPresented: $showCheckoutSheet, onSuccess: {
                await reloadAssignedRelations()
            })
        }
        .onChange(of: currentAsset.id) { _, _ in
            Task { await reloadAssignedRelations() }
        }
        .onChange(of: apiClient.assets.count) { _, _ in
            Task { await reloadAssignedRelations() }
        }
        .onChange(of: showMaintenance) { _, newValue in
            if !newValue, selectedTab == 2 { selectedTab = 0 }
        }
        .ephemeralNotice($ephemeralNotice)
        .overlay {
            if isGeneratingLabel {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.string("generating_labels"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $showLabelPdf, onDismiss: { labelPdfURL = nil }) {
            if let labelPdfURL {
                LabelPdfSheet(pdfURL: labelPdfURL)
            }
        }
        .alert(L10n.string("print_label"), isPresented: $showLabelError) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(labelErrorMessage)
        }
    }

    @MainActor
    private func generateLabel() async {
        let tag = currentAsset.decodedAssetTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            labelErrorMessage = L10n.string("labels_no_asset_tags")
            showLabelError = true
            return
        }
        isGeneratingLabel = true
        defer { isGeneratingLabel = false }

        if let data = await apiClient.generateAssetLabels(assetTags: [tag]) {
            guard let url = LabelPdfSupport.writeTemporaryPdf(data, preferredName: "label-\(tag)") else {
                labelErrorMessage = L10n.string("labels_generate_failed")
                showLabelError = true
                return
            }
            labelPdfURL = url
            showLabelPdf = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            labelErrorMessage = apiClient.lastApiMessage ?? L10n.string("labels_generate_failed")
            showLabelError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func refreshDetailImage() async {
        guard let full = await apiClient.fetchHardwareDetails(assetId: currentAsset.id) else { return }
        apiClient.applyUpdatedAsset(full)
        if let image = full.image?.trimmingCharacters(in: .whitespacesAndNewlines), !image.isEmpty {
            detailImageURL = image
        } else {
            detailImageURL = nil
        }
        imageDisplayToken = UUID()
    }

    @MainActor
    private func performCheckin() async {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        defer { isCheckingIn = false }

        let success = await apiClient.checkinAsset(assetId: currentAsset.id)
        if success {
            await reloadAssignedRelations()
        } else {
            presentEphemeralNotice(
                $ephemeralNotice,
                apiClient.errorMessage ?? L10n.string("checkin_failed"),
                isError: true
            )
        }
    }

    private func reloadAssignedRelations() async {
        async let licenses = apiClient.fetchAssetLicenses(assetId: currentAsset.id)
        async let accessories = apiClient.fetchAssetAccessories(assetId: currentAsset.id)
        async let components = apiClient.fetchAssetComponents(assetId: currentAsset.id)
        async let childAssets = apiClient.fetchAssetAssignedAssets(assetId: currentAsset.id)
        assetLicenses = await licenses
        assetAccessories = await accessories
        assetComponents = await components
        assignedChildAssets = await childAssets
    }

    private func prepareAndShowEditSheet() {
        editName = currentAsset.decodedName
        editAssetTag = currentAsset.decodedAssetTag
        editSerial = currentAsset.decodedSerial
        editNotes = currentAsset.decodedNotes
        editOrderNumber = HTMLDecoder.decode(currentAsset.orderNumber ?? "")
        editPurchaseCost = currentAsset.purchaseCost ?? ""
        let hasPurchaseCost = (currentAsset.purchaseCost?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        editBookValue = hasPurchaseCost ? (currentAsset.bookValue ?? "") : ""
        editCustomFields = [:]
        if let customFields = currentAsset.customFields {
            for (key, field) in customFields {
                editCustomFields[key] = HTMLDecoder.decode(field.value ?? "")
            }
        }
        let modelIds = Set(apiClient.assets.compactMap { $0.model?.id })
        if let modelId = currentAsset.model?.id, modelIds.contains(modelId) {
            selectedModelId = modelId
        } else if let first = modelIds.first {
            selectedModelId = first
        }
        let statusIds = apiClient.statusLabels.map(\.id)
        if statusIds.contains(currentAsset.statusLabel.id) {
            selectedStatusId = currentAsset.statusLabel.id
        } else if let first = apiClient.statusLabels.first?.id {
            selectedStatusId = first
        }
        let categoryIds = Set(apiClient.assets.compactMap { $0.category?.id })
        if let id = currentAsset.category?.id, categoryIds.contains(id) {
            selectedCategoryId = id
        } else if let first = categoryIds.first { selectedCategoryId = first }
        let manufacturerIds = Set(apiClient.assets.compactMap { $0.manufacturer?.id })
        if let id = currentAsset.manufacturer?.id, manufacturerIds.contains(id) {
            selectedManufacturerId = id
        } else if let first = manufacturerIds.first { selectedManufacturerId = first }
        let supplierIds = Set(apiClient.assets.compactMap { $0.supplier?.id })
        if let id = currentAsset.supplier?.id, supplierIds.contains(id) {
            selectedSupplierId = id
        } else if let first = supplierIds.first { selectedSupplierId = first }
        let companyIds = Set(apiClient.assets.compactMap { $0.company?.id })
        if let id = currentAsset.company?.id, companyIds.contains(id) {
            selectedCompanyId = id
        } else if let first = companyIds.first { selectedCompanyId = first }
        let locationIds = Set(apiClient.locations.map(\.id))
        if let id = currentAsset.rtdLocation?.id, locationIds.contains(id) {
            selectedLocationId = id
        } else if let id = currentAsset.location?.id, locationIds.contains(id) {
            selectedLocationId = id
        } else {
            selectedLocationId = 0
        }
        hasPurchaseDate = currentAsset.purchaseDate?.date != nil
        hasNextAuditDate = currentAsset.nextAuditDate?.date != nil
        hasEolDate = currentAsset.assetEolDate?.date != nil
        hasExpectedCheckin = currentAsset.expectedCheckin?.date != nil
        // Next run loop. Avoids concurrent state assert.
        DispatchQueue.main.async {
            showEditSheet = true
        }
    }

    private var detailsView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ScrollView {
                    VStack(spacing: 15) {
                        if let imageURL = resolvedImageURL {
                            VStack(spacing: 10) {
                                Text(L10n.string("image"))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 220)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    case .failure(_):
                                        Image(systemName: "photo")
                                            .font(.system(size: 36))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, minHeight: 140)
                                    case .empty:
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 140)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .id(imageDisplayToken)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        Text(L10n.string("device_info"))
                            .font(.headline)
                            .foregroundColor(.primary)
                        VStack(spacing: 10) {
                            if !currentAsset.decodedAssetTag.isEmpty {
                                copyableDetailRow(label: L10n.string("asset_tag"), value: currentAsset.decodedAssetTag)
                            }
                            if !currentAsset.decodedSerial.isEmpty {
                                copyableDetailRow(label: L10n.string("serial_number"), value: currentAsset.decodedSerial)
                            }
                            if !currentAsset.decodedName.isEmpty,
                               currentAsset.decodedName != currentAsset.decodedModelName {
                                copyableDetailRow(label: L10n.string("name"), value: currentAsset.decodedName)
                            }
                            if !currentAsset.decodedModelName.isEmpty {
                                copyableDetailRow(label: L10n.string("model"), value: currentAsset.decodedModelName)
                            }
                            if !currentAsset.decodedManufacturerName.isEmpty {
                                copyableDetailRow(label: L10n.string("manufacturer"), value: currentAsset.decodedManufacturerName)
                            }
                            if !currentAsset.decodedSupplierName.isEmpty {
                                copyableDetailRow(label: L10n.string("supplier_optional"), value: currentAsset.decodedSupplierName)
                            }
                            if let statusLabel = resolvedStatusLabel {
                                copyableDetailRow(label: L10n.string("status"), value: statusLabel)
                            }
                            if !currentAsset.decodedCategoryName.isEmpty {
                                copyableDetailRow(label: L10n.string("category"), value: currentAsset.decodedCategoryName)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        // Assigned To.
                        if let assignedTo = currentAsset.assignedTo,
                           currentAsset.statusLabel.statusMeta?.lowercased() == "deployed"
                           || !currentAsset.decodedAssignedToName.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L10n.string("assigned_to"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                if let user = assignedUser {
                                    Button { onOpenUser?(user) } label: {
                                        AssignedUserCard(user: user)
                                    }
                                    .buttonStyle(.plain)
                                } else if let loc = assignedLocation {
                                    Button { onOpenLocation?(loc) } label: {
                                        AssignedLocationCard(location: loc)
                                    }
                                    .buttonStyle(.plain)
                                } else if let assignedAsset {
                                    Button { onOpenAsset?(assignedAsset) } label: {
                                        AssignedAssetCard(asset: assignedAsset)
                                    }
                                    .buttonStyle(.plain)
                                } else if assignedTo.isLocation {
                                    AssignedLocationCard(location: Location(id: assignedTo.id, name: currentAsset.decodedAssignedToName))
                                } else if assignedTo.isAsset {
                                    AssignedAssetCard(asset: nil, fallbackTitle: currentAsset.decodedAssignedToName)
                                } else {
                                    AssignedUserCard(user: nil, fallbackName: currentAsset.decodedAssignedToName)
                                }
                            }
                            .padding(.top, 5)
                        }

                        if !assignedChildAssets.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L10n.string("assigned_assets"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                VStack(spacing: 12) {
                                    ForEach(assignedChildAssets) { childAsset in
                                        Button { onOpenAsset?(childAsset) } label: {
                                            AssignedAssetCard(asset: childAsset)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 5)
                        }

                        if !assetLicenses.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L10n.string("tab_licenses"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                VStack(spacing: 12) {
                                    ForEach(assetLicenses) { license in
                                        Button { onOpenLicense?(license) } label: {
                                            AssignedLicenseCard(license: license)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 5)
                        }

                        if !assetAccessories.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L10n.string("tab_accessories"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                VStack(spacing: 12) {
                                    ForEach(assetAccessories) { accessory in
                                        Button { onOpenAccessory?(accessory) } label: {
                                            AssignedAccessoryCard(accessory: accessory)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 5)
                        }

                        if !assetComponents.isEmpty {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L10n.string("tab_components"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                VStack(spacing: 12) {
                                    ForEach(assetComponents) { row in
                                        Button { onOpenComponent?(row.component) } label: {
                                            AssignedComponentCard(component: row.component, quantity: row.assignedQty)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 5)
                        }

                        // Date fields
                        let hasAnyDate =
                            (currentAsset.purchaseDate?.formatted?.isEmpty == false) ||
                            (currentAsset.nextAuditDate?.formatted?.isEmpty == false) ||
                            (currentAsset.expectedCheckin?.formatted?.isEmpty == false) ||
                            (currentAsset.assetEolDate?.formatted?.isEmpty == false) ||
                            (computedWarrantyExpires?.isEmpty == false) ||
                            (currentAsset.lastAuditDate?.formatted?.isEmpty == false) ||
                            (currentAsset.lastCheckout?.formatted?.isEmpty == false) ||
                            (currentAsset.lastCheckin?.formatted?.isEmpty == false)
                        if hasAnyDate {
                            Text(L10n.string("dates"))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                if let v = displayDate(currentAsset.purchaseDate), !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("purchase_date"), value: v)
                                }
                                if let v = currentAsset.nextAuditDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("next_audit_date"), value: v)
                                }
                                if let v = currentAsset.expectedCheckin?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("expected_checkin"), value: v)
                                }
                                if let v = computedWarrantyExpires, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("warranty_expires"), value: v)
                                }
                                if let v = displayDate(currentAsset.assetEolDate), !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("eol_date"), value: v)
                                }
                                if let v = currentAsset.lastAuditDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("last_audit_date"), value: v)
                                }
                                if let v = displayDate(currentAsset.lastCheckout, includeTimeWhenAvailable: false), !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("last_checkout"), value: v)
                                }
                                if let v = currentAsset.lastCheckin?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("last_checkin"), value: v)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        // Value Info if any
                        let hasPurchaseCost = (currentAsset.purchaseCost?.isEmpty == false)
                        let hasValueInfo = hasPurchaseCost || (currentAsset.orderNumber?.isEmpty == false)
                        if hasValueInfo {
                            Text(L10n.string("value_info"))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                if let purchaseCost = currentAsset.purchaseCost, !purchaseCost.isEmpty {
                                    copyableDetailRow(label: L10n.string("purchase_cost"), value: purchaseCost, copyValue: normalizeDecimalForCopy(purchaseCost))
                                }
                                if hasPurchaseCost, let bookValue = currentAsset.bookValue, !bookValue.isEmpty {
                                    copyableDetailRow(label: L10n.string("book_value"), value: bookValue, copyValue: normalizeDecimalForCopy(bookValue))
                                }
                                if let orderNumber = currentAsset.orderNumber, !orderNumber.isEmpty {
                                    copyableDetailRow(label: L10n.string("order_number"), value: orderNumber)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        if let customFields = currentAsset.customFields,
                           customFields.contains(where: { ($0.value.value ?? "").isEmpty == false }) {
                            Text(L10n.string("custom_fields"))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                ForEach(customFields.keys.sorted(), id: \.self) { key in
                                    if let value = customFields[key]?.value, !value.isEmpty {
                                        copyableDetailRow(label: key, value: value)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal)
                }
            }
        }
    }
    
    /// Strip thousand separators. Keep comma.
    private func normalizeDecimalForCopy(_ value: String) -> String {
        value.replacingOccurrences(of: ".", with: "")
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String, copyValue: String? = nil) -> some View {
        let toCopy = copyValue ?? value
        let isSingleToken = !value.contains(" ")
        VStack(alignment: .leading, spacing: 4) {
            Text(label).bold()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(isSingleToken ? 1 : nil)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = toCopy
            }) {
                Label(L10n.string("copy"), systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
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
                Picker("Model", selection: $selectedModelId) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.model?.id }).sorted()), id: \.self) { id in
                        if let model = apiClient.assets.first(where: { $0.model?.id == id })?.model {
                            Text(HTMLDecoder.decode(model.name)).tag(model.id)
                        }
                    }
                }
                .onChange(of: selectedModelId) { _, newValue in
                    Task { await apiClient.fetchModelFieldDefinitions(modelId: newValue) }
                }
            }
            Picker("Status", selection: Binding(
                get: { currentAsset.statusLabel.id },
                set: { _ in /* status change not yet implemented */ }
            )) {
                Text(currentAsset.statusLabel.name).tag(currentAsset.statusLabel.id)
            }
            if !apiClient.assets.isEmpty {
                Picker("Category", selection: Binding(
                    get: { currentAsset.category?.id ?? 0 },
                    set: { _ in /* category change not yet implemented */ }
                )) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.category?.id }).sorted()), id: \.self) { id in
                        if let cat = apiClient.assets.first(where: { $0.category?.id == id })?.category {
                            Text(cat.name).tag(cat.id)
                        }
                    }
                }
            }
            if !apiClient.assets.isEmpty {
                Picker("Manufacturer", selection: Binding(
                    get: { currentAsset.manufacturer?.id ?? 0 },
                    set: { _ in /* manufacturer change not yet implemented */ }
                )) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.manufacturer?.id }).sorted()), id: \.self) { id in
                        if let man = apiClient.assets.first(where: { $0.manufacturer?.id == id })?.manufacturer {
                            Text(man.name).tag(man.id)
                        }
                    }
                }
            }
            if !apiClient.assets.isEmpty {
                Picker(L10n.string("supplier_optional"), selection: Binding(
                    get: { currentAsset.supplier?.id ?? 0 },
                    set: { _ in /* supplier change not yet implemented */ }
                )) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.supplier?.id }).sorted()), id: \.self) { id in
                        if let sup = apiClient.assets.first(where: { $0.supplier?.id == id })?.supplier {
                            Text(sup.name).tag(sup.id)
                        }
                    }
                }
            }
            if !apiClient.assets.isEmpty {
                Picker(L10n.string("company_optional"), selection: Binding(
                    get: { currentAsset.company?.id ?? 0 },
                    set: { _ in /* company change not yet implemented */ }
                )) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.company?.id }).sorted()), id: \.self) { id in
                        if let comp = apiClient.assets.first(where: { $0.company?.id == id })?.company {
                            Text(comp.name).tag(comp.id)
                        }
                    }
                }
            }
            if !apiClient.locations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("default_location"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker(L10n.string("default_location"), selection: Binding(
                        get: { currentAsset.location?.id ?? 0 },
                        set: { _ in /* location change not yet geïmplementeerd */ }
                    )) {
                        ForEach(apiClient.locations, id: \.id) { loc in
                            Text(loc.name).tag(loc.id)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
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
                HStack {
                    TextField("", text: $editWarrantyMonths)
                        .keyboardType(.numberPad)
                    Text(L10n.string("months"))
                        .foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("purchase_date"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if hasPurchaseDate {
                    DatePicker("", selection: $editPurchaseDate, displayedComponents: .date)
                        .labelsHidden()
                } else {
                    Toggle(L10n.string("set_purchase_date"), isOn: $showPurchaseDate)
                        .font(.caption)
                    if showPurchaseDate {
                        DatePicker("", selection: $editPurchaseDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("expected_checkin_date"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if hasExpectedCheckin {
                    DatePicker("", selection: $editExpectedCheckin, displayedComponents: .date)
                        .labelsHidden()
                } else {
                    Toggle(L10n.string("set_expected_checkin"), isOn: $showExpectedCheckin)
                        .font(.caption)
                    if showExpectedCheckin {
                        DatePicker("", selection: $editExpectedCheckin, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("EOL Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if hasEolDate {
                    DatePicker("", selection: $editEolDate, displayedComponents: .date)
                        .labelsHidden()
                } else {
                    Toggle(L10n.string("set_eol_date"), isOn: $showEolDate)
                        .font(.caption)
                    if showEolDate {
                        DatePicker("", selection: $editEolDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Next Audit Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if hasNextAuditDate {
                    DatePicker("", selection: $editNextAuditDate, displayedComponents: .date)
                        .labelsHidden()
                } else {
                    Toggle(L10n.string("set_next_audit"), isOn: $showNextAuditDate)
                        .font(.caption)
                    if showNextAuditDate {
                        DatePicker("", selection: $editNextAuditDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section(header: Text("Notes")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $editNotes)
                    .frame(minHeight: 60)
            }
        }
    }

    @ViewBuilder
    private var customFieldsSection: some View {
        Section(header: Text("Custom Fields")) {
            let customFieldDefs = apiClient.modelFieldDefinitions ?? apiClient.fieldDefinitions
            if editCustomFields.isEmpty {
                Text("No custom fields")
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(editCustomFields.keys.sorted()), id: \.self) { key in
                    if let fieldDef = customFieldDefs.first(where: { $0.name == key }), fieldDef.type == "listbox", let options = fieldDef.field_values_array {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker(key, selection: Binding(
                                get: { editCustomFields[key] ?? "" },
                                set: { editCustomFields[key] = $0 }
                            )) {
                                ForEach(options, id: \.self) { option in
                                    Text(option).tag(option)
                                }
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
    }
} 
