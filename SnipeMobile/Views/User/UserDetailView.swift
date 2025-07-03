import SwiftUI

struct UserDetailView: View {
    let user: User
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @State private var copyNotification: String?
    @State private var showCopyNotification = false
    @StateObject private var accessoryHistoryViewModel = HistoryViewModel()
    @State private var accessoryHistory: [Activity] = []
    @State private var userActivity: [Activity] = []
    @State private var assetDetailTab: Int = 0

    private var assignedItems: [AssignedItem] {
        let assetItems = apiClient.assets.filter { $0.assignedTo?.id == user.id }.map { AssignedItem.asset($0) }
        let accessoryItems = apiClient.accessories.filter { $0.assignedTo?.id == user.id }.map { AssignedItem.accessory($0) }
        return assetItems + accessoryItems
    }

    // Accessoires waarvan de laatste actie voor deze user een checkout is, op basis van user-activity endpoint
    private var actuallyAssignedAccessories: [Accessory] {
        let isCheckout: (String) -> Bool = { action in
            let lower = action.lowercased()
            return lower.contains("check") && lower.contains("uit")
        }
        // Verzamel alle activiteiten voor accessoires
        let accessoryActivities = userActivity.filter { $0.item?.type == "accessory" && $0.item?.id != nil }
        // Groepeer per accessoire-id
        let grouped = Dictionary(grouping: accessoryActivities, by: { $0.item!.id })
        // Voor elke accessoire: pak de laatste actie
        let assignedAccessoryIds = grouped.compactMap { (accessoryId, activities) -> Int? in
            let last = activities.max(by: { ($0.createdAt?.datetime ?? "") < ($1.createdAt?.datetime ?? "") })
            if let last = last, isCheckout(last.actionType) {
                return accessoryId
            }
            return nil
        }
        // Haal de Accessory objecten op uit apiClient.accessories
        return apiClient.accessories.filter { assignedAccessoryIds.contains($0.id) }
    }

    enum AssignedItem: Identifiable {
        case asset(Asset)
        case accessory(Accessory)
        var id: Int {
            switch self {
            case .asset(let asset): return asset.id
            case .accessory(let accessory): return accessory.id + 1_000_000 // voorkom id-conflict
            }
        }
    }

    var assignedAssetsSection: some View {
        VStack(spacing: 16) {
            ForEach(assignedItems) { item in
                switch item {
                case .asset(let asset):
                    Button(action: {
                        assetDetailTab = 0
                    }) {
                        NavigationLink(destination: AssetDetailView(asset: asset, apiClient: apiClient, selectedTab: $assetDetailTab)) {
                            AssetCardView(asset: asset)
                        }
                    }
                case .accessory(let accessory):
                    NavigationLink(destination: AccessoryDetailView(accessory: accessory, apiClient: apiClient, selectedTab: .constant(0))) {
                        AccessoryCardView(accessory: accessory)
                    }
                }
            }
            ForEach(actuallyAssignedAccessories) { accessory in
                NavigationLink(destination: AccessoryDetailView(accessory: accessory, apiClient: apiClient, selectedTab: .constant(0))) {
                    AccessoryCardView(accessory: accessory)
                }
            }
        }
        .padding(.horizontal)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Picker("Details", selection: $selectedTab) {
                    Text("Details").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Copy notification overlay direct onder tabs
                if showCopyNotification, let text = copyNotification {
                    VStack {
                        Text("Copied: \(text)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(8)
                            .transition(.opacity)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        showCopyNotification = false
                                    }
                                }
                            }
                        Spacer()
                    }
                    .padding(.top, 4)
                }

                if selectedTab == 0 {
                    VStack(spacing: 20) {
                        // --- Fixed Header ---
                        VStack(spacing: 15) {
                            Text("User Info")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)

                            VStack(alignment: .leading, spacing: 15) {
                                if let empNumber = user.employeeNumber, !empNumber.isEmpty {
                                    copyableDetailRow(label: "Employee Number", value: empNumber)
                                }
                                
                                if let email = user.email, !email.isEmpty {
                                    copyableDetailRow(label: "Email", value: email)
                                }
                                
                                if let locationName = user.location?.name, !locationName.isEmpty {
                                    copyableDetailRow(label: "Location", value: locationName)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        if !assignedItems.isEmpty || !actuallyAssignedAccessories.isEmpty {
                            Text("Assigned Assets")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        // --- Scrollable Lists ---
                        ScrollView(.vertical) {
                            VStack(spacing: 30) {
                                if !assignedItems.isEmpty || !actuallyAssignedAccessories.isEmpty {
                                    assignedAssetsSection
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                    .padding(.bottom, 1) // Prevents scrollview from overlapping tab bar
                    .padding(.top)
                } else {
                    HistoryView(itemType: "user", itemId: user.id, apiClient: apiClient)
                }
            }

            // Copy notification overlay
            if showCopyNotification, let text = copyNotification {
                VStack {
                    Text("Copied: \(text)")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(8)
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    showCopyNotification = false
                                }
                            }
                        }
                    Spacer()
                }
                .padding(.top)
            }
        }
        .navigationTitle(HTMLDecoder.decode(user.decodedName))
        .navigationBarTitleDisplayMode(.inline)
        .padding(.top, 8)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/users/\(user.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear {
            selectedTab = 0
            accessoryHistoryViewModel.fetchHistory(itemType: "accessory", itemId: 0, apiClient: apiClient)
            Task {
                self.accessoryHistory = await apiClient.fetchActivityReport()
            }
            Task {
                // Haal user-activity op
                self.userActivity = await apiClient.fetchActivityForItem(itemType: "user", itemId: user.id)
            }
        }
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label + ":")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(HTMLDecoder.decode(value))
                    .font(.body)
                    .foregroundColor(.primary)
            }

            Spacer()
            
            Button(action: {
                UIPasteboard.general.string = value
                withAnimation {
                    copyNotification = label
                    showCopyNotification = true
                }
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.blue)
                    .padding(.leading)
            }
        }
    }
} 
