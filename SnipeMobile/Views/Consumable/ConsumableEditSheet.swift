import SwiftUI

struct ConsumableEditSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let consumable: Consumable
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)? = nil

    @State private var name: String = ""
    @State private var selectedCategoryId: Int = 0
    @State private var quantity: Int = 1
    @State private var minAmt: Int = 0
    @State private var itemNo: String = ""
    @State private var modelNumber: String = ""
    @State private var orderNumber: String = ""
    @State private var purchaseCost: String = ""
    @State private var notes: String = ""
    @State private var purchaseDate: Date = Date()
    @State private var hasPurchaseDate: Bool = false
    @State private var selectedLocationId: Int?
    @State private var selectedCompanyId: Int?
    @State private var selectedManufacturerId: Int?
    @State private var selectedSupplierId: Int?

    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                stockSection
                purchaseSection
                notesSection
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
                        Button(L10n.string("save")) { save() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategoryId == 0)
                    }
                }
            }
            .onAppear(perform: setup)
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

    private func setup() {
        name = consumable.decodedName
        selectedCategoryId = consumable.category?.id ?? 0
        quantity = consumable.qty ?? 1
        minAmt = consumable.minAmt ?? 0
        itemNo = consumable.decodedItemNo
        modelNumber = consumable.decodedModelNumber
        selectedLocationId = consumable.location?.id
        selectedCompanyId = consumable.company?.id
        selectedManufacturerId = consumable.manufacturer?.id
        selectedSupplierId = consumable.supplier?.id
        orderNumber = HTMLDecoder.decode(consumable.orderNumber ?? "")
        purchaseCost = consumable.purchaseCost ?? ""
        notes = HTMLDecoder.decode(consumable.notes ?? "")
        if let pd = consumable.purchaseDate, !pd.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let d = formatter.date(from: pd) {
                purchaseDate = d
                hasPurchaseDate = true
            }
        }
        if apiClient.categories.isEmpty { Task { await apiClient.fetchCategories() } }
        if apiClient.locations.isEmpty { Task { await apiClient.fetchLocations() } }
        if apiClient.companies.isEmpty { Task { await apiClient.fetchCompanies() } }
        if apiClient.manufacturers.isEmpty { Task { await apiClient.fetchManufacturers() } }
        if apiClient.suppliers.isEmpty { Task { await apiClient.fetchSuppliers() } }
        let consumableCategories = apiClient.categories(for: "consumable")
        let validCategoryIds = Set(consumableCategories.map(\.id))
        if selectedCategoryId != 0, !validCategoryIds.contains(selectedCategoryId) {
            selectedCategoryId = consumableCategories.first?.id ?? 0
        }
        if selectedCategoryId == 0, let first = consumableCategories.first {
            selectedCategoryId = first.id
        }
    }

    private var generalSection: some View {
        Section(header: Text(L10n.string("general"))) {
            TextField(L10n.fieldLabel("name", required: true), text: $name)
            AdaptivePickerRow(
                title: L10n.fieldLabel("category", required: true),
                items: apiClient.categories(for: "consumable").map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: $selectedCategoryId,
                emptyOption: (0, L10n.string("choose_category"))
            )
            TextField(L10n.string("item_no"), text: $itemNo)
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
                AdaptivePickerRow(
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

    private var stockSection: some View {
        Section(header: Text(L10n.string("stock_usage"))) {
            HStack {
                Text(L10n.fieldLabel("quantity", required: true))
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
        }
    }

    private var purchaseSection: some View {
        Section(header: Text(L10n.string("purchase_only"))) {
            TextField(L10n.string("order_number"), text: $orderNumber)
            TextField(L10n.string("purchase_price"), text: $purchaseCost)
                .keyboardType(.decimalPad)
            Toggle(L10n.string("purchase_date"), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
            }
            if !apiClient.manufacturers.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("manufacturer"),
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
    }

    private var notesSection: some View {
        Section(header: Text(L10n.string("notes"))) {
            TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func save() {
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
            let success = await apiClient.updateConsumable(
                consumableId: consumable.id,
                name: name.trimmingCharacters(in: .whitespaces),
                categoryId: selectedCategoryId,
                quantity: quantity,
                minAmt: minAmt > 0 ? minAmt : nil,
                itemNo: itemNo.isEmpty ? nil : itemNo.trimmingCharacters(in: .whitespaces),
                modelNumber: modelNumber.isEmpty ? nil : modelNumber.trimmingCharacters(in: .whitespaces),
                orderNumber: orderNumber.isEmpty ? nil : orderNumber.trimmingCharacters(in: .whitespaces),
                purchaseCost: purchaseCost.isEmpty ? nil : purchaseCost.trimmingCharacters(in: .whitespaces),
                purchaseDate: purchaseDateStr,
                companyId: selectedCompanyId,
                locationId: selectedLocationId,
                manufacturerId: selectedManufacturerId,
                supplierId: selectedSupplierId,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
