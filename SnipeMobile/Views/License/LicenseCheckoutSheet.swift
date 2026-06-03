import SwiftUI

struct LicenseCheckoutSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let license: License
    let availableSeats: [SnipeITAPIClient.LicenseSeatRow]
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)? = nil

    @State private var selectedTab: Int = 0
    @State private var userSearchText: String = ""
    @State private var assetSearchText: String = ""
    @State private var selectedUser: User? = nil
    @State private var selectedAsset: Asset? = nil
    @State private var note: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var freeSeats: [SnipeITAPIClient.LicenseSeatRow] {
        availableSeats.filter {
            $0.assignedUser == nil &&
            $0.assignedAsset == nil &&
            $0.disabled != true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if license.reassignable == false {
                    Section {
                        Label {
                            Text(L10n.string("checkout_unreassignable_warning"))
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Picker("", selection: $selectedTab) {
                        Text(L10n.string("user")).tag(0)
                        Text(L10n.string("asset")).tag(1)
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
                                        selectedAsset = nil
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 220)
                    } header: {
                        Text(L10n.string("select_user_short"))
                    }
                } else {
                    Section {
                        CheckoutAssetPickerContent(
                            searchText: $assetSearchText,
                            assets: filteredAssets,
                            selectedAssetId: selectedAsset?.id,
                            onSelect: { asset in
                                selectedAsset = asset
                                selectedUser = nil
                            }
                        )
                    } header: {
                        Text(L10n.string("select_asset_short"))
                    }
                }

                Section {
                    TextField(L10n.string("notes"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(L10n.string("notes"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.string("check_out"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("check_out")) { Task { await checkout() } }
                            .disabled(disableConfirm)
                    }
                }
            }
            .alert(L10n.string("error"), isPresented: $showError) {
                Button(L10n.string("ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if apiClient.assets.isEmpty { Task { await apiClient.fetchAssets() } }
            }
        }
    }

    private var disableConfirm: Bool {
        if freeSeats.isEmpty { return true }
        if selectedTab == 0 { return selectedUser == nil }
        return selectedAsset == nil
    }

    private var filteredUsers: [User] {
        apiClient.users
            .filter {
                userSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(userSearchText) ||
                $0.decodedEmail.localizedCaseInsensitiveContains(userSearchText)
            }
            .sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    private var filteredAssets: [Asset] {
        apiClient.assets
            .filter {
                assetSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedAssetTag.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedSerial.localizedCaseInsensitiveContains(assetSearchText)
            }
            .sorted { $0.decodedAssetTag.localizedCaseInsensitiveCompare($1.decodedAssetTag) == .orderedAscending }
    }

    private func checkout() async {
        guard let seat = freeSeats.first else {
            errorMessage = L10n.string("no_free_seats")
            showError = true
            return
        }
        isSaving = true
        defer { isSaving = false }

        let userId = selectedTab == 0 ? selectedUser?.id : nil
        let assetId = selectedTab == 1 ? selectedAsset?.id : nil
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let error = await apiClient.checkoutLicenseSeat(
            licenseId: license.id,
            seatId: seat.id,
            userId: userId,
            assetId: assetId,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        ) {
            errorMessage = error
            showError = true
            return
        }
        onSuccess?()
        isPresented = false
    }
}
