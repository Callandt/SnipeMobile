import SwiftUI

struct UserDetailView: View {
    let user: User
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var isDetailViewActive: Bool
    /// User-mode read-only profile.
    var isReadOnly: Bool = false
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
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @Environment(\.dismiss) private var dismiss

    private var currentUser: User {
        // Don't overwrite `/users/me` from the users list in user mode.
        if isReadOnly {
            if let me = apiClient.currentUser, me.id == user.id { return me }
            return user
        }
        return apiClient.users.first { $0.id == user.id } ?? user
    }

    private func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var profileSource: User {
        if let detail = detailUser, detail.id == user.id { return detail }
        return currentUser
    }

    private var displayName: String {
        let name = profileSource.decodedName
        return name.isEmpty ? currentUser.decodedName : name
    }

    private var firstNameValue: String? {
        cleaned(profileSource.decodedFirstName)
    }

    private var lastNameValue: String? {
        cleaned(profileSource.decodedLastName)
    }

    /// Prefer loaded detail fields over list-row fallbacks.
    private func field(_ keyPath: KeyPath<User, String?>) -> String? {
        if let detail = detailUser, detail.id == user.id {
            return cleaned(detail[keyPath: keyPath]).map(HTMLDecoder.decode)
        }
        return cleaned(currentUser[keyPath: keyPath]).map(HTMLDecoder.decode)
    }

    private var companyName: String? {
        if let detail = detailUser, detail.id == user.id {
            return cleaned(detail.company?.name).map(HTMLDecoder.decode)
        }
        return cleaned(currentUser.company?.name).map(HTMLDecoder.decode)
    }

    private var locationName: String? {
        if let detail = detailUser, detail.id == user.id {
            return cleaned(detail.location?.name).map(HTMLDecoder.decode)
        }
        return cleaned(currentUser.location?.name).map(HTMLDecoder.decode)
    }

    private var activatedState: Bool? {
        if let detail = detailUser, detail.id == user.id {
            return detail.activated
        }
        return currentUser.activated
    }

    private var groupNames: String? {
        let source: User
        if let detail = detailUser, detail.id == user.id {
            source = detail
        } else {
            source = currentUser
        }
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
                if !isReadOnly {
                    Picker("Details", selection: $selectedTab) {
                        Text(L10n.string("details")).tag(0)
                        Text(L10n.string("history")).tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                }

                if selectedTab == 0 || isReadOnly {
                    ScrollView {
                        VStack(spacing: 12) {
                            userInfoSection

                            if !isReadOnly {
                                if !userAssets.isEmpty {
                                    assignedSection(title: L10n.string("assigned_assets")) {
                                        ForEach(userAssets) { asset in
                                            if let onOpenAsset {
                                                Button { onOpenAsset(asset) } label: {
                                                    AssignedAssetCard(asset: asset)
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                AssignedAssetCard(asset: asset)
                                            }
                                        }
                                    }
                                }

                                if !userAccessories.isEmpty {
                                    assignedSection(title: L10n.string("tab_accessories")) {
                                        ForEach(userAccessories) { accessory in
                                            if let onOpenAccessory {
                                                Button { onOpenAccessory(accessory) } label: {
                                                    AssignedAccessoryCard(accessory: accessory)
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                AssignedAccessoryCard(accessory: accessory)
                                            }
                                        }
                                    }
                                }

                                if !userLicenses.isEmpty {
                                    assignedSection(title: L10n.string("tab_licenses")) {
                                        ForEach(userLicenses) { license in
                                            if let onOpenLicense {
                                                Button { onOpenLicense(license) } label: {
                                                    AssignedLicenseCard(license: license)
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                AssignedLicenseCard(license: license)
                                            }
                                        }
                                    }
                                }

                                if !userConsumables.isEmpty {
                                    assignedSection(title: L10n.string("tab_consumables")) {
                                        ForEach(userConsumables) { consumable in
                                            if let onOpenConsumable {
                                                Button { onOpenConsumable(consumable) } label: {
                                                    AssignedConsumableCard(consumable: consumable)
                                                }
                                                .buttonStyle(.plain)
                                            } else {
                                                AssignedConsumableCard(consumable: consumable)
                                            }
                                        }
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
        .navigationTitle(isReadOnly ? L10n.string("user_mode_my_profile") : "")
        .navigationBarTitleDisplayMode(isReadOnly ? .large : .inline)
        .toolbar {
            if !isReadOnly {
                ToolbarItem(placement: .principal) {
                    Text(displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showEditSheet = true } label: {
                        Image(systemName: "pencil")
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel(L10n.string("edit"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel(L10n.string("delete"))
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
        .entityDeleteSupport(
            showConfirm: $showDeleteConfirm,
            isDeleting: $isDeleting,
            showError: $showDeleteError,
            errorMessage: $deleteErrorMessage,
            confirmTitle: L10n.string("delete_item_confirm_title", displayName),
            confirmMessage: L10n.string("delete_user_confirm_message", displayName),
            onDelete: { await deleteCurrentUser() }
        )
        .sheet(isPresented: $showEditSheet) {
            UserEditSheet(
                apiClient: apiClient,
                user: currentUser,
                isPresented: $showEditSheet,
                onSuccess: {
                    detailUser = nil
                    Task {
                        await apiClient.fetchUsers()
                        if let fullUser = await apiClient.fetchUserDetails(userId: user.id) {
                            detailUser = fullUser
                            detailImageURL = fullUser.image
                        }
                        await reloadAssignedItems()
                    }
                }
            )
        }
        .onAppear {
            if !isReadOnly {
                isDetailViewActive = true
            }
        }
        .onDisappear {
            if !isReadOnly {
                isDetailViewActive = false
            }
        }
        .hidesTabBarWhenPushed(if: !isReadOnly)
        .task(id: user.id) {
            if isReadOnly {
                // Assigned items live on My Assets.
                await apiClient.fetchCurrentUser()
                if let me = apiClient.currentUser, me.id == user.id {
                    detailUser = me
                    detailImageURL = cleaned(me.image)
                } else {
                    detailUser = user
                    detailImageURL = cleaned(user.image)
                }
            } else {
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
                    detailUser = user
                    detailImageURL = user.image
                }
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
                if let firstName = firstNameValue {
                    copyableDetailRow(label: L10n.string("first_name"), value: firstName)
                }
                if let lastName = lastNameValue {
                    copyableDetailRow(label: L10n.string("last_name"), value: lastName)
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

    private func deleteCurrentUser() async {
        isDeleting = true
        let ok = await apiClient.deleteUser(userId: user.id)
        isDeleting = false
        if ok {
            dismiss()
        } else {
            deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
            showDeleteError = true
        }
    }

    private func reloadAssignedItems() async {
        async let assets = apiClient.fetchUserAssets(userId: user.id)
        async let accessories = apiClient.fetchUserAccessories(userId: user.id)
        async let licenses = apiClient.fetchUserLicenses(userId: user.id)
        userAssets = await assets
        userAccessories = await accessories
        userLicenses = await licenses
        // No consumable catalog scan in user mode.
        if isReadOnly {
            userConsumables = []
        } else {
            userConsumables = await apiClient.fetchUserConsumables(userId: user.id)
        }
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String) -> some View {
        let isSingleToken = !value.contains(" ")
        VStack(alignment: .leading, spacing: 4) {
            Text(label).bold()
            Text(value)
                .foregroundColor(.secondary)
                .lineLimit(isSingleToken ? 1 : nil)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
