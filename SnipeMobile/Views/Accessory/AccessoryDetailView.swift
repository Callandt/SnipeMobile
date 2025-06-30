import SwiftUI

struct AccessoryDetailView: View {
    let accessory: Accessory
    @ObservedObject var apiClient: SnipeITAPIClient
    @State private var assignedUsers: [User] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // --- Accessory Info ---
                VStack(alignment: .center, spacing: 10) {
                    Text(accessory.decodedName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let manufacturerName = accessory.manufacturer?.name, !manufacturerName.isEmpty {
                        Text("by \(manufacturerName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)

                VStack(alignment: .leading, spacing: 15) {
                    if let categoryName = accessory.category?.name, !categoryName.isEmpty {
                        detailRow(label: "Category", value: categoryName)
                    }
                    if let statusName = accessory.statusLabel?.name, !statusName.isEmpty {
                        detailRow(label: "Status", value: statusName)
                    }
                    if let locationName = accessory.location?.name, !locationName.isEmpty {
                        detailRow(label: "Location", value: locationName)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                // --- Assigned Users List ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("Assigned To")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if assignedUsers.isEmpty {
                        Text("Not assigned to any user.")
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        ForEach(assignedUsers) { user in
                            NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient)) {
                                UserCardView(user: user)
                            }
                        }
                    }
                }
                Spacer()
            }
        }
        .navigationTitle("Accessory Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                assignedUsers = await apiClient.fetchUsersForAccessory(accessoryId: accessory.id)
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).bold()
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
} 