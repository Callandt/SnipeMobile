import SwiftUI

struct UserDetailView: View {
    let user: User
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    var onOpenAccessory: ((Accessory) -> Void)? = nil
    var onOpenLocation: ((Location) -> Void)? = nil
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

    // Accessories last checked out to this user
    private var actuallyAssignedAccessories: [Accessory] {
        let isCheckout: (String) -> Bool = { action in
            let lower = action.lowercased()
            return lower.contains("check") && lower.contains("uit")
        }
        // All accessory activities
        let accessoryActivities = userActivity.filter { $0.item?.type == "accessory" && $0.item?.id != nil }
        // By accessory id
        let grouped = Dictionary(grouping: accessoryActivities, by: { $0.item!.id })
        // Latest action per accessory
        let assignedAccessoryIds = grouped.compactMap { (accessoryId, activities) -> Int? in
            let last = activities.max(by: { ($0.createdAt?.datetime ?? "") < ($1.createdAt?.datetime ?? "") })
            if let last = last, isCheckout(last.actionType) {
                return accessoryId
            }
            return nil
        }
        return apiClient.accessories.filter { assignedAccessoryIds.contains($0.id) }
    }

    enum AssignedItem: Identifiable {
        case asset(Asset)
        case accessory(Accessory)
        var id: Int {
            switch self {
            case .asset(let asset): return asset.id
            case .accessory(let accessory): return accessory.id + 1_000_000 // no clash with asset ids
            }
        }
    }

    var assignedAssetsSection: some View {
        List {
            Section {
                ForEach(assignedItems) { item in
                    switch item {
                    case .asset(let asset):
                        Button { onOpenAsset?(asset) } label: {
                            assignedToStyleAssetRow(asset: asset)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                    case .accessory(let accessory):
                        Button { onOpenAccessory?(accessory) } label: {
                            assignedToStyleAccessoryRow(accessory: accessory)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
                ForEach(actuallyAssignedAccessories) { accessory in
                    Button { onOpenAccessory?(accessory) } label: {
                        assignedToStyleAccessoryRow(accessory: accessory)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .listSectionSeparator(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
    }

    /// Gray row. Icon + name.
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

    private func assignedToStyleAccessoryRow(accessory: Accessory) -> some View {
        HStack {
            Image(systemName: "cube.box")
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessory.decodedName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !accessory.decodedCategoryName.isEmpty {
                    Text(accessory.decodedCategoryName)
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

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Picker("Details", selection: $selectedTab) {
                    Text(L10n.string("details")).tag(0)
                    Text(L10n.string("history")).tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 2)

                // Copy toast under tabs
                if showCopyNotification, let text = copyNotification {
                    VStack {
                        Text(L10n.string("copied", text))
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
                    VStack(spacing: 12) {
                        // Fixed header
                        VStack(spacing: 12) {
                            Text(L10n.string("user_info"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 2)

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
                            VStack(alignment: .leading, spacing: 15) {
                                Text(L10n.string("assigned_assets"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                assignedAssetsSection
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 1) // Prevents scrollview from overlapping tab bar
                    .padding(.top, 16)
                    .background(Color(.systemBackground))
                } else {
                    HistoryView(itemType: "user", itemId: user.id, apiClient: apiClient)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Copy notification overlay
            if showCopyNotification, let text = copyNotification {
                VStack {
                    Text(L10n.string("copied", text))
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
                .padding(.top, 8)
            }
        }
        .onAppear { isDetailViewActive = true }
        .onDisappear { isDetailViewActive = false }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(returnToTab != nil)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(HTMLDecoder.decode(user.decodedName))
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
