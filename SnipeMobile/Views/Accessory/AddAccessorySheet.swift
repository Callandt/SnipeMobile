import SwiftUI

struct AddAccessorySheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedCategoryId: Int = 0
    @State private var quantityText = "1"
    @State private var minAmtText = ""
    @State private var modelNumber = ""
    @State private var selectedLocationId: Int?
    @State private var selectedCompanyId: Int?
    @State private var orderNumber = ""
    @State private var purchaseCost = ""
    @State private var purchaseDate = Date()
    @State private var hasPurchaseDate = false
    @State private var selectedManufacturerId: Int?
    @State private var selectedSupplierId: Int?
    @State private var isSaving = false
    @State private var resultMessage = ""
    @State private var showResult = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedCategoryId != 0
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                purchaseSection
            }
            .navigationTitle(L10n.string("new_accessory"))
            .toolbar { toolbarContent }
            .onAppear(perform: setupOnAppear)
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok")) {
                    if resultMessage.contains("created") || resultMessage.lowercased().contains("success") {
                        isPresented = false
                    }
                }
            } message: {
                Text(resultMessage)
            }
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
                Button(L10n.string("create")) { saveAccessory() }
                    .disabled(!canSave)
            }
        }
    }

    private func setupOnAppear() {
        if apiClient.categories.isEmpty {
            Task { await apiClient.fetchCategories() }
        }
        if apiClient.locations.isEmpty {
            Task { await apiClient.fetchLocations() }
        }
        Task { await apiClient.fetchCompanies() }
        Task { await apiClient.fetchManufacturers() }
        Task { await apiClient.fetchSuppliers() }
    }

    private var generalSection: some View {
        Section(header: Text(L10n.string("general"))) {
            TextField(L10n.fieldLabel("name", required: true), text: $name)
            AdaptivePickerRow(
                title: L10n.fieldLabel("category", required: true),
                items: apiClient.categories.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: $selectedCategoryId,
                emptyOption: (0, L10n.string("choose_category"))
            )
            HStack {
                Text(L10n.fieldLabel("quantity", required: true))
                Spacer()
                TextField("", text: $quantityText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text(L10n.string("minimum_amount"))
                Spacer()
                TextField("", text: $minAmtText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            TextField(L10n.string("model_number"), text: $modelNumber)
            if !apiClient.locations.isEmpty {
                let sortedLocations = apiClient.locations.sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
                AdaptivePickerRow(
                    title: L10n.string("location"),
                    items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                    selection: Binding(
                        get: { selectedLocationId ?? 0 },
                        set: { selectedLocationId = $0 == 0 ? nil : $0 }
                    ),
                    emptyOption: (0, L10n.string("choose_location"))
                )
            }
            if !apiClient.companies.isEmpty {
                let sortedCompanies = apiClient.companies.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                // Searchable avoids Form Int-tag collisions with manufacturer/supplier pickers.
                SearchablePickerRow(
                    title: L10n.string("company"),
                    items: sortedCompanies.map { (value: $0.id, label: $0.name) },
                    selection: Binding(
                        get: { selectedCompanyId ?? 0 },
                        set: { selectedCompanyId = $0 == 0 ? nil : $0 }
                    ),
                    emptyOption: (0, L10n.string("choose_company"))
                )
            }
        }
    }

    private var purchaseSection: some View {
        Section(header: Text(L10n.string("purchase_only"))) {
            TextField(L10n.string("order_number"), text: $orderNumber)
            TextField(L10n.string("purchase_price"), text: $purchaseCost)
                .keyboardType(.decimalPad)
            Toggle(L10n.string("set_purchase_date"), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker(L10n.string("purchase_date"), selection: $purchaseDate, displayedComponents: .date)
            }
            SearchablePickerRow(
                title: L10n.string("manufacturer"),
                items: apiClient.manufacturers.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: Binding(
                    get: { selectedManufacturerId ?? 0 },
                    set: { selectedManufacturerId = $0 == 0 ? nil : $0 }
                ),
                emptyOption: (0, L10n.string("choose_manufacturer"))
            )
            SearchablePickerRow(
                title: L10n.string("supplier"),
                items: apiClient.suppliers.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: Binding(
                    get: { selectedSupplierId ?? 0 },
                    set: { selectedSupplierId = $0 == 0 ? nil : $0 }
                ),
                emptyOption: (0, L10n.string("choose_supplier"))
            )
        }
    }

    private func parsedQuantity() -> Int {
        max(1, Int(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1)
    }

    private func parsedMinAmt() -> Int {
        max(0, Int(minAmtText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
    }

    private func saveAccessory() {
        guard selectedCategoryId != 0 else { return }
        isSaving = true
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f
        }()
        let purchaseDateStr = hasPurchaseDate ? formatter.string(from: purchaseDate) : nil
        let quantity = parsedQuantity()
        let minAmt = parsedMinAmt()
        Task {
            let success = await apiClient.createAccessory(
                name: name.trimmingCharacters(in: .whitespaces),
                categoryId: selectedCategoryId,
                quantity: quantity,
                minAmt: minAmt,
                orderNumber: orderNumber.isEmpty ? nil : orderNumber.trimmingCharacters(in: .whitespaces),
                purchaseCost: purchaseCost.isEmpty ? nil : purchaseCost.trimmingCharacters(in: .whitespaces),
                purchaseDate: purchaseDateStr,
                modelNumber: modelNumber.isEmpty ? nil : modelNumber.trimmingCharacters(in: .whitespaces),
                companyId: selectedCompanyId,
                locationId: selectedLocationId,
                manufacturerId: selectedManufacturerId,
                supplierId: selectedSupplierId,
                customFields: nil
            )
            await MainActor.run {
                isSaving = false
                resultMessage = apiClient.lastApiMessage ?? (success ? "Accessory created!" : "Create failed.")
                showResult = true
            }
        }
    }
}
