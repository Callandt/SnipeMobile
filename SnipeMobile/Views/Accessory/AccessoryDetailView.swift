import SwiftUI

struct AccessoryDetailView: View {
    let accessory: Accessory
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @State private var assignedUsers: [User] = []
    @State private var isLoading = true
    @StateObject private var historyViewModel = HistoryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Details", selection: $selectedTab) {
                Text("Details").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            if selectedTab == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Accessory Info")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        VStack(alignment: .leading, spacing: 15) {
                            if let categoryName = accessory.category?.name, !categoryName.isEmpty {
                                detailRow(label: "Category", value: categoryName)
                            }
                            if let manufacturerName = accessory.manufacturer?.name, !manufacturerName.isEmpty {
                                detailRow(label: "Manufacturer", value: manufacturerName)
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
                        assignedUsersSection
                        Spacer()
                    }
                    .padding(.top)
                }
            } else {
                HistoryView(itemType: "accessory", itemId: accessory.id, apiClient: apiClient)
            }
        }
        .navigationTitle(accessory.decodedName)
        .navigationBarTitleDisplayMode(.inline)
        .padding(.top, 8)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/accessories/\(accessory.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear {
            historyViewModel.fetchHistory(itemType: "accessory", itemId: accessory.id, apiClient: apiClient)
            if apiClient.users.isEmpty {
                Task {
                    await apiClient.fetchUsers()
                }
            }
        }
        .onChange(of: accessory.id) {
            if apiClient.users.isEmpty {
                Task {
                    await apiClient.fetchUsers()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button(action: {}) {
                    Text("Edit")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button(action: {}) {
                    Text(accessory.statusLabel?.name.lowercased() == "deployed" ? "Check In" : "Check Out")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background((accessory.statusLabel?.name.lowercased() == "deployed") ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
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

    var currentlyAssignedUsers: [User] {
        // Helper closure om actie te herkennen
        let isCheckout: (String) -> Bool = { action in
            let lower = action.lowercased()
            return lower.contains("check") && lower.contains("uit")
        }
        // Zoek per user de laatste actie (checkout of checkin)
        var userLastAction: [Int: Activity] = [:]
        for activity in historyViewModel.history {
            if let userId = activity.target?.id, activity.target?.type == "user" {
                print("DEBUG: Activity for userId=\(userId), action=\(activity.actionType), date=\(activity.createdAt?.datetime ?? "")")
                if let prev = userLastAction[userId] {
                    if let prevDate = prev.createdAt?.datetime, let newDate = activity.createdAt?.datetime, newDate > prevDate {
                        userLastAction[userId] = activity
                    }
                } else {
                    userLastAction[userId] = activity
                }
            }
        }
        // Gebruikers waarvan de laatste actie een checkout is
        let assignedUserIds = userLastAction.filter { isCheckout($0.value.actionType) }.map { $0.key }
        print("DEBUG: assignedUserIds=\(assignedUserIds)")
        // Filter alle checkout-acties
        let checkouts = historyViewModel.history.filter { activity in
            activity.target?.type == "user" && isCheckout(activity.actionType)
        }
        // Haal de User objecten op uit de checkout-acties via apiClient.users
        let users = checkouts.compactMap { activity in
            if let userId = activity.target?.id {
                let user = apiClient.users.first(where: { $0.id == userId })
                if user != nil { print("DEBUG: Found user for userId=\(userId): \(user!.name)") }
                return user
            }
            return nil
        }
        // Filter op id's die nog assigned zijn
        let result = users.filter { assignedUserIds.contains($0.id) }
        print("DEBUG: Final assigned users: \(result.map { $0.name })")
        return result
    }

    var assignedUsersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assigned To")
                .font(.headline)
                .padding(.horizontal)
            if historyViewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if currentlyAssignedUsers.isEmpty {
                Text("Not assigned to any user.")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(currentlyAssignedUsers) { user in
                    NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient, selectedTab: .constant(0))) {
                        UserCardView(user: user)
                    }
                }
            }
        }
    }
} 
