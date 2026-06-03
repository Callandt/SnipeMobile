import SwiftUI

struct LocationDetailView: View {
    let location: Location
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    var onOpenAccessory: ((Accessory) -> Void)? = nil
    @State private var locationAccessories: [Accessory] = []
    @State private var locationAssets: [Asset] = []
    @State private var isLoadingAccessories = false
    @State private var isLoadingAssets = false

    // Users at this location.
    private var usersAtLocation: [User] {
        apiClient.users.filter { $0.location?.id == location.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Select a tab", selection: $selectedTab) {
                Text(L10n.string("users_count", usersAtLocation.count)).tag(0)
                Text(L10n.string("assets_count", locationAssets.count)).tag(1)
                Text(L10n.string("accessories_count", locationAccessories.count)).tag(2)
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
        .onAppear { isDetailViewActive = true }
        .onDisappear { isDetailViewActive = false }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(returnToTab != nil)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(location.decodedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let _ = returnToTab, let onBack = onBackToPrevious {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onBack()
                    } label: {
                        Label(L10n.string("back"), systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/locations/\(location.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear {
            selectedTab = 0
            reloadAssignedItems()
        }
        .onChange(of: location.id) { _, _ in
            reloadAssignedItems()
        }
    }

    private func reloadAssignedItems() {
        Task {
            isLoadingAssets = true
            isLoadingAccessories = true
            async let assets = apiClient.fetchLocationAssets(locationId: location.id)
            async let accessories = apiClient.fetchLocationAccessories(locationId: location.id)
            locationAssets = await assets
            locationAccessories = await accessories
            isLoadingAssets = false
            isLoadingAccessories = false
        }
    }
}
