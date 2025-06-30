import SwiftUI

struct LocationDetailView: View {
    let location: Location
    @ObservedObject var apiClient: SnipeITAPIClient

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

    @State private var selectedTab = 0

    var body: some View {
        VStack {
            Picker("Select a tab", selection: $selectedTab) {
                Text("Users (\(usersAtLocation.count))").tag(0)
                Text("Assets (\(assetsAtLocation.count))").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            ScrollView {
                if selectedTab == 0 {
                    if !usersAtLocation.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(usersAtLocation) { user in
                                NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient)) {
                                    UserCardView(user: user)
                                }
                            }
                        }
                    } else {
                        Text("No users at this location.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                } else {
                    if !assetsAtLocation.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(assetsAtLocation) { asset in
                                NavigationLink(destination: AssetDetailView(asset: asset, apiClient: apiClient)) {
                                    AssetCardView(asset: asset)
                                }
                            }
                        }
                    } else {
                        Text("No assets at this location.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/locations/\(location.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
    }
} 
