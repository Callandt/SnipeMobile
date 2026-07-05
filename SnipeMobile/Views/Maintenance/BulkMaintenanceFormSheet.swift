import SwiftUI

struct BulkMaintenanceFormSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    var preselectedAssetIds: Set<Int> = []
    var onSave: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAssetIds: Set<Int> = []
    @State private var showAssetPicker = false
    @State private var showAssetScanner = false

    @State private var title: String = ""
    @State private var selectedType: String = "Maintenance"
    @State private var selectedTypeId: Int = 0
    @State private var selectedSupplierId: Int = 0
    @State private var cost: String = ""
    @State private var url: String = ""
    @State private var notes: String = ""
    @State private var isWarranty: Bool = false
    @State private var startDate: Date = Date()
    @State private var hasCompletionDate: Bool = false
    @State private var completionDate: Date = Date()
    @State private var userSearchText: String = ""
    @State private var selectedUser: User? = nil
    @State private var responsibleWasCleared = false
    @State private var selectedImage: UIImage? = nil

    @State private var isSaving: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    // empty list = older server without the maintenance-types endpoint
    private var usesTypeIds: Bool { !apiClient.maintenanceTypes.isEmpty }

    private var legacyTypeOptions: [String] {
        MaintenanceFormPickerSupport.legacyTypeOptions(selectedType: selectedType, recordType: nil)
    }

    private var typeIdPickerReady: Bool {
        MaintenanceFormPickerSupport.hasValidPickerTag(
            id: selectedTypeId,
            in: apiClient.maintenanceTypes.map(\.id)
        )
    }

    private var filteredUsers: [User] {
        apiClient.filteredCheckoutUsers(searchText: userSearchText)
    }

    private var typeIsValid: Bool {
        usesTypeIds ? selectedTypeId != 0 : !selectedType.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && typeIsValid
            && !selectedAssetIds.isEmpty
            && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                AssetBulkSelectionSection(
                    apiClient: apiClient,
                    selectedAssetIds: $selectedAssetIds,
                    showPicker: $showAssetPicker,
                    showScanner: $showAssetScanner
                )
                Section(header: Text(L10n.string("general"))) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("name"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(L10n.string("name"), text: $title)
                    }
                    if usesTypeIds {
                        if typeIdPickerReady {
                            Picker(L10n.string("maintenance_type"), selection: $selectedTypeId) {
                                ForEach(apiClient.maintenanceTypes) { type in
                                    Text(type.decodedName).tag(type.id)
                                }
                            }
                        } else {
                            Text(L10n.string("loading"))
                                .foregroundStyle(.secondary)
                        }
                    } else if !legacyTypeOptions.isEmpty {
                        Picker(L10n.string("maintenance_type"), selection: $selectedType) {
                            ForEach(legacyTypeOptions, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                    }
                }
                Section(header: Text(L10n.string("responsible_party"))) {
                    MaintenanceOptionalResponsibleUserSection(
                        searchText: $userSearchText,
                        selectedUser: $selectedUser,
                        wasCleared: $responsibleWasCleared,
                        users: filteredUsers,
                        isLoading: apiClient.users.isEmpty
                    )
                }
                Section(header: Text(L10n.string("dates"))) {
                    DatePicker(L10n.string("start_date"), selection: $startDate, displayedComponents: .date)
                    Toggle(L10n.string("set_completion_date"), isOn: $hasCompletionDate)
                    if hasCompletionDate {
                        DatePicker(L10n.string("completion_date"), selection: $completionDate, displayedComponents: .date)
                    }
                }
                Section(header: Text(L10n.string("financial"))) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.string("cost"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(L10n.string("cost"), text: $cost)
                            .keyboardType(.decimalPad)
                    }
                    if !apiClient.suppliers.isEmpty {
                        Picker(L10n.string("supplier_optional"), selection: $selectedSupplierId) {
                            Text(L10n.string("none")).tag(0)
                            ForEach(apiClient.suppliers, id: \.id) { supplier in
                                Text(HTMLDecoder.decode(supplier.name)).tag(supplier.id)
                            }
                        }
                    }
                }
                Section {
                    Toggle(L10n.string("is_warranty"), isOn: $isWarranty)
                }
                Section(header: Text(L10n.string("url"))) {
                    TextField(L10n.string("url"), text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                AssetPhotoSection(selectedImage: $selectedImage)
                Section(header: Text(L10n.string("notes"))) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .assetBulkSelectionDestinations(
                apiClient: apiClient,
                selectedAssetIds: $selectedAssetIds,
                showPicker: $showAssetPicker,
                showScanner: $showAssetScanner
            )
            .navigationTitle(L10n.string("add_maintenance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("save")) {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            if selectedAssetIds.isEmpty { selectedAssetIds = preselectedAssetIds }
            syncPickerSelections()
            if apiClient.suppliers.isEmpty {
                Task { await apiClient.fetchSuppliers() }
            }
            if apiClient.users.isEmpty {
                Task {
                    await apiClient.fetchUsers()
                    syncPickerSelections()
                }
            }
            if apiClient.maintenanceTypes.isEmpty {
                Task {
                    await apiClient.fetchMaintenanceTypes()
                    syncPickerSelections()
                }
            }
        }
        .onChange(of: apiClient.users.count) { _, _ in syncPickerSelections() }
        .onChange(of: apiClient.maintenanceTypes.count) { _, _ in syncPickerSelections() }
        .overlay {
            if isSaving {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert(L10n.string("error"), isPresented: $showErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func syncPickerSelections() {
        if usesTypeIds {
            MaintenanceFormPickerSupport.applyTypeIdSelection(
                selectedTypeId: &selectedTypeId,
                types: apiClient.maintenanceTypes,
                record: nil
            )
        } else {
            MaintenanceFormPickerSupport.normalizeLegacyTypeSelection(
                selectedType: &selectedType,
                options: legacyTypeOptions
            )
        }
        MaintenanceFormPickerSupport.reconcileResponsibleUser(
            selectedUser: &selectedUser,
            users: apiClient.users,
            preferredId: nil,
            wasCleared: responsibleWasCleared
        )
    }

    private func save() async {
        guard !selectedAssetIds.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let startStr = dateFormatter.string(from: startDate)
        let endStr = hasCompletionDate ? dateFormatter.string(from: completionDate) : nil
        let supplierIdOpt: Int? = selectedSupplierId == 0 ? nil : selectedSupplierId
        let costOpt: String? = NumberFormatHelpers.normalizeDecimalForAPI(cost)
        let urlOpt: String? = url.trimmingCharacters(in: .whitespaces).isEmpty ? nil : url.trimmingCharacters(in: .whitespaces)
        let notesOpt: String? = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        let responsibleIdOpt: Int? = selectedUser?.id

        // send both so the legacy string column stays populated too
        let typeIdOpt: Int? = usesTypeIds ? (selectedTypeId == 0 ? nil : selectedTypeId) : nil
        let typeStringOpt: String? = usesTypeIds
            ? apiClient.maintenanceTypes.first(where: { $0.id == selectedTypeId })?.name
            : selectedType

        var failedCount = 0
        var lastError: String? = nil
        for assetId in selectedAssetIds {
            let create = MaintenanceCreateRequest(
                asset_id: assetId,
                name: title,
                asset_maintenance_type: typeStringOpt,
                maintenance_type_id: typeIdOpt,
                supplier_id: supplierIdOpt,
                cost: costOpt,
                notes: notesOpt,
                url: urlOpt,
                responsible_party_id: responsibleIdOpt,
                start_date: startStr,
                completion_date: endStr,
                is_warranty: isWarranty
            )
            let ok = await apiClient.createMaintenance(create, image: selectedImage)
            if !ok {
                failedCount += 1
                lastError = apiClient.lastApiMessage ?? apiClient.errorMessage
            }
        }

        if failedCount == 0 {
            onSave()
            dismiss()
        } else {
            let base = L10n.string("bulk_maintenance_failed", failedCount)
            errorMessage = lastError.map { "\(base)\n\($0)" } ?? base
            showErrorAlert = true
        }
    }
}

