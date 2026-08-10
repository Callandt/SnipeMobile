import SwiftUI

struct AddLocationSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isPresented: Bool
    var onCreated: ((Int?) -> Void)? = nil

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var address2: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var country: String = ""
    @State private var zip: String = ""
    @State private var currency: String = ""
    @State private var selectedParentId: Int = 0

    @State private var isSaving = false
    @State private var resultMessage: String = ""
    @State private var showResult = false
    @State private var lastCreatedId: Int?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                addressSection
            }
            .navigationTitle(L10n.string("new_location"))
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
        if apiClient.locations.isEmpty { Task { await apiClient.fetchLocations() } }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(L10n.string("general")) {
            TextField(L10n.fieldLabel("name", required: true), text: $name)
            if !apiClient.locations.isEmpty {
                let sortedLocations = apiClient.locations.sorted {
                    $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending
                }
                CreatableAdaptivePickerRow(
                    title: L10n.string("parent_location"),
                    items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                    selection: $selectedParentId,
                    emptyOption: (0, L10n.string("choose_location")),
                    apiClient: apiClient,
                    creatableLocation: true
                )
            }
            TextField(L10n.string("currency"), text: $currency)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
        }
    }

    private var addressSection: some View {
        Section(L10n.string("address")) {
            TextField(L10n.string("address"), text: $address)
            TextField(L10n.string("address2"), text: $address2)
            TextField(L10n.string("city"), text: $city)
            TextField(L10n.string("state"), text: $state)
            TextField(L10n.string("country"), text: $country)
            TextField(L10n.string("zip"), text: $zip)
        }
    }

    // MARK: - Save

    private func create() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        var body: [String: Any] = ["name": trimmedName]
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        if !trimmedAddress.isEmpty { body["address"] = trimmedAddress }
        let trimmedAddress2 = address2.trimmingCharacters(in: .whitespaces)
        if !trimmedAddress2.isEmpty { body["address2"] = trimmedAddress2 }
        let trimmedCity = city.trimmingCharacters(in: .whitespaces)
        if !trimmedCity.isEmpty { body["city"] = trimmedCity }
        let trimmedState = state.trimmingCharacters(in: .whitespaces)
        if !trimmedState.isEmpty { body["state"] = trimmedState }
        let trimmedCountry = country.trimmingCharacters(in: .whitespaces)
        if !trimmedCountry.isEmpty { body["country"] = trimmedCountry }
        let trimmedZip = zip.trimmingCharacters(in: .whitespaces)
        if !trimmedZip.isEmpty { body["zip"] = trimmedZip }
        let trimmedCurrency = currency.trimmingCharacters(in: .whitespaces)
        if !trimmedCurrency.isEmpty { body["currency"] = trimmedCurrency }
        if selectedParentId > 0 { body["parent_id"] = selectedParentId }

        let result = await apiClient.createLocation(body: body)
        lastCreatedId = result.id
        if result.success {
            await apiClient.fetchLocations()
            if let onCreated {
                onCreated(result.id)
                isPresented = false
                return
            }
            resultMessage = L10n.string("location_created")
        } else {
            resultMessage = result.message ?? L10n.string("create_failed")
        }
        showResult = true
    }
}
