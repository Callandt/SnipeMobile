import SwiftUI

struct AssetCheckoutSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    @Binding var isPresented: Bool

    @State private var checkoutName: String = ""
    @State private var notes: String = ""
    @State private var expectedCheckin: Date = Date()
    @State private var hasExpectedCheckin: Bool = false
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""
    @State private var userSearchText: String = ""
    @State private var selectedUser: User? = nil
    @State private var selectedTab: Int = 0 // 0 = user, 1 = location
    @State private var locationSearchText: String = ""
    @State private var selectedLocation: Location? = nil
    @State private var selectedStatusId: Int? = nil
    // Dummy user/location id for testing
    let dummyUserId: Int = 1
    let dummyLocationId: Int = 1

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        Picker("Check out to", selection: $selectedTab) {
                            Text("User").tag(0)
                            Text("Location").tag(1)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        .padding(.top, 8)

                        if selectedTab == 0 {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Selecteer gebruiker")
                                    .font(.headline)
                                    .foregroundColor(Color.primary)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 12)
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.gray)
                                    TextField("Zoek gebruiker...", text: $userSearchText)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .foregroundColor(Color.primary)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .padding(.horizontal, 14)
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(filteredUsers.indices, id: \ .self) { idx in
                                            let user = filteredUsers[idx]
                                            UserRow(user: user, isSelected: selectedUser?.id == user.id) {
                                                self.selectedUser = user
                                                self.selectedLocation = nil
                                            }
                                            .background(Color(.systemBackground))
                                            .padding(.vertical, 6)
                                            if idx < filteredUsers.count - 1 {
                                                Divider().padding(.leading, 8)
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 220)
                                .background(Color(.systemBackground))
                                .cornerRadius(14)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 4)
                            .padding(.horizontal, 10)
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Selecteer locatie")
                                    .font(.headline)
                                    .foregroundColor(Color.primary)
                                    .padding(.horizontal, 18)
                                    .padding(.top, 12)
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.gray)
                                    TextField("Zoek locatie...", text: $locationSearchText)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .foregroundColor(Color.primary)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .padding(.horizontal, 14)
                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        ForEach(filteredLocations.indices, id: \ .self) { idx in
                                            let location = filteredLocations[idx]
                                            LocationRow(location: location, isSelected: selectedLocation?.id == location.id) {
                                                self.selectedLocation = location
                                                self.selectedUser = nil
                                            }
                                            .background(Color(.systemBackground))
                                            .padding(.vertical, 6)
                                            if idx < filteredLocations.count - 1 {
                                                Divider().padding(.leading, 8)
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 220)
                                .background(Color(.systemBackground))
                                .cornerRadius(14)
                                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 4)
                            .padding(.horizontal, 10)
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            Text("Asset details")
                                .font(.headline)
                                .foregroundColor(Color.primary)
                                .padding(.horizontal, 18)
                                .padding(.top, 12)
                            VStack(spacing: 12) {
                                // Status picklist
                                if !deployableStatusLabels.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Status")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 0)
                                        Picker("Status", selection: $selectedStatusId) {
                                            ForEach(deployableStatusLabels, id: \.id) { status in
                                                Text(status.name).tag(Optional(status.id))
                                            }
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(10)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 0)
                                }
                                TextField("Naam (custom asset naam)", text: $checkoutName)
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(12)
                                    .foregroundColor(Color.primary)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 14)
                            Text("Notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 18)
                            TextEditor(text: $notes)
                                .frame(minHeight: 60)
                                .padding(8)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .foregroundColor(Color.primary)
                                .padding(.horizontal, 14)
                            Toggle("Expected Checkin", isOn: $hasExpectedCheckin)
                                .padding(.horizontal, 18)
                            if hasExpectedCheckin {
                                DatePicker("Datum", selection: $expectedCheckin, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .padding(.horizontal, 18)
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 10)

                        Button(action: handleCheckout) {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Check Out")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background((selectedTab == 0 ? selectedUser == nil : selectedLocation == nil) ? Color.gray.opacity(0.4) : Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(color: Color.accentColor.opacity(0.18), radius: 8, x: 0, y: 3)
                            }
                        }
                        .disabled(isSaving || (selectedTab == 0 ? selectedUser == nil : selectedLocation == nil))
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("Check Out")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { isPresented = false }
                }
            }
            .alert(isPresented: $showResult) {
                Alert(title: Text("Resultaat"), message: Text(resultMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    var filteredUsers: [User] {
        print("DEBUG: filteredUsers count=\(apiClient.users.count)")
        return apiClient.users
            .filter {
                userSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(userSearchText) ||
                $0.decodedEmail.localizedCaseInsensitiveContains(userSearchText)
            }
            .sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    var filteredLocations: [Location] {
        print("DEBUG: filteredLocations count=\(apiClient.locations.count)")
        return apiClient.locations
            .filter {
                locationSearchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(locationSearchText)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var deployableStatusLabels: [StatusLabel] {
        apiClient.statusLabels.filter { $0.type?.lowercased() == "deployable" }
    }

    func handleCheckout() {
        isSaving = true
        Task {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            var body: [String: Any] = [
                "name": checkoutName,
                "note": notes
            ]
            if hasExpectedCheckin {
                body["expected_checkin"] = formatter.string(from: expectedCheckin)
            }
            if let statusId = selectedStatusId {
                body["status_id"] = statusId
            }
            var success = false
            if selectedTab == 0, let user = selectedUser {
                body["assigned_user"] = user.id
                body["checkout_to_type"] = "user"
                success = await apiClient.checkoutAssetCustom(assetId: asset.id, body: body)
            } else if selectedTab == 1, let location = selectedLocation {
                body["assigned_location"] = location.id
                body["checkout_to_type"] = "location"
                success = await apiClient.checkoutAssetCustom(assetId: asset.id, body: body)
            }
            isSaving = false
            resultMessage = apiClient.lastApiMessage ?? (success ? "Check-out gelukt!" : "Check-out mislukt.")
            showResult = true
            if success { isPresented = false }
        }
    }

    // Set a default status selection if none is set and deployableStatusLabels is not empty
    init(apiClient: SnipeITAPIClient, asset: Asset, isPresented: Binding<Bool>) {
        self.apiClient = apiClient
        self.asset = asset
        self._isPresented = isPresented
        // Default selection for status picker to avoid nil tag warning
        if let firstDeployable = apiClient.statusLabels.first(where: { $0.type?.lowercased() == "deployable" }) {
            _selectedStatusId = State(initialValue: firstDeployable.id)
        } else {
            _selectedStatusId = State(initialValue: nil)
        }
        // Prefill checkoutName with asset name
        _checkoutName = State(initialValue: asset.name)
    }
}

struct UserRow: View {
    let user: User
    let isSelected: Bool
    let onSelect: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(user.decodedName)
                Text(user.decodedEmail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

struct LocationRow: View {
    let location: Location
    let isSelected: Bool
    let onSelect: () -> Void
    var body: some View {
        HStack {
            Text(location.name)
                .foregroundColor(Color.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
} 