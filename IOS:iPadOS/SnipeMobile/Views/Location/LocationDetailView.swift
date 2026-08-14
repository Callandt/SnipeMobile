import SwiftUI

struct LocationDetailView: View {
    let location: Location
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isDetailViewActive: Bool
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    var onOpenAccessory: ((Accessory) -> Void)? = nil
    var onOpenLocation: ((Location) -> Void)? = nil
    @State private var selectedTab = 0
    @State private var showEditSheet = false
    @State private var locationAccessories: [Accessory] = []
    @State private var locationAssets: [Asset] = []
    @State private var isLoadingAccessories = false
    @State private var isLoadingAssets = false
    @State private var hasLoadedAssignedItems = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @Environment(\.dismiss) private var dismiss

    // Users at this location.
    private var usersAtLocation: [User] {
        apiClient.users.filter { $0.location?.id == location.id }
    }

    private var currentLocation: Location {
        apiClient.locations.first { $0.id == location.id } ?? location
    }

    private var childLocations: [Location] {
        apiClient.locations
            .filter { $0.parent?.id == location.id }
            .sorted { $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending }
    }

    private var parentLocation: Location? {
        guard let parentId = currentLocation.parent?.id else { return nil }
        return apiClient.locations.first { $0.id == parentId }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var displayParent: Location? {
        if let parent = parentLocation { return parent }
        guard let info = currentLocation.parent, let id = info.id else { return nil }
        let name = cleaned(info.name) ?? ""
        guard !name.isEmpty else { return nil }
        return Location(id: id, name: name)
    }

    private var addressRows: [(label: String, value: String)] {
        let loc = currentLocation
        var rows: [(String, String)] = []
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

    var body: some View {
        VStack(spacing: 0) {
            locationHeader

            LocationDetailTabBar(
                selection: $selectedTab,
                userCount: usersAtLocation.count,
                assetCount: hasLoadedAssignedItems ? locationAssets.count : nil,
                accessoryCount: hasLoadedAssignedItems ? locationAccessories.count : nil,
                locationCount: childLocations.count
            )
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 4)

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
            } else if selectedTab == 2 {
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
            } else {
                if childLocations.isEmpty {
                    ContentUnavailableView(
                        L10n.string("no_child_locations"),
                        systemImage: "mappin.and.ellipse",
                        description: Text(L10n.string("no_child_locations_desc"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 16)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(childLocations) { child in
                                Button { onOpenLocation?(child) } label: {
                                    AssignedLocationCard(location: child)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                .disabled(isDeleting)
                .accessibilityLabel(L10n.string("edit"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(isDeleting)
                .accessibilityLabel(L10n.string("delete"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/locations/\(location.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .entityDeleteSupport(
            showConfirm: $showDeleteConfirm,
            isDeleting: $isDeleting,
            showError: $showDeleteError,
            errorMessage: $deleteErrorMessage,
            confirmTitle: L10n.string("delete_item_confirm_title", currentLocation.decodedName),
            confirmMessage: L10n.string("delete_location_confirm_message", currentLocation.decodedName),
            onDelete: { await deleteCurrentLocation() }
        )
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
        .onAppear { isDetailViewActive = true }
        .hidesTabBarWhenPushed()
        .task(id: location.id) {
            selectedTab = 0
            hasLoadedAssignedItems = false
            await reloadAssignedItems()
        }
    }

    @ViewBuilder
    private var locationHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(currentLocation.decodedName)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)

            if let parent = displayParent {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("parent_location"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    parentLocationCard(parent)
                }
                .padding(.horizontal)
            }

            if !addressRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("location_details"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(addressRows, id: \.label) { row in
                            copyableDetailRow(label: row.label, value: row.value)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func parentLocationCard(_ parent: Location) -> some View {
        let card = HStack(spacing: 0) {
            LocationCardView(location: parent, useExplicitBackground: false)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 16)
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())

        if onOpenLocation != nil, parent.id > 0 {
            Button { onOpenLocation?(parent) } label: { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        let isSingleToken = !value.contains(" ")
        VStack(alignment: .leading, spacing: 4) {
            Text(label).bold()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(isSingleToken ? 1 : nil)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = value
            }) {
                Label(L10n.string("copy"), systemImage: "doc.on.doc")
            }
        }
    }

    private func deleteCurrentLocation() async {
        isDeleting = true
        let ok = await apiClient.deleteLocation(locationId: location.id)
        isDeleting = false
        if ok {
            dismiss()
        } else {
            deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
            showDeleteError = true
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

/// Icon + count tabs so long labels like "Accessories" still fit.
private struct LocationDetailTabBar: View {
    @Binding var selection: Int
    let userCount: Int
    let assetCount: Int?
    let accessoryCount: Int?
    let locationCount: Int

    private struct TabItem: Identifiable {
        let id: Int
        let systemImage: String
        let count: Int?
        let accessibilityLabel: String
    }

    private var tabs: [TabItem] {
        [
            TabItem(
                id: 0,
                systemImage: "person.2",
                count: userCount,
                accessibilityLabel: L10n.string("users_count", userCount)
            ),
            TabItem(
                id: 1,
                systemImage: "laptopcomputer",
                count: assetCount,
                accessibilityLabel: assetCount.map { L10n.string("assets_count", $0) } ?? L10n.string("tab_assets")
            ),
            TabItem(
                id: 2,
                systemImage: "mediastick",
                count: accessoryCount,
                accessibilityLabel: accessoryCount.map { L10n.string("accessories_count", $0) } ?? L10n.string("tab_accessories")
            ),
            TabItem(
                id: 3,
                systemImage: "mappin.and.ellipse",
                count: locationCount,
                accessibilityLabel: L10n.string("child_locations_count", locationCount)
            ),
        ]
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabRow
                    .padding(3)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            } else {
                tabRow
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
    }

    private var tabRow: some View {
        HStack(spacing: 3) {
            ForEach(tabs) { tab in
                let isSelected = selection == tab.id
                Button {
                    selection = tab.id
                } label: {
                    VStack(alignment: .center, spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 22, height: 18)
                        Text(tab.count.map(String.init) ?? "–")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .background {
                        if isSelected {
                            selectedThumb
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(tab.accessibilityLabel)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder
    private var selectedThumb: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.12))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground))
        }
    }
}

