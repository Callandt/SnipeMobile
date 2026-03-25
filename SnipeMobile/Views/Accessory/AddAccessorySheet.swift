import SwiftUI

struct AddAccessorySheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var selectedCategoryId: Int = 0
    @State private var quantity: Int = 1
    @State private var minAmt: Int = 0
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
        if apiClient.companies.isEmpty {
            Task { await apiClient.fetchCompanies() }
        }
        if apiClient.manufacturers.isEmpty {
            Task { await apiClient.fetchManufacturers() }
        }
        if apiClient.suppliers.isEmpty {
            Task { await apiClient.fetchSuppliers() }
        }
    }

    private var generalSection: some View {
        Section(header: Text(L10n.string("general"))) {
            TextField(L10n.string("name"), text: $name)
            AdaptivePickerRow(
                title: L10n.string("category"),
                items: apiClient.categories.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: $selectedCategoryId,
                emptyOption: (0, L10n.string("choose_category"))
            )
            HStack {
                Text(L10n.string("quantity"))
                Spacer()
                TextField("", value: $quantity, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            HStack {
                Text(L10n.string("minimum_amount"))
                Spacer()
                TextField("", value: $minAmt, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
            TextField(L10n.string("model_number_optional"), text: $modelNumber)
            if !apiClient.locations.isEmpty {
                let sortedLocations = apiClient.locations.sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
                AdaptivePickerRow(
                    title: L10n.string("location_optional"),
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
                AdaptivePickerRow(
                    title: L10n.string("company_optional"),
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
            TextField(L10n.string("order_number_optional"), text: $orderNumber)
            TextField(L10n.string("purchase_price_optional"), text: $purchaseCost)
                .keyboardType(.decimalPad)
            Toggle(L10n.string("purchase_date"), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
            }
            if !apiClient.manufacturers.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("manufacturer_optional"),
                    items: apiClient.manufacturers.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                    selection: Binding(
                        get: { selectedManufacturerId ?? 0 },
                        set: { selectedManufacturerId = $0 == 0 ? nil : $0 }
                    ),
                    emptyOption: (0, L10n.string("choose_manufacturer"))
                )
            }
            if !apiClient.suppliers.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("supplier_optional"),
                    items: apiClient.suppliers.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                    selection: Binding(
                        get: { selectedSupplierId ?? 0 },
                        set: { selectedSupplierId = $0 == 0 ? nil : $0 }
                    ),
                    emptyOption: (0, L10n.string("choose_supplier"))
                )
            }
        }
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
        Task {
            let success = await apiClient.createAccessory(
                name: name.trimmingCharacters(in: .whitespaces),
                categoryId: selectedCategoryId,
                quantity: quantity,
                minAmt: minAmt > 0 ? minAmt : nil,
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
