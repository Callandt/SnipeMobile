import SwiftUI

struct AddComponentSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    var onCreated: ((Int?) -> Void)? = nil

    @State private var name: String = ""
    @State private var quantity: Int = 1
    @State private var minAmt: Int = 0
    @State private var serial: String = ""
    @State private var modelNumber: String = ""
    @State private var orderNumber: String = ""
    @State private var purchaseCost: String = ""
    @State private var notes: String = ""

    @State private var purchaseDate: Date = Date()
    @State private var hasPurchaseDate: Bool = false

    @State private var selectedCategoryId: Int = 0
    @State private var selectedManufacturerId: Int = 0
    @State private var selectedSupplierId: Int = 0
    @State private var selectedCompanyId: Int = 0
    @State private var selectedLocationId: Int = 0

    @State private var isSaving = false
    @State private var resultMessage: String = ""
    @State private var showResult = false
    @State private var lastCreatedId: Int?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedCategoryId != 0 &&
        quantity >= 1
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                stockSection
                purchaseSection
                notesSection
            }
            .navigationTitle(L10n.string("new_component"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear(perform: setupOnAppear)
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok")) {
                    if lastCreatedId != nil {
                        onCreated?(lastCreatedId)
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
                Button(L10n.string("create")) { Task { await create() } }
                    .disabled(!canSave)
            }
        }
    }

    private func setupOnAppear() {
        if apiClient.categories.isEmpty { Task { await apiClient.fetchCategories() } }
        if apiClient.manufacturers.isEmpty { Task { await apiClient.fetchManufacturers() } }
        if apiClient.suppliers.isEmpty { Task { await apiClient.fetchSuppliers() } }
        if apiClient.companies.isEmpty { Task { await apiClient.fetchCompanies() } }
        if apiClient.locations.isEmpty { Task { await apiClient.fetchLocations() } }
    }

    private var generalSection: some View {
        Section(L10n.string("general")) {
            TextField(L10n.fieldLabel("name", required: true), text: $name)
            AdaptivePickerRow(
                title: L10n.fieldLabel("category", required: true),
                items: apiClient.categories.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: $selectedCategoryId,
                emptyOption: (0, L10n.string("choose_category"))
            )
            TextField(L10n.string("serial"), text: $serial)
            TextField(L10n.string("model_number"), text: $modelNumber)
            if !apiClient.manufacturers.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("manufacturer"),
                    items: apiClient.manufacturers.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                    selection: $selectedManufacturerId,
                    emptyOption: (0, L10n.string("choose_manufacturer"))
                )
            }
            if !apiClient.locations.isEmpty {
                let sortedLocations = apiClient.locations.sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
                AdaptivePickerRow(
                    title: L10n.string("location"),
                    items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                    selection: $selectedLocationId,
                    emptyOption: (0, L10n.string("choose_location"))
                )
            }
            if !apiClient.companies.isEmpty {
                let sortedCompanies = apiClient.companies.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("company"),
                    items: sortedCompanies.map { (value: $0.id, label: $0.name) },
                    selection: $selectedCompanyId,
                    emptyOption: (0, L10n.string("choose_company"))
                )
            }
        }
    }

    private var stockSection: some View {
        Section(L10n.string("stock_usage")) {
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
        Section(L10n.string("purchase_only")) {
            TextField(L10n.string("order_number"), text: $orderNumber)
            TextField(L10n.string("purchase_price"), text: $purchaseCost)
                .keyboardType(.decimalPad)
            Toggle(L10n.string("purchase_date"), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
            }
            if !apiClient.suppliers.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("supplier"),
                    items: apiClient.suppliers.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                    selection: $selectedSupplierId,
                    emptyOption: (0, L10n.string("choose_supplier"))
                )
            }
        }
    }

    private var notesSection: some View {
        Section(L10n.string("notes")) {
            TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func create() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, selectedCategoryId > 0, quantity >= 1 else { return }

        isSaving = true
        defer { isSaving = false }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)

        let result = await apiClient.createComponent(
            name: trimmedName,
            categoryId: selectedCategoryId,
            quantity: quantity,
            minAmt: minAmt > 0 ? minAmt : nil,
            serial: serial.isEmpty ? nil : serial.trimmingCharacters(in: .whitespaces),
            modelNumber: modelNumber.isEmpty ? nil : modelNumber.trimmingCharacters(in: .whitespaces),
            orderNumber: orderNumber.isEmpty ? nil : orderNumber.trimmingCharacters(in: .whitespaces),
            purchaseCost: purchaseCost.isEmpty ? nil : purchaseCost.trimmingCharacters(in: .whitespaces),
            purchaseDate: hasPurchaseDate ? f.string(from: purchaseDate) : nil,
            companyId: selectedCompanyId > 0 ? selectedCompanyId : nil,
            locationId: selectedLocationId > 0 ? selectedLocationId : nil,
            manufacturerId: selectedManufacturerId > 0 ? selectedManufacturerId : nil,
            supplierId: selectedSupplierId > 0 ? selectedSupplierId : nil,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        lastCreatedId = result.id
        resultMessage = result.success
            ? L10n.string("component_created")
            : (apiClient.lastApiMessage ?? L10n.string("create_failed"))
        showResult = true
    }
}
