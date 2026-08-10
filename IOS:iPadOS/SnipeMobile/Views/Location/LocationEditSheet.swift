import SwiftUI

struct LocationEditSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let location: Location
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)? = nil

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
    @State private var errorMessage: String?
    @State private var showError = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                addressSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.string("edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("save")) { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .onAppear(perform: prefill)
            .alert(L10n.string("error"), isPresented: $showError) {
                Button(L10n.string("ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(L10n.string("general")) {
            TextField(L10n.fieldLabel("name", required: true), text: $name)
            let sortedLocations = apiClient.locations
                .filter { $0.id != location.id }
                .sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
            if !sortedLocations.isEmpty {
                AdaptivePickerRow(
                    title: L10n.string("parent_location"),
                    items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                    selection: $selectedParentId,
                    emptyOption: (0, L10n.string("choose_location"))
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

    // MARK: - Helpers

    private func prefill() {
        name = location.decodedName
        address = HTMLDecoder.decode(location.address ?? "")
        address2 = HTMLDecoder.decode(location.address2 ?? "")
        city = HTMLDecoder.decode(location.city ?? "")
        state = HTMLDecoder.decode(location.state ?? "")
        country = HTMLDecoder.decode(location.country ?? "")
        zip = HTMLDecoder.decode(location.zip ?? "")
        currency = HTMLDecoder.decode(location.currency ?? "")
        selectedParentId = location.parent?.id ?? 0

        if apiClient.locations.isEmpty { Task { await apiClient.fetchLocations() } }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        var body: [String: Any] = [
            "name": trimmedName,
            "address": address.trimmingCharacters(in: .whitespaces),
            "address2": address2.trimmingCharacters(in: .whitespaces),
            "city": city.trimmingCharacters(in: .whitespaces),
            "state": state.trimmingCharacters(in: .whitespaces),
            "country": country.trimmingCharacters(in: .whitespaces),
            "zip": zip.trimmingCharacters(in: .whitespaces),
            "currency": currency.trimmingCharacters(in: .whitespaces)
        ]
        body["parent_id"] = selectedParentId > 0 ? selectedParentId : NSNull()

        if let error = await apiClient.updateLocation(locationId: location.id, body: body) {
            errorMessage = error
            showError = true
            return
        }
        onSuccess?()
        isPresented = false
    }
}
