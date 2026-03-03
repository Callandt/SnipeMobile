import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenLocation: ((Location) -> Void)? = nil
    @State private var userId: String = ""
    @Environment(\.dismiss) var dismiss
    @State private var hasLoggedAppearance = false
    @State private var copyNotification: String?
    @State private var showCopyNotification = false
    @State private var userDetailTab: Int = 0
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
    @State private var showCheckInOutResult = false
    @State private var checkInOutSuccess = false
    @State private var checkInOutMessage = ""
    @State private var showCheckoutSheet = false

    /// Huidige asset uit apiClient (na edit/check-in/check-out), anders de doorgegegeven asset.
    private var currentAsset: Asset {
        apiClient.assets.first { $0.id == asset.id } ?? asset
    }

    private var assignedUser: User? {
        guard currentAsset.assignedTo?.type == "user", let id = currentAsset.assignedTo?.id else { return nil }
        return apiClient.users.first { $0.id == id }
    }

    private var assignedLocation: Location? {
        guard currentAsset.assignedTo?.type == "location", let id = currentAsset.assignedTo?.id else { return nil }
        return apiClient.locations.first { $0.id == id }
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
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 2)

            if selectedTab == 0 {
                detailsView
            } else {
                HistoryView(itemType: "asset", itemId: currentAsset.id, apiClient: apiClient)
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
                if currentAsset.statusLabel.statusMeta?.lowercased() == "deployed" {
                    Button(action: {
                        Task {
                            let success = await apiClient.checkinAsset(assetId: currentAsset.id)
                            checkInOutSuccess = success
                            checkInOutMessage = success ? "Check-in successful!" : (apiClient.errorMessage ?? "Check-in failed.")
                            showCheckInOutResult = true
                            if success { Task { await apiClient.fetchPrimaryThenBackground() } }
                        }
                    }) {
                        Label(L10n.string("check_in"), systemImage: "arrow.down.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                } else {
                    Button(action: { showCheckoutSheet = true }) {
                        Label(L10n.string("check_out"), systemImage: "arrow.up.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .controlSize(.large)
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
        .navigationBarBackButtonHidden(returnToTab != nil)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(currentAsset.decodedModelName.isEmpty ? currentAsset.decodedName : currentAsset.decodedModelName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let _ = returnToTab, let onBack = onBackToPrevious {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onBack()
                    } label: {
                        Label(L10n.string("back"), systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/hardware/\(currentAsset.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
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
            }
            selectedModelId = currentAsset.model?.id ?? 0
            // Init date fields
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
            // Alleen cijfers tonen in warranty months
            editWarrantyMonths = (currentAsset.warrantyMonths ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        }
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width > 100 {
                        dismiss()
                    }
                }
        )
        .sheet(isPresented: $showEditSheet) {
            editSheet
        }
        .sheet(isPresented: $showCheckoutSheet) {
            AssetCheckoutSheet(apiClient: apiClient, asset: currentAsset, isPresented: $showCheckoutSheet, onSuccess: { Task { await apiClient.fetchPrimaryThenBackground() } })
        }
        .alert(isPresented: $showCheckInOutResult) {
            Alert(title: Text(checkInOutSuccess ? L10n.string("success") : L10n.string("error")), message: Text(checkInOutMessage), dismissButton: .default(Text(L10n.string("ok"))))
        }
    }

    private func prepareAndShowEditSheet() {
        editName = currentAsset.name
        editAssetTag = currentAsset.assetTag
        editSerial = currentAsset.serial ?? ""
        editNotes = currentAsset.notes ?? ""
        editOrderNumber = currentAsset.orderNumber ?? ""
        editPurchaseCost = currentAsset.purchaseCost ?? ""
        editBookValue = currentAsset.bookValue ?? ""
        editCustomFields = [:]
        if let customFields = currentAsset.customFields {
            for (key, field) in customFields {
                editCustomFields[key] = field.value ?? ""
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
        if let id = currentAsset.location?.id, locationIds.contains(id) {
            selectedLocationId = id
        } else if let first = apiClient.locations.first?.id {
            selectedLocationId = first
        }
        hasPurchaseDate = currentAsset.purchaseDate?.date != nil
        hasNextAuditDate = currentAsset.nextAuditDate?.date != nil
        hasEolDate = currentAsset.assetEolDate?.date != nil
        hasExpectedCheckin = currentAsset.expectedCheckin?.date != nil
        // Sheet op volgende runloop tonen om SwiftUI-assert/breakpoint bij gelijktijdige state-updates te vermijden
        DispatchQueue.main.async {
            showEditSheet = true
        }
    }

    private var detailsView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if showCopyNotification, let text = copyNotification {
                    Text(L10n.string("copied", text))
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(8)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showCopyNotification = false
                                }
                            }
                        }
                }
                
                ScrollView {
                    VStack(spacing: 15) {
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
                            if !currentAsset.decodedModelName.isEmpty {
                                copyableDetailRow(label: L10n.string("model"), value: currentAsset.decodedModelName)
                            }
                            if !currentAsset.decodedManufacturerName.isEmpty {
                                copyableDetailRow(label: L10n.string("manufacturer"), value: currentAsset.decodedManufacturerName)
                            }
                            if let statusMeta = currentAsset.statusLabel.statusMeta, !statusMeta.isEmpty {
                                copyableDetailRow(label: L10n.string("status"), value: L10n.statusLabel(statusMeta))
                            }
                            if !currentAsset.decodedCategoryName.isEmpty {
                                copyableDetailRow(label: L10n.string("category"), value: currentAsset.decodedCategoryName)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        // Assigned To Section (zelfde opmaak als Accessory detail: grijze kaart, icoon + naam + chevron)
                        if currentAsset.statusLabel.statusMeta?.lowercased() == "deployed", currentAsset.assignedTo != nil {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L10n.string("assigned_to"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                if let user = assignedUser {
                                    Button { onOpenUser?(user) } label: {
                                        HStack {
                                            Image(systemName: "person.circle")
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 30, height: 30)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(user.decodedName)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                if !user.decodedEmail.isEmpty {
                                                    Text(user.decodedEmail)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                }
                                                if !user.decodedLocationName.isEmpty {
                                                    Text(user.decodedLocationName)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                } else if let loc = assignedLocation {
                                    Button { onOpenLocation?(loc) } label: {
                                        HStack {
                                            Image(systemName: "mappin.and.ellipse")
                                                .foregroundStyle(.tertiary)
                                                .frame(width: 30, height: 30)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(HTMLDecoder.decode(loc.name))
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                            }
                            .padding(.top, 5)
                        }
                        // --- DATUMVELDEN ---
                        let hasAnyDate =
                            (currentAsset.purchaseDate?.formatted?.isEmpty == false) ||
                            (currentAsset.nextAuditDate?.formatted?.isEmpty == false) ||
                            (currentAsset.expectedCheckin?.formatted?.isEmpty == false) ||
                            (currentAsset.assetEolDate?.formatted?.isEmpty == false) ||
                            (currentAsset.lastAuditDate?.formatted?.isEmpty == false) ||
                            (currentAsset.lastCheckout?.formatted?.isEmpty == false) ||
                            (currentAsset.lastCheckin?.formatted?.isEmpty == false)
                        if hasAnyDate {
                            Text(L10n.string("dates"))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                if let v = currentAsset.purchaseDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("purchase_date"), value: v)
                                }
                                if let v = currentAsset.nextAuditDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("next_audit_date"), value: v)
                                }
                                if let v = currentAsset.expectedCheckin?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("expected_checkin"), value: v)
                                }
                                if let v = currentAsset.assetEolDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("eol_date"), value: v)
                                }
                                if let v = currentAsset.lastAuditDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: L10n.string("last_audit_date"), value: v)
                                }
                                if let v = currentAsset.lastCheckout?.formatted, !v.isEmpty {
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

                        // Value Info alleen tonen als er minstens één waarde is
                        let hasValueInfo = (currentAsset.purchaseCost?.isEmpty == false) || (currentAsset.bookValue?.isEmpty == false) || (currentAsset.orderNumber?.isEmpty == false)
                        if hasValueInfo {
                            Text(L10n.string("value_info"))
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                if let purchaseCost = currentAsset.purchaseCost, !purchaseCost.isEmpty {
                                    copyableDetailRow(label: L10n.string("purchase_cost"), value: purchaseCost, copyValue: normalizeDecimalForCopy(purchaseCost))
                                }
                                if let bookValue = currentAsset.bookValue, !bookValue.isEmpty {
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
    
    /// Voor aankoopprijs/boekwaarde: alleen duizendtal-punten verwijderen; komma blijft komma (1.630,86 → 1630,86).
    private func normalizeDecimalForCopy(_ value: String) -> String {
        value.replacingOccurrences(of: ".", with: "")
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String, copyValue: String? = nil) -> some View {
        let toCopy = copyValue ?? value
        HStack {
            Text(label).bold()
            Spacer()
            Text(value)
            Button(action: {
                UIPasteboard.general.string = toCopy
                withAnimation {
                    copyNotification = label
                    showCopyNotification = true
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
                    .imageScale(.small)
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
                Picker("Supplier", selection: Binding(
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
                Picker("Company", selection: Binding(
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
                    Text("Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Location", selection: Binding(
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
