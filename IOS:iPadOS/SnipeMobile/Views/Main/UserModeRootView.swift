import SwiftUI

/// User shell: profile, assigned items, requestables.
struct UserModeRootView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @EnvironmentObject private var appSettings: AppSettings

    private enum Tab: Hashable {
        case me
        case assets
        case requests
    }

    private enum AssetsRoute: Hashable {
        case asset(Int)
        case accessory(Int)
        case license(Int)
    }

    private enum RequestRoute: Hashable {
        case asset(Int)
    }

    @State private var selectedTab: Tab = .me
    @State private var assetsPath = NavigationPath()
    @State private var requestsPath = NavigationPath()
    @State private var isDetailViewActive = false
    private var isDetailPushedOnSelectedTab: Bool {
        switch selectedTab {
        case .me: return false
        case .assets: return !assetsPath.isEmpty
        case .requests: return !requestsPath.isEmpty
        }
    }
    @State private var selectedAssetDetailTab = 0
    @State private var showingSettings = false
    @State private var isRefreshingRequests = false
    @State private var requestableAssets: [Asset] = []
    @State private var pendingRequestIds: Set<Int> = []
    @State private var actionError: String?
    @State private var showActionError = false
    @State private var assetsSearchText = ""

    private var myAssets: [Asset] {
        filteredAssets(apiClient.assets)
    }

    private var myAccessories: [Accessory] {
        let query = assetsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apiClient.accessories }
        return apiClient.accessories.filter { SearchHelpers.accessoryMatches($0, query: query) }
    }

    private var myLicenses: [License] {
        let query = assetsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apiClient.licenses }
        return apiClient.licenses.filter { SearchHelpers.licenseMatches($0, query: query) }
    }

    private var hasAnyAssignedItems: Bool {
        !apiClient.assets.isEmpty || !apiClient.accessories.isEmpty || !apiClient.licenses.isEmpty
    }

    private func filteredAssets(_ all: [Asset]) -> [Asset] {
        let query = assetsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { SearchHelpers.assetMatches($0, query: query) }
    }

    private var assignedItemsBreakdown: some View {
        HStack(spacing: 14) {
            assignedCountLabel(
                icon: "laptopcomputer",
                count: myAssets.count,
                titleKey: "tab_assets"
            )
            assignedCountLabel(
                icon: "mediastick",
                count: myAccessories.count,
                titleKey: "tab_accessories"
            )
            assignedCountLabel(
                icon: "doc.text.fill",
                count: myLicenses.count,
                titleKey: "tab_licenses"
            )
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func assignedCountLabel(icon: String, count: Int, titleKey: String) -> some View {
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text("\(count) \(L10n.string(titleKey))")
            }
            .accessibilityElement(children: .combine)
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            profileTab
                .tabItem {
                    Label(L10n.string("user_mode_my_profile"), systemImage: "person.crop.circle.fill")
                }
                .tag(Tab.me)

            myAssetsTab
                .tabItem {
                    Label(L10n.string("user_mode_my_assets"), systemImage: "laptopcomputer")
                }
                .tag(Tab.assets)

            requestsTab
                .tabItem {
                    Label(L10n.string("user_mode_requests"), systemImage: "tray.and.arrow.down.fill")
                }
                .tag(Tab.requests)
        }
        .task {
            await reloadAll(reportErrors: true)
        }
        .onChange(of: selectedTab) { _, _ in
            assetsPath = NavigationPath()
            requestsPath = NavigationPath()
        }
        .modifier(TabBarMinimizeBehaviorModifier(isDetailVisible: isDetailPushedOnSelectedTab))
        .sheet(isPresented: $showingSettings, onDismiss: {
            requestableAssets = []
            Task { await reloadAll(reportErrors: true) }
        }) {
            SettingsView(apiClient: apiClient)
                .environmentObject(appSettings)
        }
        .alert(L10n.string("error"), isPresented: $showActionError) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
        .alert(
            L10n.string("refresh_failed_title"),
            isPresented: Binding(
                get: { apiClient.refreshErrorMessage != nil && !apiClient.pendingUnauthorizedSessionWipe },
                set: { newValue in
                    if !newValue {
                        DispatchQueue.main.async { apiClient.refreshErrorMessage = nil }
                    }
                }
            )
        ) {
            Button(L10n.string("ok"), role: .cancel) { apiClient.refreshErrorMessage = nil }
        } message: {
            Text(apiClient.refreshErrorMessage ?? "")
        }
    }

    // MARK: - Profile

    private var profileTab: some View {
        NavigationStack {
            Group {
                if let user = apiClient.currentUser {
                    UserDetailView(
                        user: user,
                        apiClient: apiClient,
                        isDetailViewActive: $isDetailViewActive,
                        isReadOnly: true
                    )
                } else if apiClient.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        L10n.string("user_mode_profile_unavailable_title"),
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text(L10n.string("user_mode_profile_unavailable_desc"))
                    )
                }
            }
            .toolbar {
                settingsToolbarButton
            }
            .refreshable { await reloadAll(reportErrors: true) }
        }
    }

    // MARK: - My assets

    private var myAssetsTab: some View {
        NavigationStack(path: $assetsPath) {
            Group {
                if apiClient.isLoading && !hasAnyAssignedItems {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasAnyAssignedItems {
                    ContentUnavailableView(
                        L10n.string("user_mode_no_assets_title"),
                        systemImage: "laptopcomputer",
                        description: Text(L10n.string("user_mode_no_assets_desc"))
                    )
                } else if myAssets.isEmpty && myAccessories.isEmpty && myLicenses.isEmpty {
                    ContentUnavailableView.search(text: assetsSearchText)
                } else {
                    List {
                        // Keep counts in the list (large title).
                        Section {
                            assignedItemsBreakdown
                                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color(.systemBackground))
                        }

                        if !myAssets.isEmpty {
                            Section {
                                ForEach(myAssets) { asset in
                                    Button {
                                        assetsPath.append(AssetsRoute.asset(asset.id))
                                    } label: {
                                        AssetCardView(asset: asset)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }

                        if !myAccessories.isEmpty {
                            Section(L10n.string("tab_accessories")) {
                                ForEach(myAccessories) { accessory in
                                    Button {
                                        assetsPath.append(AssetsRoute.accessory(accessory.id))
                                    } label: {
                                        AccessoryCardView(accessory: accessory)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }

                        if !myLicenses.isEmpty {
                            Section(L10n.string("tab_licenses")) {
                                ForEach(myLicenses) { license in
                                    Button {
                                        assetsPath.append(AssetsRoute.license(license.id))
                                    } label: {
                                        LicenseCardView(license: license)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .browseListBackground()
                }
            }
            .navigationTitle(L10n.string("user_mode_my_assets"))
            .navigationBarTitleDisplayMode(.large)
            .compactLayoutWhileSearching()
            .searchable(text: $assetsSearchText, prompt: Text(L10n.string("search_assets")))
            .toolbar {
                settingsToolbarButton
            }
            .refreshable { await reloadAll(reportErrors: true) }
            .navigationDestination(for: AssetsRoute.self) { route in
                switch route {
                case .asset(let id):
                    assetDetailDestination(assetId: id, fallback: apiClient.assets)
                case .accessory(let id):
                    if let accessory = apiClient.accessories.first(where: { $0.id == id }) {
                        AccessoryDetailView(
                            accessory: accessory,
                            apiClient: apiClient,
                            selectedTab: $selectedAssetDetailTab,
                            isDetailViewActive: $isDetailViewActive
                        )
                    }
                case .license(let id):
                    if let license = apiClient.licenses.first(where: { $0.id == id }) {
                        LicenseDetailView(
                            license: license,
                            apiClient: apiClient,
                            selectedTab: $selectedAssetDetailTab,
                            isDetailViewActive: $isDetailViewActive
                        )
                    }
                }
            }
        }
        .syncTabBarWithNavigationPath(assetsPath)
    }

    // MARK: - Requests

    private var requestsTab: some View {
        NavigationStack(path: $requestsPath) {
            Group {
                if isRefreshingRequests && requestableAssets.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if requestableAssets.isEmpty {
                    ContentUnavailableView(
                        L10n.string("user_mode_no_requestable_title"),
                        systemImage: "tray",
                        description: Text(L10n.string("user_mode_no_requestable_desc"))
                    )
                } else {
                    List {
                        ForEach(requestableAssets) { asset in
                            AssetCardView(
                                asset: asset,
                                onSelect: {
                                    requestsPath.append(RequestRoute.asset(asset.id))
                                }
                            ) {
                                requestActionButton(for: asset)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .browseListBackground()
                }
            }
            .navigationTitle(L10n.string("user_mode_requests"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                settingsToolbarButton
            }
            .refreshable { await reloadRequestables(reportErrors: true) }
            .navigationDestination(for: RequestRoute.self) { route in
                switch route {
                case .asset(let id):
                    assetDetailDestination(
                        assetId: id,
                        fallback: requestableAssets + apiClient.assets
                    )
                }
            }
        }
        .syncTabBarWithNavigationPath(requestsPath)
    }

    // MARK: - Shared

    private var settingsToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .accessibilityLabel(L10n.string("settings"))
        }
    }

    @ViewBuilder
    private func assetDetailDestination(assetId: Int, fallback: [Asset]) -> some View {
        if let asset = fallback.first(where: { $0.id == assetId })
            ?? apiClient.assets.first(where: { $0.id == assetId }) {
            AssetDetailView(
                asset: asset,
                apiClient: apiClient,
                selectedTab: $selectedAssetDetailTab,
                isDetailViewActive: $isDetailViewActive,
                isReadOnly: true
            )
        } else {
            ProgressView()
                .task {
                    if let fetched = await apiClient.fetchHardwareDetails(assetId: assetId) {
                        apiClient.applyUpdatedAsset(fetched)
                    }
                }
        }
    }

    // MARK: - Helpers

    private func reloadAll(reportErrors: Bool) async {
        if reportErrors {
            apiClient.clearRefreshError()
        }
        await apiClient.fetchUserModeData(clearRefreshError: reportErrors)
        await reloadRequestables(reportErrors: reportErrors && apiClient.refreshErrorMessage == nil)
    }

    private func reloadRequestables(reportErrors: Bool = false) async {
        isRefreshingRequests = true
        defer { isRefreshingRequests = false }
        requestableAssets = await apiClient.fetchRequestableAssets(reportErrors: reportErrors)
    }

    /// Prefer cancel action when present.
    private func canCancelRequest(_ asset: Asset) -> Bool {
        asset.availableActions?.cancel == true
    }

    private func canRequestAsset(_ asset: Asset) -> Bool {
        if canCancelRequest(asset) { return false }
        // No actions payload → allow request.
        return asset.availableActions?.request != false
    }

    @ViewBuilder
    private func requestActionButton(for asset: Asset) -> some View {
        let isPending = pendingRequestIds.contains(asset.id)
        let cancelMode = canCancelRequest(asset)

        if cancelMode || canRequestAsset(asset) {
            Button {
                Task { await toggleRequest(asset) }
            } label: {
                HStack(spacing: 6) {
                    if isPending {
                        ProgressView()
                            .controlSize(.small)
                    } else if cancelMode {
                        Image(systemName: "xmark.circle")
                        Text(L10n.string("user_mode_cancel_request_action"))
                    } else {
                        Image(systemName: "tray.and.arrow.down")
                        Text(L10n.string("user_mode_request_action"))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .tint(cancelMode ? Color.orange : Color.accentColor)
            .controlSize(.regular)
            .disabled(isPending)
            .padding(.top, 4)
        }
    }

    private func toggleRequest(_ asset: Asset) async {
        pendingRequestIds.insert(asset.id)
        defer { pendingRequestIds.remove(asset.id) }

        let error: String?
        if canCancelRequest(asset) {
            error = await apiClient.cancelAssetRequest(assetId: asset.id)
        } else {
            error = await apiClient.requestAsset(assetId: asset.id)
        }

        if let error {
            actionError = error
            showActionError = true
        } else {
            await reloadRequestables(reportErrors: true)
        }
    }
}
