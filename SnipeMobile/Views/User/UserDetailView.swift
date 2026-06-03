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
    var onOpenLicense: ((License) -> Void)? = nil
    var onOpenConsumable: ((Consumable) -> Void)? = nil
    @State private var copyNotification: String?
    @State private var showCopyNotification = false
    @State private var detailImageURL: String? = nil
    @State private var userAssets: [Asset] = []
    @State private var userAccessories: [Accessory] = []
    @State private var userLicenses: [License] = []
    @State private var userConsumables: [Consumable] = []

    private var currentUser: User {
        apiClient.users.first { $0.id == user.id } ?? user
    }

    private var resolvedImageURL: URL? {
        let rawValue = (detailImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? detailImageURL!
            : (currentUser.image?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        guard !rawValue.isEmpty else { return nil }

        if let absolute = URL(string: rawValue), absolute.scheme != nil {
            return absolute
        }
        if rawValue.hasPrefix("/") {
            return URL(string: "\(apiClient.baseURL)\(rawValue)")
        }
        return nil
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
                    ScrollView {
                        VStack(spacing: 12) {
                            userInfoSection

                            if !userAssets.isEmpty {
                                assignedSection(title: L10n.string("assigned_assets")) {
                                    ForEach(userAssets) { asset in
                                        Button { onOpenAsset?(asset) } label: {
                                            AssignedAssetCard(asset: asset)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !userAccessories.isEmpty {
                                assignedSection(title: L10n.string("tab_accessories")) {
                                    ForEach(userAccessories) { accessory in
                                        Button { onOpenAccessory?(accessory) } label: {
                                            AssignedAccessoryCard(accessory: accessory)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !userLicenses.isEmpty {
                                assignedSection(title: L10n.string("tab_licenses")) {
                                    ForEach(userLicenses) { license in
                                        Button { onOpenLicense?(license) } label: {
                                            AssignedLicenseCard(license: license)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !userConsumables.isEmpty {
                                assignedSection(title: L10n.string("tab_consumables")) {
                                    ForEach(userConsumables) { consumable in
                                        Button { onOpenConsumable?(consumable) } label: {
                                            AssignedConsumableCard(consumable: consumable)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 16)
                        .padding(.top, 16)
                    }
                    .background(Color(.systemBackground))
                } else {
                    HistoryView(itemType: "user", itemId: user.id, apiClient: apiClient)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
            reloadAssignedItems()
            Task {
                if let fullUser = await apiClient.fetchUserDetails(userId: user.id),
                   let image = fullUser.image,
                   !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailImageURL = image
                } else {
                    detailImageURL = nil
                }
            }
        }
        .onChange(of: user.id) { _, _ in
            reloadAssignedItems()
        }
    }

    private var userInfoSection: some View {
        VStack(spacing: 12) {
            if let imageURL = resolvedImageURL {
                VStack(spacing: 10) {
                    Text(L10n.string("image"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        case .failure(_):
                            Image(systemName: "photo")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 140)
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 140)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

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
    }

    private func assignedSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(spacing: 12) {
                content()
            }
        }
        .padding(.horizontal)
    }

    private func reloadAssignedItems() {
        Task {
            async let assets = apiClient.fetchUserAssets(userId: user.id)
            async let accessories = apiClient.fetchUserAccessories(userId: user.id)
            async let licenses = apiClient.fetchUserLicenses(userId: user.id)
            async let consumables = apiClient.fetchUserConsumables(userId: user.id)
            userAssets = mergeCached(await assets, from: apiClient.assets, id: \.id)
            userAccessories = mergeCached(await accessories, from: apiClient.accessories, id: \.id)
            userLicenses = mergeCached(await licenses, from: apiClient.licenses, id: \.id)
            userConsumables = mergeCached(await consumables, from: apiClient.consumables, id: \.id)
        }
    }

    private func mergeCached<T>(_ items: [T], from cache: [T], id: KeyPath<T, Int>) -> [T] {
        items.map { item in
            let itemId = item[keyPath: id]
            return cache.first(where: { $0[keyPath: id] == itemId }) ?? item
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
