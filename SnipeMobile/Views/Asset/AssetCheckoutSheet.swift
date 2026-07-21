import SwiftUI

struct AssetCheckoutSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    @Binding var isPresented: Bool
    var onSuccess: (() async -> Void)? = nil

    @State private var checkoutName: String = ""
    @State private var notes: String = ""
    @State private var expectedCheckin: Date = Date()
    @State private var hasExpectedCheckin: Bool = false
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""
    @State private var userSearchText: String = ""
    @State private var assetSearchText: String = ""
    @State private var locationSearchText: String = ""
    @State private var selectedUser: User? = nil
    @State private var selectedAsset: Asset? = nil
    @State private var selectedLocation: Location? = nil
    @State private var selectedTab: Int = 0
    @State private var selectedImages: [UIImage] = []
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var dismissAfterResult = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $selectedTab) {
                        Text(L10n.string("user")).tag(0)
                        Text(L10n.string("location")).tag(1)
                        Text(L10n.string("asset")).tag(2)
                    }
                    .pickerStyle(.segmented)
                }

                if selectedTab == 0 {
                    Section {
                        CheckoutUserPickerContent(
                            searchText: $userSearchText,
                            users: filteredUsers,
                            selectedUserId: selectedUser?.id,
                            onSelect: { user in
                                clearSelection()
                                selectedUser = user
                            }
                        )
                    } header: {
                        Text(L10n.string("select_user_short"))
                    }
                } else if selectedTab == 1 {
                    Section {
                        CheckoutLocationPickerContent(
                            searchText: $locationSearchText,
                            locations: filteredLocations,
                            selectedLocationId: selectedLocation?.id,
                            onSelect: { location in
                                clearSelection()
                                selectedLocation = location
                            }
                        )
                    } header: {
                        Text(L10n.string("select_location_short"))
                    }
                } else {
                    Section {
                        CheckoutAssetPickerContent(
                            searchText: $assetSearchText,
                            assets: filteredTargetAssets,
                            selectedAssetId: selectedAsset?.id,
                            onSelect: { target in
                                clearSelection()
                                selectedAsset = target
                            }
                        )
                    } header: {
                        Text(L10n.string("select_asset_short"))
                    }
                }

                assetDetailsSection

                AssetPhotosSection(selectedImages: $selectedImages, showCamera: $showCamera)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.visible)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("check_out")) { handleCheckout() }
                            .disabled(!canConfirm)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if apiClient.assets.isEmpty { Task { await apiClient.fetchAssets() } }
            }
            .defaultCheckoutUserSelection(apiClient: apiClient, selectedUser: $selectedUser)
            .assetCameraCover(isPresented: $showCamera, image: $cameraImage)
            .onChange(of: cameraImage) { _, newValue in
                if let newValue {
                    selectedImages.append(newValue)
                    cameraImage = nil
                }
            }
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) {
                    if dismissAfterResult {
                        isPresented = false
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    private var canConfirm: Bool {
        switch selectedTab {
        case 0: return selectedUser != nil
        case 1: return selectedLocation != nil
        default: return selectedAsset != nil
        }
    }

    private func clearSelection() {
        selectedUser = nil
        selectedLocation = nil
        selectedAsset = nil
    }

    var filteredUsers: [User] {
        apiClient.filteredCheckoutUsers(searchText: userSearchText)
    }

    var filteredLocations: [Location] {
        apiClient.locations
            .filter {
                locationSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(locationSearchText)
            }
            .sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    /// Target assets for checkout (exclude the asset being checked out).
    var filteredTargetAssets: [Asset] {
        apiClient.assets
            .filter { $0.id != asset.id }
            .filter {
                assetSearchText.isEmpty ||
                $0.decodedName.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedAssetTag.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedModelName.localizedCaseInsensitiveContains(assetSearchText) ||
                $0.decodedSerial.localizedCaseInsensitiveContains(assetSearchText)
            }
            .sorted { $0.decodedAssetTag.localizedCaseInsensitiveCompare($1.decodedAssetTag) == .orderedAscending }
    }

    @ViewBuilder
    private var assetDetailsSection: some View {
        Section {
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
            var success = false
            if selectedTab == 0, let user = selectedUser {
                body["assigned_user"] = user.id
                body["checkout_to_type"] = "user"
                success = await apiClient.checkoutAssetCustom(assetId: asset.id, body: body)
            } else if selectedTab == 1, let location = selectedLocation {
                body["assigned_location"] = location.id
                body["checkout_to_type"] = "location"
                success = await apiClient.checkoutAssetCustom(assetId: asset.id, body: body)
            } else if selectedTab == 2, let target = selectedAsset {
                body["assigned_asset"] = target.id
                body["checkout_to_type"] = "asset"
                success = await apiClient.checkoutAssetCustom(assetId: asset.id, body: body)
            }
            if success {
                var photoUploadFailed = false
                if !selectedImages.isEmpty {
                    let noteForFiles = notes.isEmpty ? L10n.string("checkout_photo_note") : notes
                    let uploaded = await apiClient.uploadAssetFiles(
                        assetId: asset.id,
                        images: selectedImages,
                        notes: noteForFiles
                    )
                    photoUploadFailed = !uploaded
                }
                await onSuccess?()
                await MainActor.run {
                    isSaving = false
                    if photoUploadFailed {
                        dismissAfterResult = true
                        resultMessage = apiClient.lastApiMessage ?? L10n.string("photo_upload_failed")
                        showResult = true
                    } else {
                        isPresented = false
                    }
                }
            } else {
                await MainActor.run {
                    isSaving = false
                    dismissAfterResult = false
                    resultMessage = apiClient.lastApiMessage ?? L10n.string("checkout_failed")
                    showResult = true
                }
            }
        }
    }

    init(apiClient: SnipeITAPIClient, asset: Asset, isPresented: Binding<Bool>, onSuccess: (() async -> Void)? = nil) {
        self.apiClient = apiClient
        self.asset = asset
        self._isPresented = isPresented
        self.onSuccess = onSuccess
        _checkoutName = State(initialValue: asset.name)
    }
}
