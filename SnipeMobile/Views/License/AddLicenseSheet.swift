import SwiftUI

struct AddLicenseSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    var onCreated: ((Int?) -> Void)? = nil

    @State private var name: String = ""
    @State private var serial: String = ""
    @State private var seats: Int = 1
    @State private var minAmt: Int = 0
    @State private var licensedToName: String = ""
    @State private var licensedToEmail: String = ""
    @State private var orderNumber: String = ""
    @State private var purchaseOrder: String = ""
    @State private var purchaseCost: String = ""
    @State private var notes: String = ""

    @State private var purchaseDate: Date = Date()
    @State private var hasPurchaseDate: Bool = false
    @State private var expirationDate: Date = Date()
    @State private var hasExpirationDate: Bool = false
    @State private var terminationDate: Date = Date()
    @State private var hasTerminationDate: Bool = false

    @State private var selectedCategoryId: Int = 0
    @State private var selectedManufacturerId: Int = 0
    @State private var selectedSupplierId: Int = 0
    @State private var selectedCompanyId: Int = 0

    @State private var reassignable: Bool = true
    @State private var maintained: Bool = false

    @State private var isSaving = false
    @State private var resultMessage: String = ""
    @State private var showResult = false
    @State private var lastCreatedId: Int?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        selectedCategoryId != 0 &&
        seats >= 1
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                seatsSection
                licensedToSection
                purchaseSection
                notesSection
            }
            .navigationTitle(L10n.string("new_license"))
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

    // MARK: - Toolbar

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
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(L10n.string("general")) {
            TextField(L10n.string("name"), text: $name)
            TextField(L10n.string("product_key"), text: $serial)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            AdaptivePickerRow(
                title: L10n.string("category"),
                items: apiClient.categories.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                selection: $selectedCategoryId,
                emptyOption: (0, L10n.string("choose_category"))
            )
            if !apiClient.manufacturers.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("manufacturer_optional"),
                    items: apiClient.manufacturers.map { (value: $0.id, label: HTMLDecoder.decode($0.name)) },
                    selection: $selectedManufacturerId,
                    emptyOption: (0, L10n.string("choose_manufacturer"))
                )
            }
            if !apiClient.companies.isEmpty {
                let sortedCompanies = apiClient.companies.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                AdaptivePickerRow(
                    title: L10n.string("company_optional"),
                    items: sortedCompanies.map { (value: $0.id, label: $0.name) },
                    selection: $selectedCompanyId,
                    emptyOption: (0, L10n.string("choose_company"))
                )
            }
        }
    }

    private var seatsSection: some View {
        Section(L10n.string("seats")) {
            HStack {
                Text(L10n.string("seats"))
                Spacer()
                TextField("", value: $seats, format: .number)
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
            Toggle(L10n.string("reassignable"), isOn: $reassignable)
            Toggle(L10n.string("maintained"), isOn: $maintained)
        }
    }

    private var licensedToSection: some View {
        Section(L10n.string("licensed_to")) {
            TextField(L10n.string("license_to_name"), text: $licensedToName)
            TextField(L10n.string("license_to_email"), text: $licensedToEmail)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
    }

    private var purchaseSection: some View {
        Section(L10n.string("purchase_only")) {
            TextField(L10n.string("order_number_optional"), text: $orderNumber)
            TextField(L10n.string("purchase_order_optional"), text: $purchaseOrder)
            TextField(L10n.string("purchase_price_optional"), text: $purchaseCost)
                .keyboardType(.decimalPad)
            Toggle(L10n.string("purchase_date"), isOn: $hasPurchaseDate)
            if hasPurchaseDate {
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
            }
            Toggle(L10n.string("expiration_date"), isOn: $hasExpirationDate)
            if hasExpirationDate {
                DatePicker("", selection: $expirationDate, displayedComponents: .date)
            }
            Toggle(L10n.string("termination_date"), isOn: $hasTerminationDate)
            if hasTerminationDate {
                DatePicker("", selection: $terminationDate, displayedComponents: .date)
            }
            if !apiClient.suppliers.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("supplier_optional"),
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

    // MARK: - Save

    private func create() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, selectedCategoryId > 0, seats >= 1 else { return }

        isSaving = true
        defer { isSaving = false }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)

        var body: [String: Any] = [
            "name": trimmedName,
            "seats": seats,
            "category_id": selectedCategoryId,
            "reassignable": reassignable ? 1 : 0,
            "maintained": maintained ? 1 : 0
        ]
        if minAmt > 0 { body["min_amt"] = minAmt }
        let trimmedSerial = serial.trimmingCharacters(in: .whitespaces)
        if !trimmedSerial.isEmpty { body["serial"] = trimmedSerial }
        let trimmedLicenseName = licensedToName.trimmingCharacters(in: .whitespaces)
        if !trimmedLicenseName.isEmpty { body["license_name"] = trimmedLicenseName }
        let trimmedEmail = licensedToEmail.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty { body["license_email"] = trimmedEmail }
        let trimmedOrder = orderNumber.trimmingCharacters(in: .whitespaces)
        if !trimmedOrder.isEmpty { body["order_number"] = trimmedOrder }
        let trimmedPurchaseOrder = purchaseOrder.trimmingCharacters(in: .whitespaces)
        if !trimmedPurchaseOrder.isEmpty { body["purchase_order"] = trimmedPurchaseOrder }
        if let cost = NumberFormatHelpers.normalizeDecimalForAPI(purchaseCost), !cost.isEmpty {
            body["purchase_cost"] = cost
        }
        if hasPurchaseDate { body["purchase_date"] = f.string(from: purchaseDate) }
        if hasExpirationDate { body["expiration_date"] = f.string(from: expirationDate) }
        if hasTerminationDate { body["termination_date"] = f.string(from: terminationDate) }
        if selectedManufacturerId > 0 { body["manufacturer_id"] = selectedManufacturerId }
        if selectedSupplierId > 0 { body["supplier_id"] = selectedSupplierId }
        if selectedCompanyId > 0 { body["company_id"] = selectedCompanyId }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty { body["notes"] = trimmedNotes }

        let result = await apiClient.createLicense(body: body)
        lastCreatedId = result.id
        resultMessage = result.success
            ? L10n.string("license_created")
            : (result.message ?? L10n.string("create_failed"))
        showResult = true
    }
}
