import SwiftUI

struct MaintenanceFormSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let assetId: Int
    let record: AssetMaintenance?
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var selectedType: String = "Maintenance"
    @State private var selectedTypeId: Int = 0
    @State private var selectedSupplierId: Int = 0
    @State private var cost: String = ""
    @State private var notes: String = ""
    @State private var isWarranty: Bool = false
    @State private var startDate: Date = Date()
    @State private var hasCompletionDate: Bool = false
    @State private var completionDate: Date = Date()
    @State private var isSaving: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    private let maintenanceTypes = [
        "Maintenance", "Repair", "PAT Test/Electrical",
        "Upgrade", "Hardware Support", "Software Support"
    ]

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private var isEditing: Bool { record != nil }

    // empty list = older server without the maintenance-types endpoint
    private var usesTypeIds: Bool { !apiClient.maintenanceTypes.isEmpty }

    private var typeIsValid: Bool {
        usesTypeIds ? selectedTypeId != 0 : !selectedType.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && typeIsValid && !isSaving
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
                        Picker(L10n.string("maintenance_type"), selection: $selectedTypeId) {
                            ForEach(apiClient.maintenanceTypes) { type in
                                Text(type.decodedName).tag(type.id)
                            }
                        }
                    } else {
                        Picker(L10n.string("maintenance_type"), selection: $selectedType) {
                            ForEach(maintenanceTypes, id: \.self) { type in
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
            if apiClient.suppliers.isEmpty {
                Task { await apiClient.fetchSuppliers() }
            }
            if apiClient.maintenanceTypes.isEmpty {
                Task {
                    await apiClient.fetchMaintenanceTypes()
                    applyTypeSelection()
                }
            } else {
                applyTypeSelection()
            }
        }
        .alert(L10n.string("error"), isPresented: $showErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // match the edited record by name, else pick the first type
    private func applyTypeSelection() {
        guard usesTypeIds else { return }
        if let r = record {
            let targetName = (r.maintenanceType ?? r.assetMaintenanceType)?.lowercased()
            if let target = targetName,
               let match = apiClient.maintenanceTypes.first(where: { $0.name.lowercased() == target }) {
                selectedTypeId = match.id
                return
            }
        }
        if selectedTypeId == 0, let first = apiClient.maintenanceTypes.first {
            selectedTypeId = first.id
        }
    }

    private func prefill() {
        guard let r = record else { return }
        title = r.decodedTitle
        selectedType = r.assetMaintenanceType ?? r.maintenanceType ?? "Maintenance"
        selectedSupplierId = r.supplier?.id ?? 0
        cost = r.cost ?? ""
        notes = r.decodedNotes
        isWarranty = r.isWarranty
        if let startStr = r.startDate?.date, let date = dateFormatter.date(from: startStr) {
            startDate = date
        }
        if let endStr = r.completionDate?.date, let date = dateFormatter.date(from: endStr) {
            hasCompletionDate = true
            completionDate = date
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let startStr = dateFormatter.string(from: startDate)
        let endStr = hasCompletionDate ? dateFormatter.string(from: completionDate) : nil
        let supplierIdOpt: Int? = selectedSupplierId == 0 ? nil : selectedSupplierId
        let costOpt: String? = NumberFormatHelpers.normalizeDecimalForAPI(cost)
        let notesOpt: String? = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes

        // send both so the legacy string column stays populated too
        let typeIdOpt: Int? = usesTypeIds ? (selectedTypeId == 0 ? nil : selectedTypeId) : nil
        let typeStringOpt: String? = usesTypeIds
            ? apiClient.maintenanceTypes.first(where: { $0.id == selectedTypeId })?.name
            : selectedType

        let ok: Bool
        if let existing = record {
            let update = MaintenanceUpdateRequest(
                name: title,
                asset_maintenance_type: typeStringOpt,
                maintenance_type_id: typeIdOpt,
                supplier_id: supplierIdOpt,
                cost: costOpt,
                notes: notesOpt,
                start_date: startStr,
                completion_date: endStr,
                is_warranty: isWarranty
            )
            ok = await apiClient.updateMaintenance(id: existing.id, update: update)
        } else {
            let create = MaintenanceCreateRequest(
                asset_id: assetId,
                name: title,
                asset_maintenance_type: typeStringOpt,
                maintenance_type_id: typeIdOpt,
                supplier_id: supplierIdOpt,
                cost: costOpt,
                notes: notesOpt,
                start_date: startStr,
                completion_date: endStr,
                is_warranty: isWarranty
            )
            ok = await apiClient.createMaintenance(create)
        }

        if ok {
            onSave()
            dismiss()
        } else {
            errorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showErrorAlert = true
        }
    }
}
