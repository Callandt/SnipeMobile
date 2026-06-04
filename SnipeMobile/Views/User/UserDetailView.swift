import SwiftUI

struct UserDetailView: View {
    let user: User
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isDetailViewActive: Bool
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    var onOpenAccessory: ((Accessory) -> Void)? = nil
    var onOpenLocation: ((Location) -> Void)? = nil
    var onOpenLicense: ((License) -> Void)? = nil
    var onOpenConsumable: ((Consumable) -> Void)? = nil
    @State private var selectedTab = 0
    @State private var showEditSheet = false
    @State private var detailImageURL: String? = nil
    @State private var detailUser: User? = nil
    @State private var userAssets: [Asset] = []
    @State private var userAccessories: [Accessory] = []
    @State private var userLicenses: [License] = []
    @State private var userConsumables: [Consumable] = []

    private var currentUser: User {
        apiClient.users.first { $0.id == user.id } ?? user
    }

    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var displayName: String {
        if let detail = detailUser, detail.id == user.id, !detail.decodedName.isEmpty {
            return detail.decodedName
        }
        return currentUser.decodedName
    }

    private func field(_ keyPath: KeyPath<User, String?>) -> String? {
        if let detail = detailUser, detail.id == user.id, let value = cleaned(detail[keyPath: keyPath]) {
            return HTMLDecoder.decode(value)
        }
        return cleaned(currentUser[keyPath: keyPath]).map(HTMLDecoder.decode)
    }

    private var companyName: String? {
        if let detail = detailUser, detail.id == user.id, let value = cleaned(detail.company?.name) {
            return HTMLDecoder.decode(value)
        }
        return cleaned(currentUser.company?.name).map(HTMLDecoder.decode)
    }

    private var locationName: String? {
        if let detail = detailUser, detail.id == user.id, let value = cleaned(detail.location?.name) {
            return HTMLDecoder.decode(value)
        }
        return cleaned(currentUser.location?.name).map(HTMLDecoder.decode)
    }

    private var activatedState: Bool? {
        if let detail = detailUser, detail.id == user.id, let value = detail.activated {
            return value
        }
        return currentUser.activated
    }

    private var groupNames: String? {
        let source = (detailUser?.id == user.id ? detailUser : nil) ?? currentUser
        let names = source.groups
            .map { $0.decodedName }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
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
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(returnToTab != nil)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayName)
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
                Button { showEditSheet = true } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(L10n.string("edit"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/users/\(user.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            UserEditSheet(
                apiClient: apiClient,
                user: currentUser,
                isPresented: $showEditSheet,
                onSuccess: {
                    detailUser = nil
                    Task {
                        if let fullUser = await apiClient.fetchUserDetails(userId: user.id) {
                            detailUser = fullUser
                            detailImageURL = fullUser.image
                        }
                        await reloadAssignedItems()
                    }
                }
            )
        }
        .task(id: user.id) {
            DispatchQueue.main.async { isDetailViewActive = true }
            defer { isDetailViewActive = false }
            await reloadAssignedItems()
            if let fullUser = await apiClient.fetchUserDetails(userId: user.id) {
                detailUser = fullUser
                if let image = fullUser.image,
                   !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailImageURL = image
                } else {
                    detailImageURL = nil
                }
            } else {
                detailImageURL = nil
            }
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
                if let username = field(\.username) {
                    copyableDetailRow(label: L10n.string("username"), value: username)
                }
                if let jobtitle = field(\.jobtitle) {
                    copyableDetailRow(label: L10n.string("job_title"), value: jobtitle)
                }
                if let empNumber = field(\.employeeNumber) {
                    copyableDetailRow(label: L10n.string("employee_number"), value: empNumber)
                }
                if let email = field(\.email) {
                    copyableDetailRow(label: L10n.string("email"), value: email)
                }
                if let phone = field(\.phone) {
                    copyableDetailRow(label: L10n.string("phone"), value: phone)
                }
                if let companyName {
                    copyableDetailRow(label: L10n.string("company"), value: companyName)
                }
                if let locationName {
                    copyableDetailRow(label: L10n.string("location"), value: locationName)
                }
                if let activated = activatedState {
                    copyableDetailRow(
                        label: L10n.string("status"),
                        value: activated ? L10n.string("activated") : L10n.string("deactivated")
                    )
                }
                if let groupNames {
                    copyableDetailRow(label: L10n.string("groups"), value: groupNames)
                }
                if let notes = field(\.notes) {
                    copyableDetailRow(label: L10n.string("notes"), value: notes)
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

    private func reloadAssignedItems() async {
        async let assets = apiClient.fetchUserAssets(userId: user.id)
        async let accessories = apiClient.fetchUserAccessories(userId: user.id)
        async let licenses = apiClient.fetchUserLicenses(userId: user.id)
        async let consumables = apiClient.fetchUserConsumables(userId: user.id)
        userAssets = await assets
        userAccessories = await accessories
        userLicenses = await licenses
        userConsumables = await consumables
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        let isSingleToken = !value.contains(" ")
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(label).bold()
                Spacer(minLength: 8)
                Text(value)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).bold()
                Text(value)
                    .lineLimit(isSingleToken ? 1 : nil)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = value
            }) {
                Label(L10n.string("copy"), systemImage: "doc.on.doc")
            }
        }
    }
}
