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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text(location.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 5)

                // --- USERS Section ---
                if !usersAtLocation.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Users at this Location")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(usersAtLocation) { user in
                            NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient)) {
                                UserCardView(user: user)
                            }
                        }
                    }
                }

                // --- ASSETS Section ---
                if !assetsAtLocation.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Assets at this Location")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(assetsAtLocation) { asset in
                            NavigationLink(destination: AssetDetailView(asset: asset, apiClient: apiClient)) {
                                AssetCardView(asset: asset)
                            }
                        }
                    }
                }
                
                if usersAtLocation.isEmpty && assetsAtLocation.isEmpty {
                    Text("No users or assets at this location.")
                        .foregroundColor(.secondary)
                        .padding()
                }

                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
    }
} 