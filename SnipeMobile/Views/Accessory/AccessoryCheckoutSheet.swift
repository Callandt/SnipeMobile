import SwiftUI

struct AccessoryCheckoutSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let accessory: Accessory
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)? = nil

    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""
    @State private var userSearchText: String = ""
    @State private var selectedUser: User? = nil
    @State private var selectedTab: Int = 0
    @State private var locationSearchText: String = ""
    @State private var selectedLocation: Location? = nil

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
                    TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(L10n.string("notes"))
                }
            }
            .listStyle(.insetGrouped)
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

    func handleCheckout() {
        isSaving = true
        Task {
            var body: [String: Any] = ["note": notes]
            var success = false
            if selectedTab == 0, let user = selectedUser {
                body["assigned_to"] = user.id
                success = await apiClient.checkoutAccessoryCustom(accessoryId: accessory.id, body: body)
            } else if selectedTab == 1, let location = selectedLocation {
                body["assigned_location"] = location.id
                success = await apiClient.checkoutAccessoryCustom(accessoryId: accessory.id, body: body)
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
}
