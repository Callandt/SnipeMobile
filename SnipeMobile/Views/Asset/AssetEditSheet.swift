import SwiftUI

struct IdNamePair: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct AssetEditSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    @Binding var isPresented: Bool
    @Binding var editName: String
    @Binding var editAssetTag: String
    @Binding var editSerial: String
    @Binding var editNotes: String
    @Binding var editOrderNumber: String
    @Binding var editPurchaseCost: String
    @Binding var editBookValue: String
    @Binding var editCustomFields: [String: String]
    @Binding var isSaving: Bool
    @Binding var showSaveSuccess: Bool
    @Binding var selectedModelId: Int
    @Binding var selectedStatusId: Int
    @Binding var selectedCategoryId: Int
    @Binding var selectedManufacturerId: Int
    @Binding var selectedSupplierId: Int
    @Binding var selectedCompanyId: Int
    @Binding var selectedLocationId: Int
    @Binding var editPurchaseDate: Date
    @Binding var editNextAuditDate: Date
    @Binding var editWarrantyExpires: Date
    @Binding var hasPurchaseDate: Bool
    @Binding var hasNextAuditDate: Bool
    @Binding var hasWarrantyExpires: Bool
    @Binding var editExpectedCheckin: Date
    @Binding var editEolDate: Date
    @Binding var editWarrantyMonths: String
    @Binding var hasExpectedCheckin: Bool
    @Binding var hasEolDate: Bool
    @Binding var showPurchaseDate: Bool
    @Binding var showNextAuditDate: Bool
    @Binding var showWarrantyExpires: Bool
    @Binding var showExpectedCheckin: Bool
    @Binding var showEolDate: Bool

    var body: some View {
        NavigationView {
            Form {
                generalSection
                financialSection
                notesSection
                customFieldsSection
            }
            .navigationTitle("Edit Asset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            isSaving = true
                            Task {
                                // Hier komt je save-logica (API-call, etc.)
                                // Simuleer een korte delay voor demo:
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                isSaving = false
                                isPresented = false
                                showSaveSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showSaveSuccess = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

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
                let modelPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { asset in
                    guard let model = asset.model else { return nil }
                    return IdNamePair(id: model.id, name: HTMLDecoder.decode(model.name))
                })).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                Picker("Model", selection: $selectedModelId) {
                    ForEach(modelPairs) { pair in
                        Text(pair.name).tag(pair.id)
                    }
                }
                .onChange(of: selectedModelId) {
                    updateCustomFieldsForModel(selectedModelId)
                }
            }
            if !apiClient.assets.isEmpty {
                Picker("Supplier", selection: $selectedSupplierId) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.supplier?.id }).sorted()), id: \.self) { id in
                        if let sup = apiClient.assets.first(where: { $0.supplier?.id == id })?.supplier {
                            Text(sup.name).tag(sup.id)
                        }
                    }
                }
            }
            if !apiClient.assets.isEmpty {
                Picker("Company", selection: $selectedCompanyId) {
                    ForEach(Array(Set(apiClient.assets.compactMap { $0.company?.id }).sorted()), id: \.self) { id in
                        if let comp = apiClient.assets.first(where: { $0.company?.id == id })?.company {
                            Text(comp.name).tag(comp.id)
                        }
                    }
                }
            }
            Picker("Status", selection: $selectedStatusId) {
                ForEach(apiClient.statusLabels, id: \.id) { label in
                    Text(label.name).tag(label.id)
                }
            }
            if !apiClient.assets.isEmpty {
                let categoryPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { asset in
                    guard let cat = asset.category else { return nil }
                    return IdNamePair(id: cat.id, name: cat.name)
                })).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !categoryPairs.isEmpty {
                    Picker("Category", selection: $selectedCategoryId) {
                        ForEach(categoryPairs) { pair in
                            Text(pair.name).tag(pair.id)
                        }
                    }
                }
            }
            if !apiClient.assets.isEmpty {
                let manufacturerPairs: [IdNamePair] = Array(Set(apiClient.assets.compactMap { asset in
                    guard let man = asset.manufacturer else { return nil }
                    return IdNamePair(id: man.id, name: man.name)
                })).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if !manufacturerPairs.isEmpty {
                    Picker("Manufacturer", selection: $selectedManufacturerId) {
                        ForEach(manufacturerPairs) { pair in
                            Text(pair.name).tag(pair.id)
                        }
                    }
                }
            }
            if !apiClient.locations.isEmpty {
                let locationPairs: [IdNamePair] = apiClient.locations.map { IdNamePair(id: $0.id, name: $0.name) }
                if !locationPairs.isEmpty {
                    Picker("Location", selection: $selectedLocationId) {
                        ForEach(locationPairs) { pair in
                            Text(pair.name).tag(pair.id)
                        }
                    }
                }
            }
        }
    }

    private var financialSection: some View {
        Section(header: Text("Financial")) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Purchase Cost")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Purchase Cost", text: $editPurchaseCost)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Order Number")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Order Number", text: $editOrderNumber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Warranty Months")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Warranty Months", text: $editWarrantyMonths)
            }
        }
    }

    private var notesSection: some View {
        Section(header: Text("Notes")) {
            TextEditor(text: $editNotes)
                .frame(minHeight: 120)
        }
    }

    private var customFieldsSection: some View {
        Section(header: Text("Custom Fields")) {
            let currentFieldset = apiClient.fieldsets?.first(where: { fs in
                (fs.models?.rows.contains { $0.id == selectedModelId }) ?? false
            })
            let customFieldDefs = currentFieldset?.fields.rows ?? []
            if customFieldDefs.isEmpty {
                Text("No custom fields")
                    .foregroundColor(.secondary)
            } else {
                ForEach(customFieldDefs, id: \.id) { fieldDef in
                    Group {
                        if fieldDef.type == "listbox", let options = fieldDef.field_values_array, !options.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fieldDef.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Picker(fieldDef.name, selection: Binding(
                                    get: { editCustomFields[fieldDef.name] ?? options.first ?? "" },
                                    set: { editCustomFields[fieldDef.name] = $0 }
                                )) {
                                    ForEach(options, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            }
                        } else if fieldDef.type == "text" {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(fieldDef.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(fieldDef.name, text: Binding(
                                    get: { editCustomFields[fieldDef.name] ?? "" },
                                    set: { editCustomFields[fieldDef.name] = $0 }
                                ))
                            }
                        } else {
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    private func updateCustomFieldsForModel(_ modelId: Int) {
        guard let fieldsets = apiClient.fieldsets else { return }
        guard let fieldset = fieldsets.first(where: { fs in
            (fs.models?.rows.contains { $0.id == modelId }) ?? false
        }) else { return }
        var newCustomFields: [String: String] = [:]
        for field in fieldset.fields.rows {
            newCustomFields[field.name] = editCustomFields[field.name] ?? ""
        }
        editCustomFields = newCustomFields
    }
} 