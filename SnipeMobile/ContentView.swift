import SwiftUI
import AVFoundation
import CodeScanner

// MARK: - Tab
enum MainTab: String, CaseIterable {
    case hardware = "Hardware"
    case accessories = "Accessories"
    case users = "Users"
    case locations = "Locations"

    var localizedTitle: String {
        switch self {
        case .hardware: return L10n.string("tab_hardware")
        case .accessories: return L10n.string("tab_accessories")
        case .users: return L10n.string("tab_users")
        case .locations: return L10n.string("tab_locations")
        }
    }

    var icon: String {
        switch self {
        case .hardware: return "laptopcomputer"
        case .accessories: return "mediastick"
        case .users: return "person.2"
        case .locations: return "mappin.and.ellipse"
        }
    }
}

struct ContentView: View {
    @StateObject private var apiClient = SnipeITAPIClient()
    @State private var selectedTab: MainTab = .hardware
    @State private var showingScanner = false
    @State private var scannedAssetId: Int?
    @State private var searchText: String = ""
    @State private var isRefreshing: Bool = false
    @State private var hasLoadedInitialAssets: Bool = false
    @State private var assetDetailTab: Int = 0
    @State private var userDetailTab: Int = 0
    @State private var locationDetailTab: Int = 0
    @State private var accessoryDetailTab: Int = 0
    @EnvironmentObject var appSettings: AppSettings
    @State private var showingSettings = false
    @State private var showingAddAsset = false
    @State private var showingAddAccessory = false
    @State private var pendingUserToOpen: User?
    @State private var pendingAssetToOpen: Asset?
    @State private var pendingLocationToOpen: Location?
    @State private var pendingAccessoryToOpen: Accessory?
    @State private var returnToTab: MainTab?
    @State private var hardwarePath = NavigationPath()
    @State private var usersPath = NavigationPath()
    @State private var locationsPath = NavigationPath()
    @State private var accessoriesPath = NavigationPath()
    /// True wanneer een detailview op de stack staat; tabbar blijft dan volledig zichtbaar.
    @State private var isDetailViewActive = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HardwareTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                hasLoadedInitialAssets: $hasLoadedInitialAssets,
                assetDetailTab: $assetDetailTab,
                scannedAssetId: $scannedAssetId,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                showingAddAsset: $showingAddAsset,
                navigationPath: $hardwarePath,
                isDetailViewActive: $isDetailViewActive,
                pendingAssetToOpen: $pendingAssetToOpen,
                returnToTab: $returnToTab,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; hardwarePath = NavigationPath() } },
                onOpenUser: { u in pendingUserToOpen = u; usersPath.append(u); selectedTab = .users; returnToTab = .hardware },
                onOpenLocation: { pendingLocationToOpen = $0; selectedTab = .locations; returnToTab = .hardware }
            )
            .tag(MainTab.hardware)
            .tabItem { Label(MainTab.hardware.localizedTitle, systemImage: MainTab.hardware.icon) }

            AccessoriesTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                accessoryDetailTab: $accessoryDetailTab,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                showingAddAccessory: $showingAddAccessory,
                navigationPath: $accessoriesPath,
                isDetailViewActive: $isDetailViewActive,
                pendingAccessoryToOpen: $pendingAccessoryToOpen,
                returnToTab: $returnToTab,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; accessoriesPath = NavigationPath() } },
                onOpenUser: { u in pendingUserToOpen = u; usersPath.append(u); selectedTab = .users; returnToTab = .accessories },
                onOpenAsset: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .accessories },
                onOpenLocation: { pendingLocationToOpen = $0; selectedTab = .locations; returnToTab = .accessories }
            )
            .tag(MainTab.accessories)
            .tabItem { Label(MainTab.accessories.localizedTitle, systemImage: MainTab.accessories.icon) }

            UsersTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                userDetailTab: $userDetailTab,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                showingAddAsset: $showingAddAsset,
                navigationPath: $usersPath,
                isDetailViewActive: $isDetailViewActive,
                pendingUserToOpen: $pendingUserToOpen,
                returnToTab: $returnToTab,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; usersPath = NavigationPath() } },
                onOpenAsset: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .users },
                onOpenAccessory: { pendingAccessoryToOpen = $0; selectedTab = .accessories; returnToTab = .users },
                onOpenLocation: { pendingLocationToOpen = $0; selectedTab = .locations; returnToTab = .users }
            )
            .tag(MainTab.users)
            .tabItem { Label(MainTab.users.localizedTitle, systemImage: MainTab.users.icon) }

            LocationsTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                locationDetailTab: $locationDetailTab,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                showingAddAsset: $showingAddAsset,
                navigationPath: $locationsPath,
                isDetailViewActive: $isDetailViewActive,
                pendingLocationToOpen: $pendingLocationToOpen,
                returnToTab: $returnToTab,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; locationsPath = NavigationPath() } },
                onOpenUser: { u in pendingUserToOpen = u; usersPath.append(u); selectedTab = .users; returnToTab = .locations },
                onOpenAsset: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .locations }
            )
            .tag(MainTab.locations)
            .tabItem { Label(MainTab.locations.localizedTitle, systemImage: MainTab.locations.icon) }
        }
        #if os(iOS)
        .tabViewStyle(.automatic)
        #endif
        .onChange(of: selectedTab) { _, newTab in
            // Zoeken resetten bij tabwissel
            searchText = ""
            // Tabbar-state resetten; zichtbare view (lijst of detail) zet correcte waarde
            isDetailViewActive = false
            // Alleen naar de lijst terugkeren als de gebruiker zelf op een tab tikt
            // (returnToTab == nil). Bij programmatische navigatie tussen tabs
            // (bijv. vanuit een detail naar een andere tab) laten we de path met
            // de geopende detail-view intact.
            guard returnToTab == nil else { return }
            switch newTab {
            case .hardware: hardwarePath = NavigationPath()
            case .accessories: accessoriesPath = NavigationPath()
            case .users: usersPath = NavigationPath()
            case .locations: locationsPath = NavigationPath()
            }
        }
        .modifier(TabBarMinimizeBehaviorModifier(isDetailVisible: isDetailViewActive))
        .sheet(isPresented: $showingScanner, onDismiss: {
            selectedTab = .hardware
        }) {
            CodeScannerView(codeTypes: [.qr], completion: handleScanResult)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(apiClient: apiClient)
                .preferredColorScheme(
                    appSettings.appTheme == "light" ? .light :
                    appSettings.appTheme == "dark" ? .dark : nil
                )
        }
        .sheet(isPresented: $showingAddAsset) {
            AddAssetSheet(apiClient: apiClient, isPresented: $showingAddAsset)
        }
        .sheet(isPresented: $showingAddAccessory) {
            AddAccessorySheet(apiClient: apiClient, isPresented: $showingAddAccessory)
        }
        .onAppear {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if !granted {
                        apiClient.errorMessage = "Camera access is required for QR scanning."
                    }
                }
            }
            if apiClient.isConfigured && !hasLoadedInitialAssets {
                Task {
                    await apiClient.fetchPrimaryThenBackground()
                    hasLoadedInitialAssets = true
                }
            }
        }
    }

    private func handleScanResult(_ result: Result<ScanResult, ScanError>) {
        showingScanner = false
        switch result {
        case .success(let scanResult):
            if let url = URL(string: scanResult.string), let id = extractAssetId(from: url) {
                apiClient.errorMessage = nil
                if let asset = apiClient.assets.first(where: { $0.id == id }) {
                    scannedAssetId = asset.id
                    selectedTab = .hardware
                } else if apiClient.assets.isEmpty {
                    scannedAssetId = id
                    selectedTab = .hardware
                    Task { await apiClient.fetchPrimaryThenBackground() }
                } else {
                    scannedAssetId = nil
                    apiClient.errorMessage = "Asset with ID \(id) not found."
                }
            } else {
                apiClient.errorMessage = "Invalid QR code: no valid asset ID"
            }
        case .failure(let error):
            apiClient.errorMessage = "Scan failed: \(error.localizedDescription)"
        }
    }

    private func extractAssetId(from url: URL) -> Int? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let path = components.path.components(separatedBy: "/").last,
           let id = Int(path) {
            return id
        }
        return nil
    }
}

