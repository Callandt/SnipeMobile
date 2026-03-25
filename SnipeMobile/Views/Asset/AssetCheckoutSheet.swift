import SwiftUI

struct AssetCheckoutSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)? = nil

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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $selectedTab) {
                        Text(L10n.string("user")).tag(0)
                        Text(L10n.string("location")).tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedTab == 0 {
                    Section {
                        TextField(L10n.string("search_users"), text: $userSearchText)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredUsers) { user in
                                    UserRow(user: user, isSelected: selectedUser?.id == user.id) {
                                        selectedUser = user
                                        selectedLocation = nil
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 200)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    } header: {
                        Text(L10n.string("select_user_short"))
                    }
                } else {
                    Section {
                        TextField(L10n.string("search_locations"), text: $locationSearchText)
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredLocations) { location in
                                    LocationRow(location: location, isSelected: selectedLocation?.id == location.id) {
                                        selectedLocation = location
                                        selectedUser = nil
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 200)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    } header: {
                        Text(L10n.string("select_location_short"))
                    }
                }

                Section {
                    if !deployableStatusLabels.isEmpty {
                        AdaptivePickerRow(
                            title: L10n.string("status"),
                            items: deployableStatusLabels.map { (value: $0.id, label: $0.statusMeta ?? "") },
                            selection: Binding(
                                get: { selectedStatusId ?? -1 },
                                set: { selectedStatusId = $0 == -1 ? nil : $0 }
                            ),
                            emptyOption: (-1, L10n.string("none"))
                        )
                    }
                    TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    Toggle(L10n.string("expected_checkin"), isOn: $hasExpectedCheckin)
                    if hasExpectedCheckin {
                        DatePicker(L10n.string("expected_checkin_date"), selection: $expectedCheckin, displayedComponents: .date)
                    }
                } header: {
                    Text(L10n.string("asset_details"))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.visible)
            .background(Color(.systemGroupedBackground))
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
                        Button(L10n.string("check_out")) { handleCheckout() }
                            .disabled(selectedTab == 0 ? selectedUser == nil : selectedLocation == nil)
                    }
                }
            }
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(resultMessage)
            }
            .onChange(of: apiClient.statusLabels.count) { _, _ in
                if let id = selectedStatusId, !deployableStatusLabels.contains(where: { $0.id == id }) {
                    selectedStatusId = deployableStatusLabels.first?.id
                }
            }
        }
    }

    var filteredUsers: [User] {
        apiClient.users
            .filter {
                userSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(userSearchText) ||
                $0.decodedEmail.localizedCaseInsensitiveContains(userSearchText)
            }
            .sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    var filteredLocations: [Location] {
        apiClient.locations
            .filter {
                locationSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(locationSearchText)
            }
            .sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    var deployableStatusLabels: [StatusLabel] {
        apiClient.statusLabels.filter { $0.statusMeta?.lowercased() == "deployable" }
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
            await MainActor.run {
                isSaving = false
                resultMessage = apiClient.lastApiMessage ?? (success ? L10n.string("checkout_success") : L10n.string("checkout_failed"))
                showResult = true
                if success {
                    isPresented = false
                    onSuccess?()
                }
            }
        }
    }

    init(apiClient: SnipeITAPIClient, asset: Asset, isPresented: Binding<Bool>, onSuccess: (() -> Void)? = nil) {
        self.apiClient = apiClient
        self.asset = asset
        self._isPresented = isPresented
        self.onSuccess = onSuccess
        if let firstDeployable = apiClient.statusLabels.first(where: { $0.statusMeta?.lowercased() == "deployable" }) {
            _selectedStatusId = State(initialValue: firstDeployable.id)
        } else {
            _selectedStatusId = State(initialValue: nil)
        }
        _checkoutName = State(initialValue: asset.name)
    }
}

struct UserRow: View {
    let user: User
    let isSelected: Bool
    let onSelect: () -> Void
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.decodedName)
                        .foregroundStyle(.primary)
                    Text(user.decodedEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct LocationRow: View {
    let location: Location
    let isSelected: Bool
    let onSelect: () -> Void
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(location.decodedName)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
