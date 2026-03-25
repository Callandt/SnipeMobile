import SwiftUI

struct AssetCheckinSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    @Binding var isPresented: Bool

    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""
    @State private var selectedStatusId: Int? = nil
    @State private var name: String = ""
    @State private var selectedLocationId: Int? = nil

    var sortedLocations: [Location] {
        apiClient.locations.sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AdaptivePickerRow(
                        title: L10n.string("status"),
                        items: apiClient.statusLabels.sorted(by: { ($0.statusMeta ?? "") < ($1.statusMeta ?? "") }).map { (value: $0.id, label: $0.statusMeta ?? "") },
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
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.string("check_in_asset"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L10n.string("check_in")) { performCheckin() }
                    }
                }
            }
            .onAppear {
                name = asset.name
                let validIds = Set(apiClient.statusLabels.map(\.id))
                if let id = selectedStatusId, !validIds.contains(id) {
                    selectedStatusId = apiClient.statusLabels.first(where: { $0.statusMeta?.lowercased() == "deployable" })?.id
                } else if selectedStatusId == nil {
                    if let ready = apiClient.statusLabels.first(where: { $0.statusMeta?.lowercased() == "deployable" }) {
                        selectedStatusId = ready.id
                    }
                }
            }
            .onChange(of: apiClient.statusLabels.count) { _, _ in
                if let id = selectedStatusId, !apiClient.statusLabels.contains(where: { $0.id == id }) {
                    selectedStatusId = apiClient.statusLabels.first(where: { $0.statusMeta?.lowercased() == "deployable" })?.id
                }
            }
            .alert(L10n.string("result"), isPresented: $showResult) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(resultMessage)
            }
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
            await MainActor.run {
                isSaving = false
                resultMessage = apiClient.lastApiMessage ?? (success ? L10n.string("checkin_success") : L10n.string("checkin_failed"))
                showResult = true
                if success { isPresented = false }
            }
        }
    }
}
