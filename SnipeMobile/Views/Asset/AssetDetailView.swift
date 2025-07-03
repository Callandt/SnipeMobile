import SwiftUI

struct AssetDetailView: View {
    let asset: Asset
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
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
    @State private var showSaveSuccess = false
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

    private var assignedUser: User? {
        guard let assignedToId = asset.assignedTo?.id else { return nil }
        return apiClient.users.first { $0.id == assignedToId }
    }

    private var editSheet: some View {
        AssetEditSheet(
            apiClient: apiClient,
            asset: asset,
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
            showSaveSuccess: $showSaveSuccess,
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
                Text("Details").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            if selectedTab == 0 {
                detailsView
            } else {
                HistoryView(itemType: "asset", itemId: asset.id, apiClient: apiClient)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(action: {
                    editName = asset.name
                    editAssetTag = asset.assetTag
                    editSerial = asset.serial ?? ""
                    editNotes = asset.notes ?? ""
                    editOrderNumber = asset.orderNumber ?? ""
                    editPurchaseCost = asset.purchaseCost ?? ""
                    editBookValue = asset.bookValue ?? ""
                    editCustomFields = [:]
                    if let customFields = asset.customFields {
                        for (key, field) in customFields {
                            editCustomFields[key] = field.value ?? ""
                        }
                    }
                    // Initialiseer selectievariabelen voor alle pickers
                    if let modelId = asset.model?.id {
                        selectedModelId = modelId
                    } else if let firstModel = apiClient.assets.compactMap({ $0.model?.id }).first {
                        selectedModelId = firstModel
                    }
                    if let statusId = asset.statusLabel.id as Int? {
                        selectedStatusId = statusId
                    } else if let firstStatus = apiClient.statusLabels.first?.id {
                        selectedStatusId = firstStatus
                    }
                    if let categoryId = asset.category?.id {
                        selectedCategoryId = categoryId
                    } else if let firstCategory = apiClient.assets.compactMap({ $0.category?.id }).first {
                        selectedCategoryId = firstCategory
                    }
                    if let manufacturerId = asset.manufacturer?.id {
                        selectedManufacturerId = manufacturerId
                    } else if let firstManufacturer = apiClient.assets.compactMap({ $0.manufacturer?.id }).first {
                        selectedManufacturerId = firstManufacturer
                    }
                    if let supplierId = asset.supplier?.id {
                        selectedSupplierId = supplierId
                    } else if let firstSupplier = apiClient.assets.compactMap({ $0.supplier?.id }).first {
                        selectedSupplierId = firstSupplier
                    }
                    if let companyId = asset.company?.id {
                        selectedCompanyId = companyId
                    } else if let firstCompany = apiClient.assets.compactMap({ $0.company?.id }).first {
                        selectedCompanyId = firstCompany
                    }
                    if let locationId = asset.location?.id {
                        selectedLocationId = locationId
                    } else if let firstLocation = apiClient.locations.first?.id {
                        selectedLocationId = firstLocation
                    }
                    // Set hasXDate variables for pre-filled dates
                    hasPurchaseDate = asset.purchaseDate?.date != nil
                    hasNextAuditDate = asset.nextAuditDate?.date != nil
                    hasEolDate = asset.assetEolDate?.date != nil
                    hasExpectedCheckin = asset.expectedCheckin?.date != nil
                    showEditSheet = true
                }) {
                    Text("Edit")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if asset.statusLabel.statusMeta?.lowercased() == "deployed" {
                    Button(action: {
                        Task {
                            let success = await apiClient.checkinAsset(assetId: asset.id)
                            checkInOutSuccess = success
                            checkInOutMessage = success ? "Check-in gelukt!" : (apiClient.errorMessage ?? "Check-in mislukt.")
                            showCheckInOutResult = true
                        }
                    }) {
                        Text("Check In")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Button(action: {
                        showCheckoutSheet = true
                    }) {
                        Text("Check Out")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color.white.ignoresSafeArea(edges: .bottom))
        }
        .navigationTitle(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
        .navigationBarTitleDisplayMode(.inline)
        .padding(.top, 8)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/hardware/\(asset.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear {
            selectedTab = 0
            if !hasLoggedAppearance {
                print("AssetDetailView loaded, statusType: \(asset.statusLabel.name)")
                hasLoggedAppearance = true
            }
            Task {
                await apiClient.fetchFieldDefinitions()
                await apiClient.fetchStatusLabels()
            }
            selectedModelId = asset.model?.id ?? 0
            // Init date fields
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let purchaseDateStr = asset.purchaseDate?.date, let d = formatter.date(from: purchaseDateStr) {
                editPurchaseDate = d
                hasPurchaseDate = true
                showPurchaseDate = true
            } else {
                hasPurchaseDate = false
                showPurchaseDate = false
            }
            if let nextAuditDateStr = asset.nextAuditDate?.date, let d = formatter.date(from: nextAuditDateStr) {
                editNextAuditDate = d
                hasNextAuditDate = true
                showNextAuditDate = true
            } else {
                hasNextAuditDate = false
                showNextAuditDate = false
            }
            if let expectedCheckinStr = asset.expectedCheckin?.date, let d = formatter.date(from: expectedCheckinStr) {
                editExpectedCheckin = d
                hasExpectedCheckin = true
                showExpectedCheckin = true
            } else {
                hasExpectedCheckin = false
                showExpectedCheckin = false
            }
            if let eolDateStr = asset.assetEolDate?.date, let d = formatter.date(from: eolDateStr) {
                editEolDate = d
                hasEolDate = true
                showEolDate = true
            } else {
                hasEolDate = false
                showEolDate = false
            }
            // Alleen cijfers tonen in warranty months
            editWarrantyMonths = (asset.warrantyMonths ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
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
            AssetCheckoutSheet(apiClient: apiClient, asset: asset, isPresented: $showCheckoutSheet)
        }
        .alert(isPresented: $showCheckInOutResult) {
            Alert(title: Text(checkInOutSuccess ? "Succes" : "Fout"), message: Text(checkInOutMessage), dismissButton: .default(Text("OK")))
        }
        .overlay(
            Group {
                if showSaveSuccess {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Label("Saved!", systemImage: "checkmark.circle.fill")
                                .font(.title2)
                                .padding()
                                .background(Color.green.opacity(0.9))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                            Spacer()
                        }
                        Spacer()
                    }
                    .transition(.opacity)
                }
            }
        )
    }

    private var detailsView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if showCopyNotification, let text = copyNotification {
                    Text("Copied: \(text)")
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
                        Text("Device Info")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.top, 5)
                        VStack(spacing: 10) {
                            if !asset.decodedAssetTag.isEmpty {
                                copyableDetailRow(label: "Asset Tag", value: asset.decodedAssetTag)
                            }
                            if !asset.decodedSerial.isEmpty {
                                copyableDetailRow(label: "Serial Number", value: asset.decodedSerial)
                            }
                            if !asset.decodedModelName.isEmpty {
                                copyableDetailRow(label: "Model", value: asset.decodedModelName)
                            }
                            if !asset.decodedManufacturerName.isEmpty {
                                copyableDetailRow(label: "Manufacturer", value: asset.decodedManufacturerName)
                            }
                            if let statusMeta = asset.statusLabel.statusMeta, !statusMeta.isEmpty {
                                copyableDetailRow(label: "Status", value: statusMeta)
                            }
                            if !asset.decodedCategoryName.isEmpty {
                                copyableDetailRow(label: "Category", value: asset.decodedCategoryName)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)

                        // Assigned To Section
                        if asset.statusLabel.statusMeta?.lowercased() == "deployed", let user = assignedUser {
                            VStack(spacing: 15) {
                                Text("Assigned To")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)

                                NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient, selectedTab: $userDetailTab)) {
                                    HStack {
                                        Image(systemName: "person.circle")
                                            .foregroundColor(.gray)
                                            .frame(width: 30, height: 30)
                                        VStack(alignment: .leading) {
                                            Text(user.decodedName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(user.decodedEmail)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Text(user.decodedLocationName)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                            }
                            .padding(.top, 5)
                        }
                        // --- DATUMVELDEN ---
                        let hasAnyDate =
                            (asset.purchaseDate?.formatted?.isEmpty == false) ||
                            (asset.nextAuditDate?.formatted?.isEmpty == false) ||
                            (asset.expectedCheckin?.formatted?.isEmpty == false) ||
                            (asset.assetEolDate?.formatted?.isEmpty == false) ||
                            (asset.lastAuditDate?.formatted?.isEmpty == false) ||
                            (asset.lastCheckout?.formatted?.isEmpty == false) ||
                            (asset.lastCheckin?.formatted?.isEmpty == false)
                        if hasAnyDate {
                            Text("Dates")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                if let v = asset.purchaseDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: "Purchase Date", value: v)
                                }
                                if let v = asset.nextAuditDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: "Next Audit Date", value: v)
                                }
                                if let v = asset.expectedCheckin?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: "Expected Checkin", value: v)
                                }
                                if let v = asset.assetEolDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: "EOL Date", value: v)
                                }
                                if let v = asset.lastAuditDate?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: "Last Audit Date", value: v)
                                }
                                if let v = asset.lastCheckout?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: "Last Checkout", value: v)
                                }
                                if let v = asset.lastCheckin?.formatted, !v.isEmpty {
                                    copyableDetailRow(label: "Last Checkin", value: v)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        // Value Info alleen tonen als er minstens één waarde is
                        let hasValueInfo = (asset.purchaseCost?.isEmpty == false) || (asset.bookValue?.isEmpty == false) || (asset.orderNumber?.isEmpty == false)
                        if hasValueInfo {
                            Text("Value Info")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 5)
                            VStack(spacing: 10) {
                                if let purchaseCost = asset.purchaseCost, !purchaseCost.isEmpty {
                                    copyableDetailRow(label: "Purchase Cost", value: purchaseCost)
                                }
                                if let bookValue = asset.bookValue, !bookValue.isEmpty {
                                    copyableDetailRow(label: "Book Value", value: bookValue)
                                }
                                if let orderNumber = asset.orderNumber, !orderNumber.isEmpty {
                                    copyableDetailRow(label: "Order Number", value: orderNumber)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        if let customFields = asset.customFields, !customFields.isEmpty {
                            Text("Custom Fields")
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
                    .padding(.horizontal)
                }
            }
        }
    }
    
    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).bold()
            Spacer()
            Text(value)
            Button(action: {
                UIPasteboard.general.string = value
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
                get: { asset.statusLabel.id },
                set: { _ in /* status change not yet implemented */ }
            )) {
                Text(asset.statusLabel.name).tag(asset.statusLabel.id)
            }
            if !apiClient.assets.isEmpty {
                Picker("Category", selection: Binding(
                    get: { asset.category?.id ?? 0 },
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
                    get: { asset.manufacturer?.id ?? 0 },
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
                    get: { asset.supplier?.id ?? 0 },
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
                    get: { asset.company?.id ?? 0 },
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
                        get: { asset.location?.id ?? 0 },
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
        Section(header: Text("Financial")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Purchase Cost")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Purchase Cost", text: $editPurchaseCost)
                    .keyboardType(.decimalPad)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Order Number")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Order Number", text: $editOrderNumber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Warranty (months)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("", text: $editWarrantyMonths)
                        .keyboardType(.numberPad)
                    Text("months")
                        .foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Purchase Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if hasPurchaseDate {
                    DatePicker("", selection: $editPurchaseDate, displayedComponents: .date)
                        .labelsHidden()
                } else {
                    Toggle("Set Purchase Date", isOn: $showPurchaseDate)
                        .font(.caption)
                    if showPurchaseDate {
                        DatePicker("", selection: $editPurchaseDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Expected Checkin Date")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if hasExpectedCheckin {
                    DatePicker("", selection: $editExpectedCheckin, displayedComponents: .date)
                        .labelsHidden()
                } else {
                    Toggle("Set Expected Checkin Date", isOn: $showExpectedCheckin)
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
                    Toggle("Set EOL Date", isOn: $showEolDate)
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
                    Toggle("Set Next Audit Date", isOn: $showNextAuditDate)
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