// MARK: - Hardware Tab
struct HardwareTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var hasLoadedInitialAssets: Bool
    @Binding var assetDetailTab: Int
    @Binding var scannedAssetId: Int?
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var showingAddAsset: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingAssetToOpen: Asset?
    @Binding var returnToTab: MainTab?
    var onBackToPreviousTab: () -> Void
    var onOpenUser: (User) -> Void
    var onOpenLocation: (Location) -> Void

    var filteredAssets: [Asset] {
        if searchText.isEmpty { return apiClient.assets }
        return apiClient.assets.filter {
            $0.decodedName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedModelName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedAssetTag.lowercased().contains(searchText.lowercased()) ||
            $0.decodedLocationName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedAssignedToName.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !apiClient.isConfigured {
                    ContentUnavailableView(
                        L10n.string("no_data_yet"),
                        systemImage: "link.badge.plus",
                        description: Text(L10n.string("configure_api"))
                    )
                } else if apiClient.isLoading && !isRefreshing {
                    ProgressView(L10n.string("loading_assets"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = apiClient.errorMessage {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    List {
                        Section {
                            HStack {
                                Label("\(apiClient.assets.count)", systemImage: "laptopcomputer")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(L10n.string("assigned_count", apiClient.assets.filter { $0.assignedTo != nil }.count))
                                    .foregroundStyle(.secondary)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }

                        Section {
                            ForEach(filteredAssets) { asset in
                                Button {
                                    navigationPath.append(asset)
                                } label: {
                                    AssetCardView(asset: asset)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                }
            }
            .onAppear { isDetailViewActive = false }
            .navigationTitle(MainTab.hardware.localizedTitle)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAddAsset = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(L10n.string("add_asset"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(L10n.string("scan_qr"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.string("search_assets"))
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    await apiClient.fetchPrimaryThenBackground()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: Asset.self) { asset in
                AssetDetailView(asset: asset, apiClient: apiClient, selectedTab: $assetDetailTab, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenUser: onOpenUser, onOpenLocation: onOpenLocation)
            }
        }
        .onAppear {
            if apiClient.isConfigured && apiClient.assets.isEmpty && !hasLoadedInitialAssets {
                Task {
                    await apiClient.fetchPrimaryThenBackground()
                    hasLoadedInitialAssets = true
                }
            }
            tryPushScannedAsset()
            tryPushPendingAsset()
        }
        .onChange(of: scannedAssetId) { _, _ in
            tryPushScannedAsset()
        }
        .onChange(of: pendingAssetToOpen) { _, _ in
            tryPushPendingAsset()
        }
        .onChange(of: apiClient.assets) { _, _ in
            tryPushScannedAsset()
            tryPushPendingAsset()
        }
    }

    private func tryPushPendingAsset() {
        guard let asset = pendingAssetToOpen else { return }
        navigationPath.append(asset)
        pendingAssetToOpen = nil
    }

    private func tryPushScannedAsset() {
        guard let id = scannedAssetId, let asset = apiClient.assets.first(where: { $0.id == id }) else { return }
        navigationPath.append(asset)
        scannedAssetId = nil
    }
}

// MARK: - Accessories Tab
struct AccessoriesTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var accessoryDetailTab: Int
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var showingAddAccessory: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingAccessoryToOpen: Accessory?
    @Binding var returnToTab: MainTab?
    var onBackToPreviousTab: () -> Void
    var onOpenUser: (User) -> Void
    var onOpenAsset: (Asset) -> Void
    var onOpenLocation: (Location) -> Void

    var filteredAccessories: [Accessory] {
        if searchText.isEmpty { return apiClient.accessories }
        return apiClient.accessories.filter {
            $0.decodedName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedAssetTag.lowercased().contains(searchText.lowercased()) ||
            $0.decodedLocationName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedAssignedToName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedManufacturerName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedCategoryName.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !apiClient.isConfigured {
                    ContentUnavailableView(
                        L10n.string("no_data_yet"),
                        systemImage: "link.badge.plus",
                        description: Text(L10n.string("configure_api_short"))
                    )
                } else if apiClient.isLoading && !isRefreshing {
                    ProgressView(L10n.string("loading_accessories"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = apiClient.errorMessage {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    List {
                        Section {
                            HStack {
                                Label("\(apiClient.accessories.count)", systemImage: "mediastick")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }

                        Section {
                            ForEach(filteredAccessories) { accessory in
                                Button {
                                    navigationPath.append(accessory)
                                } label: {
                                    AccessoryCardView(accessory: accessory)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                }
            }
            .onAppear { isDetailViewActive = false }
            .navigationTitle(MainTab.accessories.localizedTitle)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingAddAccessory = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(L10n.string("add_accessory"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(L10n.string("scan_qr"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.string("search_accessories"))
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    await apiClient.fetchPrimaryThenBackground()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: Accessory.self) { accessory in
                AccessoryDetailView(accessory: accessory, apiClient: apiClient, selectedTab: $accessoryDetailTab, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenUser: onOpenUser, onOpenAsset: onOpenAsset, onOpenLocation: onOpenLocation)
            }
        }
        .onChange(of: pendingAccessoryToOpen) { _, new in
            if let accessory = new {
                navigationPath.append(accessory)
                pendingAccessoryToOpen = nil
            }
        }
    }
}

// MARK: - Users Tab
struct UsersTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var userDetailTab: Int
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var showingAddAsset: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingUserToOpen: User?
    @Binding var returnToTab: MainTab?
    var onBackToPreviousTab: () -> Void
    var onOpenAsset: (Asset) -> Void
    var onOpenAccessory: (Accessory) -> Void
    var onOpenLocation: (Location) -> Void

    var filteredUsers: [User] {
        if searchText.isEmpty { return apiClient.users }
        return apiClient.users.filter {
            $0.decodedName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedFirstName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedEmail.lowercased().contains(searchText.lowercased()) ||
            $0.decodedLocationName.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !apiClient.isConfigured {
                    ContentUnavailableView(
                        L10n.string("no_data_yet"),
                        systemImage: "link.badge.plus",
                        description: Text(L10n.string("configure_api_short"))
                    )
                } else if apiClient.isLoading && !isRefreshing {
                    ProgressView(L10n.string("loading_users"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = apiClient.errorMessage {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    List {
                        Section {
                            HStack {
                                Label("\(apiClient.users.count)", systemImage: "person.2")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }

                        Section {
                            ForEach(filteredUsers) { user in
                                Button {
                                    navigationPath.append(user)
                                } label: {
                                    UserCardView(user: user)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                }
            }
            .onAppear { isDetailViewActive = false }
            .navigationTitle(MainTab.users.localizedTitle)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(L10n.string("scan_qr"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.string("search_users"))
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    await apiClient.fetchPrimaryThenBackground()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: User.self) { user in
                UserDetailView(user: user, apiClient: apiClient, selectedTab: $userDetailTab, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenAsset: onOpenAsset, onOpenAccessory: onOpenAccessory, onOpenLocation: onOpenLocation)
            }
        }
        .onChange(of: pendingUserToOpen) { _, new in
            if new != nil { pendingUserToOpen = nil }
        }
    }
}

// MARK: - Locations Tab
struct LocationsTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var locationDetailTab: Int
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var showingAddAsset: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingLocationToOpen: Location?
    @Binding var returnToTab: MainTab?
    var onBackToPreviousTab: () -> Void
    var onOpenUser: (User) -> Void
    var onOpenAsset: (Asset) -> Void

    var filteredLocations: [Location] {
        if searchText.isEmpty { return apiClient.locations }
        return apiClient.locations.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !apiClient.isConfigured {
                    ContentUnavailableView(
                        L10n.string("no_data_yet"),
                        systemImage: "link.badge.plus",
                        description: Text(L10n.string("configure_api_short"))
                    )
                } else if apiClient.isLoading && !isRefreshing {
                    ProgressView(L10n.string("loading_locations"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = apiClient.errorMessage {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    List {
                        Section {
                            HStack {
                                Label("\(apiClient.locations.count)", systemImage: "mappin.and.ellipse")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }

                        Section {
                            ForEach(filteredLocations) { location in
                                Button {
                                    navigationPath.append(location)
                                } label: {
                                    LocationCardView(location: location)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .listSectionSeparator(.hidden)
                }
            }
            .onAppear { isDetailViewActive = false }
            .navigationTitle(MainTab.locations.localizedTitle)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(L10n.string("scan_qr"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.string("search_locations"))
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    await apiClient.fetchPrimaryThenBackground()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: Location.self) { location in
                LocationDetailView(location: location, apiClient: apiClient, selectedTab: $locationDetailTab, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenUser: onOpenUser, onOpenAsset: onOpenAsset)
            }
        }
        .onChange(of: pendingLocationToOpen) { _, new in
            if let location = new {
                navigationPath.append(location)
                pendingLocationToOpen = nil
            }
        }
    }
}

// MARK: - iOS 26 Liquid Glass: tab bar minimaliseert alleen bij scrollen in lijstviews
struct TabBarMinimizeBehaviorModifier: ViewModifier {
    let isDetailVisible: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(isDetailVisible ? .never : .onScrollDown)
        } else {
            content
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}
