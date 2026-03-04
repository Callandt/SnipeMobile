import SwiftUI

struct AccessoryEditSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let accessory: Accessory
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var selectedCategoryId: Int = 0
    @State private var quantity: Int = 1
    @State private var minAmt: Int = 0
    @State private var modelNumber: String = ""
    @State private var selectedLocationId: Int?
    @State private var selectedCompanyId: Int?
    @State private var orderNumber: String = ""
    @State private var purchaseCost: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var hasPurchaseDate: Bool = false
    @State private var selectedManufacturerId: Int?
    @State private var selectedSupplierId: Int?
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                purchaseSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("save")) { saveAccessory() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategoryId == 0)
                    }
                }
            }
            .onAppear {
                name = accessory.decodedName
                selectedCategoryId = accessory.category?.id ?? 0
                quantity = accessory.qty ?? 1
                minAmt = accessory.minAmt ?? 0
                modelNumber = accessory.modelNumber ?? ""
                selectedLocationId = accessory.location?.id
                selectedCompanyId = accessory.company?.id
                selectedManufacturerId = accessory.manufacturer?.id
                selectedSupplierId = accessory.supplier?.id
                orderNumber = accessory.orderNumber ?? ""
                purchaseCost = accessory.purchaseCost ?? ""
                if let pd = accessory.purchaseDate, !pd.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    if let d = formatter.date(from: pd) {
                        purchaseDate = d
                        hasPurchaseDate = true
                    }
                }
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
                let validCategoryIds = Set(apiClient.categories.map(\.id))
                if selectedCategoryId != 0, !validCategoryIds.contains(selectedCategoryId) {
                    selectedCategoryId = apiClient.categories.first?.id ?? 0
                }
                if selectedCategoryId == 0, let first = apiClient.categories.first {
                    selectedCategoryId = first.id
                }
            }
            .onChange(of: apiClient.categories.count) { _, _ in
                if selectedCategoryId != 0, !apiClient.categories.contains(where: { $0.id == selectedCategoryId }) {
                    selectedCategoryId = apiClient.categories.first?.id ?? 0
                }
            }
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) {
                    if resultMessage.contains("Saved") || resultMessage.lowercased().contains("opgeslagen") {
                        isPresented = false
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    private var generalSection: some View {
        Section(header: Text(L10n.string("general"))) {
            TextField(L10n.string("name"), text: $name)
            Picker(L10n.string("category"), selection: $selectedCategoryId) {
                Text(L10n.string("choose_category")).tag(0)
                ForEach(apiClient.categories) { cat in
                    Text(HTMLDecoder.decode(cat.name)).tag(cat.id)
                }
            }
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
                Picker(L10n.string("location_optional"), selection: Binding(
                    get: { selectedLocationId ?? 0 },
                    set: { selectedLocationId = $0 == 0 ? nil : $0 }
                )) {
                    Text(L10n.string("choose_location")).tag(0)
                    ForEach(apiClient.locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { loc in
                        Text(loc.name).tag(loc.id)
                    }
                }
            }
            if !apiClient.companies.isEmpty {
                Picker(L10n.string("company_optional"), selection: Binding(
                    get: { selectedCompanyId ?? 0 },
                    set: { selectedCompanyId = $0 == 0 ? nil : $0 }
                )) {
                    Text(L10n.string("choose_company")).tag(0)
                    ForEach(apiClient.companies.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { company in
                        Text(company.name).tag(company.id)
                    }
                }
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
                Picker(L10n.string("manufacturer_optional"), selection: Binding(
                    get: { selectedManufacturerId ?? 0 },
                    set: { selectedManufacturerId = $0 == 0 ? nil : $0 }
                )) {
                    Text(L10n.string("choose_manufacturer")).tag(0)
                    ForEach(apiClient.manufacturers, id: \.id) { m in
                        Text(HTMLDecoder.decode(m.name)).tag(m.id)
                    }
                }
            }
            if !apiClient.suppliers.isEmpty {
                Picker(L10n.string("supplier_optional"), selection: Binding(
                    get: { selectedSupplierId ?? 0 },
                    set: { selectedSupplierId = $0 == 0 ? nil : $0 }
                )) {
                    Text(L10n.string("choose_supplier")).tag(0)
                    ForEach(apiClient.suppliers, id: \.id) { sup in
                        Text(HTMLDecoder.decode(sup.name)).tag(sup.id)
                    }
                }
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
            let success = await apiClient.updateAccessory(
                accessoryId: accessory.id,
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
                supplierId: selectedSupplierId
            )
            await MainActor.run {
                isSaving = false
                resultMessage = apiClient.lastApiMessage ?? (success ? "Saved." : "Save failed.")
                showResult = true
                if success {
                    onSuccess?()
                    isPresented = false
                }
            }
        }
    }
}
