import SwiftUI

struct AssetCheckinSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    @Binding var isPresented: Bool
    var onSuccess: (() async -> Void)? = nil

    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var ephemeralNotice: EphemeralNotice?
    @State private var selectedStatusId: Int? = nil
    @State private var name: String = ""
    @State private var selectedLocationId: Int? = nil
    @State private var selectedImages: [UIImage] = []
    @State private var showCamera = false
    @State private var cameraImage: UIImage?

    var sortedLocations: [Location] {
        apiClient.locations.sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    private var statusPickerItems: [(value: Int, label: String)] {
        // Prefer deployable statuses after check-in.
        let deployable = apiClient.statusLabels.filter(\.isDeployableType)
        let source = deployable.isEmpty ? apiClient.statusLabels : deployable
        return AssetStatusFilterSupport.sortedStatusLabels(source)
            .map { (value: $0.id, label: AssetStatusFilterSupport.displayName(for: $0)) }
    }

    private func ensureDefaultStatus() {
        let deployable = apiClient.statusLabels.filter(\.isDeployableType)
        let pool = deployable.isEmpty ? apiClient.statusLabels : deployable
        let validIds = Set(pool.map(\.id))
        if let id = selectedStatusId, validIds.contains(id) { return }
        selectedStatusId =
            pool.first(where: { AssetStatusFilterSupport.isReadyToDeployLabel($0) })?.id
            ?? pool.first?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AdaptivePickerRow(
                        title: L10n.string("status"),
                        items: statusPickerItems,
                        selection: Binding(
                            get: { selectedStatusId ?? -1 },
                            set: { selectedStatusId = $0 == -1 ? nil : $0 }
                        ),
                        emptyOption: (-1, L10n.string("none"))
                    )
                    TextField(L10n.string("name"), text: $name)
                    TextField(L10n.string("notes"), text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    AdaptivePickerRow(
                        title: L10n.string("location"),
                        items: sortedLocations.map { (value: $0.id, label: $0.decodedName) },
                        selection: Binding(
                            get: { selectedLocationId ?? -1 },
                            set: { selectedLocationId = $0 == -1 ? nil : $0 }
                        ),
                        emptyOption: (-1, L10n.string("none"))
                    )
                } header: {
                    Text(L10n.string("asset_details"))
                } footer: {
                    Text(L10n.string("name_help_checkin"))
                }

                AssetPhotosSection(selectedImages: $selectedImages, showCamera: $showCamera)
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.string("check_in_asset"))
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
                        Button(L10n.string("check_in")) { performCheckin() }
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                name = asset.name
                if apiClient.statusLabels.isEmpty {
                    Task { await apiClient.fetchStatusLabels() }
                }
                ensureDefaultStatus()
            }
            .onChange(of: apiClient.statusLabels.count) { _, _ in
                ensureDefaultStatus()
            }
            .assetCameraCover(isPresented: $showCamera, image: $cameraImage)
            .onChange(of: cameraImage) { _, newValue in
                if let newValue {
                    selectedImages.append(newValue)
                    cameraImage = nil
                }
            }
            .ephemeralNotice($ephemeralNotice)
        }
    }

    private func performCheckin() {
        isSaving = true
        Task {
            var body: [String: Any] = [:]
            if let statusId = selectedStatusId { body["status_id"] = statusId }
            if !name.isEmpty, name != asset.name { body["name"] = name }
            if !notes.isEmpty { body["note"] = notes }
            if let locationId = selectedLocationId { body["location_id"] = locationId }
            let success = await apiClient.checkinAssetCustom(assetId: asset.id, body: body)

            var photoUploadFailed = false
            if success, !selectedImages.isEmpty {
                let noteForFiles = notes.isEmpty ? L10n.string("checkin_photo_note") : notes
                let uploaded = await apiClient.uploadAssetFiles(
                    assetId: asset.id,
                    images: selectedImages,
                    notes: noteForFiles
                )
                photoUploadFailed = !uploaded
            }

            if success {
                await onSuccess?()
            }

            await MainActor.run {
                isSaving = false
                if success {
                    if photoUploadFailed {
                        presentEphemeralNotice(
                            $ephemeralNotice,
                            apiClient.lastApiMessage ?? L10n.string("photo_upload_failed"),
                            isError: true
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            isPresented = false
                        }
                    } else {
                        isPresented = false
                    }
                } else {
                    presentEphemeralNotice(
                        $ephemeralNotice,
                        apiClient.lastApiMessage ?? L10n.string("checkin_failed"),
                        isError: true
                    )
                }
            }
        }
    }
}
