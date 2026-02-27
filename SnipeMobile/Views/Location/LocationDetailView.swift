import SwiftUI

struct LocationDetailView: View {
    let location: Location
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    @State private var assetDetailTab: Int = 0
    @State private var userDetailTab: Int = 0

    // Assets whose default or ready-to-deploy location is this one.
    private var assetsAtLocation: [Asset] {
        apiClient.assets.filter {
            $0.location?.id == location.id || $0.rtdLocation?.id == location.id
        }
    }

    // Users whose location is this one.
    private var usersAtLocation: [User] {
        apiClient.users.filter { $0.location?.id == location.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Select a tab", selection: $selectedTab) {
                Text("Users (\(usersAtLocation.count))").tag(0)
                Text("Assets (\(assetsAtLocation.count))").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if selectedTab == 0 {
                if usersAtLocation.isEmpty {
                    ContentUnavailableView("No users", systemImage: "person.2", description: Text("No users at this location."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 4)
                } else {
                    List {
                        Section {
                            ForEach(usersAtLocation) { user in
                                Button {
                                    onOpenUser?(user)
                                } label: {
                                    UserCardView(user: user)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                    .padding(.top, 4)
                }
            } else if selectedTab == 1 {
                if assetsAtLocation.isEmpty {
                    ContentUnavailableView("No assets", systemImage: "laptopcomputer", description: Text("No assets at this location."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 4)
                } else {
                    List {
                        Section {
                            ForEach(assetsAtLocation) { asset in
                                Button {
                                    onOpenAsset?(asset)
                                } label: {
                                    AssetCardView(asset: asset)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                    .padding(.top, 4)
                }
            }
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(returnToTab != nil)
        .toolbar {
            if let _ = returnToTab, let onBack = onBackToPrevious {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
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
} 
