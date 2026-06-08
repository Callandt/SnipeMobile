import SwiftUI

struct LocationDetailView: View {
    let location: Location
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isDetailViewActive: Bool
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    var onOpenAccessory: ((Accessory) -> Void)? = nil
    @State private var selectedTab = 0
    @State private var showEditSheet = false
    @State private var locationAccessories: [Accessory] = []
    @State private var locationAssets: [Asset] = []
    @State private var isLoadingAccessories = false
    @State private var isLoadingAssets = false
    @State private var hasLoadedAssignedItems = false

    // Users at this location.
    private var usersAtLocation: [User] {
        apiClient.users.filter { $0.location?.id == location.id }
    }

    private var currentLocation: Location {
        apiClient.locations.first { $0.id == location.id } ?? location
    }

    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var detailRows: [(label: String, value: String)] {
        let loc = currentLocation
        var rows: [(String, String)] = []
        if let parentName = cleaned(loc.parent?.name) {
            rows.append((L10n.string("parent_location"), HTMLDecoder.decode(parentName)))
        }
        if let address = cleaned(loc.address) {
            rows.append((L10n.string("address"), address))
        }
        if let address2 = cleaned(loc.address2) {
            rows.append((L10n.string("address2"), address2))
        }
        if let zip = cleaned(loc.zip) {
            rows.append((L10n.string("zip"), zip))
        }
        if let city = cleaned(loc.city) {
            rows.append((L10n.string("city"), city))
        }
        if let state = cleaned(loc.state) {
            rows.append((L10n.string("state"), state))
        }
        if let country = cleaned(loc.country) {
            rows.append((L10n.string("country"), country))
        }
        if let currency = cleaned(loc.currency) {
            rows.append((L10n.string("currency"), currency))
        }
        return rows
    }

    private var assetsTabTitle: String {
        hasLoadedAssignedItems
            ? L10n.string("assets_count", locationAssets.count)
            : L10n.string("tab_assets")
    }

    private var accessoriesTabTitle: String {
        hasLoadedAssignedItems
            ? L10n.string("accessories_count", locationAccessories.count)
            : L10n.string("tab_accessories")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !detailRows.isEmpty {
                Text(L10n.string("location_details"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 15) {
                    ForEach(detailRows, id: \.label) { row in
                        copyableDetailRow(label: row.label, value: row.value)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }

            Picker("Select a tab", selection: $selectedTab) {
                Text(L10n.string("users_count", usersAtLocation.count)).tag(0)
                Text(assetsTabTitle).tag(1)
                Text(accessoriesTabTitle).tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 2)

            if selectedTab == 0 {
                if usersAtLocation.isEmpty {
                    ContentUnavailableView(L10n.string("no_users"), systemImage: "person.2", description: Text(L10n.string("no_users_location")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 16)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(usersAtLocation) { user in
                                Button { onOpenUser?(user) } label: {
                                    AssignedUserCard(user: user)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    .background(Color(.systemBackground))
                }
            } else if selectedTab == 1 {
                if isLoadingAssets {
                    ProgressView(L10n.string("loading_assets"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 16)
                } else if locationAssets.isEmpty {
                    ContentUnavailableView(L10n.string("no_assets"), systemImage: "laptopcomputer", description: Text(L10n.string("no_assets_location")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 16)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(locationAssets) { asset in
                                Button { onOpenAsset?(asset) } label: {
                                    AssignedAssetCard(asset: asset)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    .background(Color(.systemBackground))
                }
            } else {
                if isLoadingAccessories {
                    ProgressView(L10n.string("loading_accessories"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 16)
                } else if locationAccessories.isEmpty {
                    ContentUnavailableView(
                        L10n.string("no_accessories"),
                        systemImage: "mediastick",
                        description: Text(L10n.string("no_accessories_location"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 16)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(locationAccessories) { accessory in
                                Button { onOpenAccessory?(accessory) } label: {
                                    AssignedAccessoryCard(accessory: accessory)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }
                    .background(Color(.systemBackground))
                }
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(currentLocation.decodedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(L10n.string("edit"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/locations/\(location.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            LocationEditSheet(
                apiClient: apiClient,
                location: currentLocation,
                isPresented: $showEditSheet,
                onSuccess: {
                    Task {
                        await apiClient.fetchLocations()
                        await reloadAssignedItems()
                    }
                }
            )
        }
        .task(id: location.id) {
            selectedTab = 0
            hasLoadedAssignedItems = false
            DispatchQueue.main.async { isDetailViewActive = true }
            defer { isDetailViewActive = false }
            await reloadAssignedItems()
        }
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        let isSingleToken = !value.contains(" ")
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(label).bold()
                Spacer(minLength: 8)
                Text(value)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).bold()
                Text(value)
                    .lineLimit(isSingleToken ? 1 : nil)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = value
            }) {
                Label(L10n.string("copy"), systemImage: "doc.on.doc")
            }
        }
    }

    private func reloadAssignedItems() async {
        isLoadingAssets = true
        isLoadingAccessories = true
        defer {
            isLoadingAssets = false
            isLoadingAccessories = false
            hasLoadedAssignedItems = true
        }
        async let assets = apiClient.fetchLocationAssets(locationId: location.id)
        async let accessories = apiClient.fetchLocationAccessories(locationId: location.id)
        locationAssets = await assets
        locationAccessories = await accessories
    }
}
