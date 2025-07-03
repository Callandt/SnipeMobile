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
                            ForEach(Array(accessoryInfoRows().enumerated()), id: \ .offset) { _, row in
                                row
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        if accessory.qty != nil || accessory.minAmt != nil || accessory.remaining != nil || accessory.checkoutsCount != nil {
                            Text("Stock & Usage")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            VStack(alignment: .leading, spacing: 10) {
                                if let qty = accessory.qty {
                                    HStack { Text("Total Quantity").foregroundColor(.secondary); Spacer(); Text("\(qty)").bold() }
                                }
                                if let minAmt = accessory.minAmt {
                                    HStack { Text("Minimum Amount").foregroundColor(.secondary); Spacer(); Text("\(minAmt)").bold() }
                                }
                                if let remaining = accessory.remaining {
                                    HStack { Text("Remaining").foregroundColor(.secondary); Spacer(); Text("\(remaining)").bold() }
                                }
                                if let checkouts = accessory.checkoutsCount {
                                    HStack { Text("Checkouts Count").foregroundColor(.secondary); Spacer(); Text("\(checkouts)").bold() }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // --- Assigned Users List ---
                        assignedUsersSection
                        Spacer()
                    }
                    .padding(.top)
                }
            } else {
                HistoryView(itemType: "accessory", itemId: accessory.id, apiClient: apiClient)
            }
            Spacer(minLength: 0)
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
                    Text((accessory.statusLabel?.statusMeta?.lowercased() == "deployed") ? "Check In" : "Check Out")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background((accessory.statusLabel?.statusMeta?.lowercased() == "deployed") ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color.white.ignoresSafeArea(edges: .bottom))
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
            print("DEBUG assignedTo accessory:", String(describing: accessory.assignedTo))
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
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).bold()
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func accessoryInfoRows() -> [AnyView] {
        var rows: [AnyView] = []
        if !accessory.decodedName.isEmpty {
            rows.append(AnyView(detailRow(label: "Name", value: accessory.decodedName)))
        }
        if !accessory.decodedAssetTag.isEmpty {
            rows.append(AnyView(detailRow(label: "Asset Tag", value: accessory.decodedAssetTag)))
        }
        if let status = accessory.statusLabel?.statusMeta, !status.isEmpty {
            rows.append(AnyView(detailRow(label: "Status", value: status)))
        }
        if !accessory.decodedAssignedToName.isEmpty {
            rows.append(AnyView(detailRow(label: "Assigned To", value: accessory.decodedAssignedToName)))
        }
        if !accessory.decodedLocationName.isEmpty {
            rows.append(AnyView(detailRow(label: "Location", value: accessory.decodedLocationName)))
        }
        if !accessory.decodedManufacturerName.isEmpty {
            rows.append(AnyView(detailRow(label: "Manufacturer", value: accessory.decodedManufacturerName)))
        }
        if !accessory.decodedCategoryName.isEmpty {
            rows.append(AnyView(detailRow(label: "Category", value: accessory.decodedCategoryName)))
        }
        return rows
    }

    var currentlyAssignedUsers: [User] {
        let isCheckout: (String) -> Bool = { action in
            let lower = action.lowercased()
            return (lower.contains("check") && (lower.contains("out") || lower.contains("uit")))
        }
        print("DEBUG: --- HISTORY ---")
        for activity in historyViewModel.history {
            print("DEBUG: activity actionType=\(activity.actionType), targetType=\(activity.target?.type ?? "nil"), targetId=\(activity.target?.id ?? -1), targetName=\(activity.target?.name ?? "nil")")
        }
        var userLastAction: [Int: (Activity, String?)] = [:] // (activity, datetime)
        for activity in historyViewModel.history {
            if let userId = activity.target?.id, activity.target?.type == "user" {
                let newDate = activity.createdAt?.datetime
                if let (_, prevDate) = userLastAction[userId] {
                    if let prevDate = prevDate, let newDate = newDate, newDate > prevDate {
                        userLastAction[userId] = (activity, newDate)
                    }
                } else {
                    userLastAction[userId] = (activity, newDate)
                }
            }
        }
        let assignedUserIdsWithDate = userLastAction.compactMap { (userId, tuple) -> (Int, String?)? in
            isCheckout(tuple.0.actionType) ? (userId, tuple.1) : nil
        }
        let sortedUserIds = assignedUserIdsWithDate.sorted { ($0.1 ?? "") > ($1.1 ?? "") }.map { $0.0 }
        print("DEBUG: sorted assignedUserIds=", sortedUserIds)
        let users = sortedUserIds.compactMap { userId in
            apiClient.users.first(where: { $0.id == userId })
        }
        print("DEBUG: assigned users=", users.map { $0.name })
        return users
    }

    var currentlyAssignedLocations: [Location] {
        let isCheckout: (String) -> Bool = { action in
            let lower = action.lowercased()
            return (lower.contains("check") && (lower.contains("out") || lower.contains("uit")))
        }
        var locationLastAction: [Int: Activity] = [:]
        for activity in historyViewModel.history {
            if let locationId = activity.target?.id, activity.target?.type == "location" {
                if let prev = locationLastAction[locationId] {
                    if let prevDate = prev.createdAt?.datetime, let newDate = activity.createdAt?.datetime, newDate > prevDate {
                        locationLastAction[locationId] = activity
                    }
                } else {
                    locationLastAction[locationId] = activity
                }
            }
        }
        let assignedLocationIds = locationLastAction.compactMap { (locationId, activity) in
            isCheckout(activity.actionType) ? locationId : nil
        }
        print("DEBUG: assignedLocationIds=", assignedLocationIds)
        let locations = assignedLocationIds.compactMap { locationId in
            apiClient.locations.first(where: { $0.id == locationId })
        }
        print("DEBUG: assigned locations=", locations.map { $0.name })
        return locations
    }

    var assignedUsersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !currentlyAssignedUsers.isEmpty {
                Text("Assigned To")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                ForEach(currentlyAssignedUsers) { user in
                    NavigationLink(destination: UserDetailView(user: user, apiClient: apiClient, selectedTab: .constant(0))) {
                        UserCardView(user: user)
                    }
                }
            }
            if !currentlyAssignedLocations.isEmpty {
                Text("Assigned Location")
                    .font(.headline)
                    .padding(.horizontal)
                ForEach(currentlyAssignedLocations) { location in
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.gray)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading) {
                            Text(location.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                }
            }
            if currentlyAssignedUsers.isEmpty && currentlyAssignedLocations.isEmpty {
                if let fallback = accessory.assignedTo, (fallback.name != "" || fallback.email != nil) {
                    Text("Assigned To")
                        .font(.headline)
                        .padding(.horizontal)
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundColor(.gray)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading) {
                            Text(fallback.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            if let email = fallback.email, !email.isEmpty {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                } else {
                    Text("Not assigned to any user or location.")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
        }
    }
} 

