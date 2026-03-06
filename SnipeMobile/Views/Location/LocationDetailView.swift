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
    @State private var assetDetailTab: Int = 0
    @State private var userDetailTab: Int = 0

    // Assets at this location.
    private var assetsAtLocation: [Asset] {
        apiClient.assets.filter {
            $0.location?.id == location.id || $0.rtdLocation?.id == location.id
        }
    }

    // Users at this location.
    private var usersAtLocation: [User] {
        apiClient.users.filter { $0.location?.id == location.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Select a tab", selection: $selectedTab) {
                Text(L10n.string("users_count", usersAtLocation.count)).tag(0)
                Text(L10n.string("assets_count", assetsAtLocation.count)).tag(1)
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
                    List {
                        Section {
                            ForEach(usersAtLocation) { user in
                                Button { onOpenUser?(user) } label: {
                                    assignedToStyleUserRow(user: user)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                    .contentMargins(.top, 16, for: .scrollContent)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                }
            } else if selectedTab == 1 {
                if assetsAtLocation.isEmpty {
                    ContentUnavailableView(L10n.string("no_assets"), systemImage: "laptopcomputer", description: Text(L10n.string("no_assets_location")))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 16)
                } else {
                    List {
                        Section {
                            ForEach(assetsAtLocation) { asset in
                                Button { onOpenAsset?(asset) } label: {
                                    assignedToStyleAssetRow(asset: asset)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                    .contentMargins(.top, 16, for: .scrollContent)
                    .scrollContentBackground(.hidden)
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
                Text(HTMLDecoder.decode(location.name))
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
        }
    }

    /// Gray row. Icon + name. No chevron.
    private func assignedToStyleUserRow(user: User) -> some View {
        HStack {
            Image(systemName: "person.circle")
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(HTMLDecoder.decode(user.decodedName))
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !user.decodedEmail.isEmpty {
                    Text(HTMLDecoder.decode(user.decodedEmail))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !user.decodedLocationName.isEmpty {
                    Text(HTMLDecoder.decode(user.decodedLocationName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func assignedToStyleAssetRow(asset: Asset) -> some View {
        HStack {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(asset.decodedAssetTag)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
} 
