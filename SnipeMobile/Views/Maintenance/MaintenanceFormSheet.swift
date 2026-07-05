import SwiftUI

struct MaintenanceFormSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let assetId: Int
    let record: AssetMaintenance?
    var onSave: (Int) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

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
    @State private var selectedResponsibleId: Int = 0
    @State private var selectedImage: UIImage? = nil
    @State private var removeExistingImage: Bool = false
    @State private var isSaving: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private var isEditing: Bool { record != nil }

    // empty list = older server without the maintenance-types endpoint
    private var usesTypeIds: Bool { !apiClient.maintenanceTypes.isEmpty }

    private var legacyTypeOptions: [String] {
        MaintenanceFormPickerSupport.legacyTypeOptions(
            selectedType: selectedType,
            recordType: record?.displayType
        )
    }

    private var typeIdPickerReady: Bool {
        MaintenanceFormPickerSupport.hasValidPickerTag(
            id: selectedTypeId,
            in: apiClient.maintenanceTypes.map(\.id)
        )
    }

    private var responsiblePickerReady: Bool {
        MaintenanceFormPickerSupport.hasValidPickerTag(
            id: selectedResponsibleId,
            in: apiClient.users.map(\.id)
        )
    }

    private var typeIsValid: Bool {
        usesTypeIds ? selectedTypeId != 0 : !selectedType.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && typeIsValid && !isSaving
    }

    private var existingImageURL: URL? {
        guard let raw = record?.image?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        if raw.hasPrefix("/") {
            return URL(string: "\(apiClient.baseURL)\(raw)")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
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
                Section(header: Text(L10n.string("dates"))) {
                    DatePicker(L10n.string("start_date"), selection: $startDate, displayedComponents: .date)
                    Toggle(L10n.string("set_completion_date"), isOn: $hasCompletionDate)
                    if hasCompletionDate {
                        DatePicker(L10n.string("completion_date"), selection: $completionDate, displayedComponents: .date)
                    }
                }
                Section(header: Text(L10n.string("responsible_party"))) {
                    if responsiblePickerReady {
                        Picker(L10n.string("responsible_party"), selection: $selectedResponsibleId) {
                            ForEach(apiClient.users, id: \.id) { user in
                                Text(user.decodedName).tag(user.id)
                            }
                        }
                    } else {
                        Text(L10n.string("loading"))
                            .foregroundStyle(.secondary)
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
                AssetPhotoSection(
                    selectedImage: $selectedImage,
                    existingImageURL: existingImageURL,
                    removeExistingImage: $removeExistingImage
                )
                Section(header: Text(L10n.string("notes"))) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isEditing ? L10n.string("edit_maintenance") : L10n.string("add_maintenance"))
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
            prefill()
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
                record: record
            )
        } else {
            MaintenanceFormPickerSupport.normalizeLegacyTypeSelection(
                selectedType: &selectedType,
                options: legacyTypeOptions
            )
        }
        MaintenanceFormPickerSupport.reconcileResponsibleSelection(
            selectedId: &selectedResponsibleId,
            users: apiClient.users,
            preferredId: record?.responsibleParty?.id,
            defaultUser: apiClient.defaultCheckoutUser
        )
    }

    private func prefill() {
        if let r = record {
            title = r.decodedTitle
            selectedType = r.assetMaintenanceType ?? r.maintenanceType ?? "Maintenance"
            selectedSupplierId = r.supplier?.id ?? 0
            cost = r.cost ?? ""
            url = r.url ?? ""
            notes = r.decodedNotes
            isWarranty = r.isWarranty
            if let partyId = r.responsibleParty?.id {
                selectedResponsibleId = partyId
            }
            if let startStr = r.startDate?.date, let date = dateFormatter.date(from: startStr) {
                startDate = date
            }
            if let endStr = r.completionDate?.date, let date = dateFormatter.date(from: endStr) {
                hasCompletionDate = true
                completionDate = date
            }
        } else if let defaultId = apiClient.defaultCheckoutUser?.id {
            selectedResponsibleId = defaultId
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let startStr = dateFormatter.string(from: startDate)
        let endStr = hasCompletionDate ? dateFormatter.string(from: completionDate) : nil
        let supplierIdOpt: Int? = selectedSupplierId == 0 ? nil : selectedSupplierId
        let costOpt: String? = NumberFormatHelpers.normalizeDecimalForAPI(cost)
        let urlOpt: String? = url.trimmingCharacters(in: .whitespaces).isEmpty ? nil : url.trimmingCharacters(in: .whitespaces)
        let notesOpt: String? = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        let responsibleIdOpt: Int? = selectedResponsibleId == 0 ? nil : selectedResponsibleId

        // send both so the legacy string column stays populated too
        let typeIdOpt: Int? = usesTypeIds ? (selectedTypeId == 0 ? nil : selectedTypeId) : nil
        let typeStringOpt: String? = usesTypeIds
            ? apiClient.maintenanceTypes.first(where: { $0.id == selectedTypeId })?.name
            : selectedType

        let update = MaintenanceUpdateRequest(
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
            is_warranty: isWarranty,
            image_delete: (selectedImage == nil && removeExistingImage) ? 1 : nil
        )

        let savedId: Int?
        if let existing = record {
            savedId = await apiClient.updateMaintenance(
                id: existing.id,
                assetId: assetId,
                update: update,
                image: selectedImage,
                wasCompleted: existing.isCompleted
            )
        } else {
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
            let created = await apiClient.createMaintenance(create, image: selectedImage)
            savedId = created ? 0 : nil
        }

        if savedId != nil {
            onSave(savedId ?? 0)
            dismiss()
        } else {
            errorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showErrorAlert = true
        }
    }
}
