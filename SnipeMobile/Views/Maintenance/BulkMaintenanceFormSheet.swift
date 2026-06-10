import SwiftUI

struct BulkMaintenanceFormSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    var preselectedAssetIds: Set<Int> = []
    var onSave: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAssetIds: Set<Int> = []
    @State private var showAssetPicker = false

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

    // empty list = older server without the maintenance-types endpoint
    private var usesTypeIds: Bool { !apiClient.maintenanceTypes.isEmpty }

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
                Section(header: Text(L10n.string("assets"))) {
                    Button {
                        showAssetPicker = true
                    } label: {
                        HStack {
                            Label(L10n.string("select_assets"), systemImage: "laptopcomputer")
                            Spacer()
                            Text(L10n.string("assets_selected_count", selectedAssetIds.count))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
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
            .navigationDestination(isPresented: $showAssetPicker) {
                AssetMultiSelectView(assets: apiClient.assets, selectedAssetIds: $selectedAssetIds)
            }
        }
        .onAppear {
            if selectedAssetIds.isEmpty { selectedAssetIds = preselectedAssetIds }
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

    private func applyTypeSelection() {
        guard usesTypeIds else { return }
        if selectedTypeId == 0, let first = apiClient.maintenanceTypes.first {
            selectedTypeId = first.id
        }
    }

    private func save() async {
        guard !selectedAssetIds.isEmpty else { return }
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
                start_date: startStr,
                completion_date: endStr,
                is_warranty: isWarranty
            )
            let ok = await apiClient.createMaintenance(create)
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

// asset multi-select used by the bulk form
private struct AssetMultiSelectView: View {
    let assets: [Asset]
    @Binding var selectedAssetIds: Set<Int>

    @State private var searchText: String = ""

    private var filteredAssets: [Asset] {
        if searchText.isEmpty { return assets }
        let q = searchText.lowercased()
        return assets.filter {
            $0.decodedName.lowercased().contains(q) ||
            $0.decodedModelName.lowercased().contains(q) ||
            $0.decodedAssetTag.lowercased().contains(q) ||
            $0.decodedAssignedToName.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(L10n.string("assets_selected_count", selectedAssetIds.count))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !selectedAssetIds.isEmpty {
                        Button(L10n.string("clear_selection")) {
                            selectedAssetIds.removeAll()
                        }
                        .font(.subheadline)
                    }
                }
            }
            Section {
                ForEach(filteredAssets) { asset in
                    Button {
                        toggle(asset.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedAssetIds.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedAssetIds.contains(asset.id) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                let subtitle = [asset.decodedAssetTag, asset.decodedName]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " · ")
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .searchable(text: $searchText, prompt: L10n.string("search_assets"))
        .navigationTitle(L10n.string("select_assets"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: Int) {
        if selectedAssetIds.contains(id) {
            selectedAssetIds.remove(id)
        } else {
            selectedAssetIds.insert(id)
        }
    }
}
