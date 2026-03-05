//
//  SnipeMobileApp.swift
//  SnipeMobile
//
//  Created by Avery Callandt on 26/06/2025.
//

import SwiftUI
import LocalAuthentication
import AVFoundation

class AppSettings: ObservableObject {
    @AppStorage("appLanguage") var appLanguage: String = "en" { willSet { objectWillChange.send() } }
    @AppStorage("appTheme") var appTheme: String = "system" { willSet { objectWillChange.send() } }
    @AppStorage("useBiometrics") var useBiometrics: Bool = false { willSet { objectWillChange.send() } }
    var isDutch: Bool { appLanguage == "nl" }
    var isEnglish: Bool { appLanguage == "en" }
}

@main struct SnipeMobileApp: App {
    init() {
        CloudSettingsStore.shared.mergeFromCloud()
    }
    @StateObject private var apiClient = SnipeITAPIClient()
    @StateObject private var appSettings = AppSettings()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var showAPISettings: Bool = false
    @State private var isLocked = false
    @State private var showBiometricError = false
    @State private var biometricErrorMessage = ""
    @State private var selectedTab: String = "Hardware"
    @State private var selectedAsset: Asset? { didSet { selectedDetailTab = 0 } }
    @State private var selectedAccessory: Accessory? { didSet { selectedDetailTab = 0 } }
    @State private var selectedUser: User? { didSet { selectedDetailTab = 0 } }
    @State private var selectedLocation: Location? { didSet { selectedDetailTab = 0 } }
    @State private var selectedDetailTab: Int = 0
    @State private var justAuthenticated = false
    @State private var showPrivacyBlur = false
    @AppStorage("biometricsJustConfirmed") var biometricsJustConfirmed: Bool = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasCompletedOnboarding {
                    if showAPISettings {
                        APISettingsOnboardingView(
                            onContinue: { url, key in
                                apiClient.saveConfiguration(baseURL: url, apiToken: key)
                                hasCompletedOnboarding = true
                                CloudSettingsStore.shared.setHasCompletedOnboarding(true)
                                showAPISettings = false
                            },
                            onSkip: {
                                hasCompletedOnboarding = true
                                CloudSettingsStore.shared.setHasCompletedOnboarding(true)
                                showAPISettings = false
                            },
                            apiClient: apiClient
                        )
                    } else {
                        WelcomeView(onGetStarted: {
                            showAPISettings = true
                        })
                    }
                } else {
                    Group {
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            MainSplitView(apiClient: apiClient)
                        } else {
                            ContentView()
                        }
                    }
                    .environmentObject(appSettings)
                    .preferredColorScheme(
                        appSettings.appTheme == "light" ? .light :
                        appSettings.appTheme == "dark" ? .dark : nil
                    )
                    // Blur overlay zolang biometrics actief is en nog niet geauthenticeerd
                    if (isLocked && appSettings.useBiometrics == true) || showPrivacyBlur {
                        ZStack {
                            StrongBlurView()
                                .ignoresSafeArea()
                                .zIndex(1)
                            VStack {
                                Spacer()
                                Image("SnipeMobile")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .opacity(0.85)
                                Spacer()
                            }
                            .zIndex(2)
                        }
                    }
                }
            }
            .onAppear {
                if hasCompletedOnboarding && appSettings.useBiometrics == true && !isLocked && !justAuthenticated {
                    isLocked = true
                    authenticateBiometric()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if hasCompletedOnboarding && appSettings.useBiometrics == true && !isLocked && !justAuthenticated {
                    isLocked = true
                    authenticateBiometric()
                }
            }
            .onChange(of: appSettings.useBiometrics) {
                if biometricsJustConfirmed {
                    biometricsJustConfirmed = false
                    // skip lock
                } else if hasCompletedOnboarding && appSettings.useBiometrics == true && !isLocked && !justAuthenticated {
                    isLocked = true
                    authenticateBiometric()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                if appSettings.useBiometrics == true {
                    showPrivacyBlur = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                showPrivacyBlur = false
            }
        }
    }

    private func authenticateBiometric() {
        let context = LAContext()
        var error: NSError?
        let reason = "Authenticate with Face ID or Touch ID to open the app"
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        isLocked = false
                        showBiometricError = false
                        justAuthenticated = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            justAuthenticated = false
                        }
                    } else {
                        biometricErrorMessage = "Authentication failed. Try again."
                        showBiometricError = true
                    }
                }
            }
        } else {
            biometricErrorMessage = "Biometrics not available on this device."
            showBiometricError = true
        }
    }
}

struct MainSplitView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @EnvironmentObject private var appSettings: AppSettings
    @State private var selectedSection: MainTab = .hardware
    @State private var selectedAsset: Asset?
    @State private var selectedAccessory: Accessory?
    @State private var selectedUser: User?
    @State private var selectedLocation: Location?
    @State private var showSettings = false
    @State private var showAddAsset = false
    @State private var showAddAccessory = false
    @State private var showScanner = false
    @State private var scannedAssetId: Int?
    @State private var isRefreshing = false
    @State private var searchText: String = ""
    @State private var selectedAssetDetailTab: Int = 0
    @State private var selectedAccessoryDetailTab: Int = 0
    @State private var selectedUserDetailTab: Int = 0
    @State private var selectedLocationDetailTab: Int = 0
    /// Voor detailviews: tabbar-state (op iPhone in ContentView gebruikt; op iPad niet gebruikt).
    @State private var isDetailViewActive = false
    /// Bij true: onChange(of: selectedSection) niet clearen (we komen van een link in een detail).
    @State private var skipClearSelectionOnSectionChange = false
    @State private var showScanErrorAlert = false
    @State private var scanErrorMessage: String?
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true

    init(apiClient: SnipeITAPIClient) {
        self.apiClient = apiClient
    }

    // Filtered lists per tab
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
    var filteredAccessories: [Accessory] {
        if searchText.isEmpty { return apiClient.accessories }
        return apiClient.accessories.filter {
            $0.decodedName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedAssetTag.lowercased().contains(searchText.lowercased()) ||
            $0.decodedLocationName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedAssignedToName.lowercased().contains(searchText.lowercased())
        }
    }
    var filteredUsers: [User] {
        if searchText.isEmpty { return apiClient.users }
        return apiClient.users.filter {
            $0.decodedName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedFirstName.lowercased().contains(searchText.lowercased()) ||
            $0.decodedEmail.lowercased().contains(searchText.lowercased()) ||
            $0.decodedLocationName.lowercased().contains(searchText.lowercased())
        }
    }
    var filteredLocations: [Location] {
        if searchText.isEmpty { return apiClient.locations }
        return apiClient.locations.filter {
            $0.name.lowercased().contains(searchText.lowercased())
        }
    }

    private func ipadCardRowBackground(selected: Bool) -> some View {
        ZStack {
            Color(.systemGroupedBackground)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .padding(.vertical, 6)
        }
    }

    private var ipadSearchPrompt: String {
        switch selectedSection {
        case .hardware: return L10n.string("search_assets")
        case .accessories: return L10n.string("search_accessories")
        case .users: return L10n.string("search_users")
        case .locations: return L10n.string("search_locations")
        }
    }

    var body: some View {
        mainSplitView
    }

    private var mainSplitView: some View {
        NavigationSplitView {
            ipadSidebar
        } content: {
            ipadContentWithToolbar
                .navigationSplitViewColumnWidth(min: 380, ideal: 420)
        } detail: {
            ipadDetailContent
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedSection) { _, _ in
            if skipClearSelectionOnSectionChange {
                skipClearSelectionOnSectionChange = false
                return
            }
            selectedAsset = nil
            selectedAccessory = nil
            selectedUser = nil
            selectedLocation = nil
        }
        .onChange(of: selectedAsset?.id) { _, _ in
            selectedAssetDetailTab = 0
        }
        .onChange(of: selectedAccessory?.id) { _, _ in
            selectedAccessoryDetailTab = 0
        }
        .onChange(of: selectedUser?.id) { _, _ in
            selectedUserDetailTab = 0
        }
        .onChange(of: selectedLocation?.id) { _, _ in
            selectedLocationDetailTab = 0
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .sheet(isPresented: $showAddAsset) {
            AddAssetSheet(apiClient: apiClient, isPresented: $showAddAsset)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddAccessory) {
            AddAccessorySheet(apiClient: apiClient, isPresented: $showAddAccessory)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showScanner, onDismiss: scannerDismiss) {
            ZoomableQRScannerView(completion: handleScanResult)
        }
        .alert(L10n.string("error"), isPresented: $showScanErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {
                scanErrorMessage = nil
            }
        } message: {
            if let msg = scanErrorMessage {
                Text(msg)
            }
        }
        .onChange(of: scannedAssetId) { _, new in
            selectScannedAsset(id: new)
        }
        .onChange(of: apiClient.assets.count) { _, _ in
            selectScannedAsset(id: scannedAssetId)
        }
    }

    private var settingsSheet: some View {
        SettingsView(apiClient: apiClient)
            .preferredColorScheme(
                appSettings.appTheme == "light" ? .light :
                appSettings.appTheme == "dark" ? .dark : nil
            )
    }

    private func scannerDismiss() {
        if let id = scannedAssetId,
           let asset = apiClient.assets.first(where: { $0.id == id }) {
            selectedSection = .hardware
            selectedAsset = asset
            selectedAssetDetailTab = 0
        }
        scannedAssetId = nil
    }

    private func selectScannedAsset(id: Int?) {
        guard let id = id, let asset = apiClient.assets.first(where: { $0.id == id }) else { return }
        selectedSection = .hardware
        selectedAsset = asset
        selectedAssetDetailTab = 0
    }

    private var ipadSidebar: some View {
        List {
            Section {
                Button {
                    showScanner = true
                } label: {
                    Label(L10n.string("scan_qr"), systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.plain)

                ForEach(MainTab.allCases, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.localizedTitle, systemImage: section.icon)
                            .foregroundStyle(selectedSection == section ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedSection == section ? Color.accentColor.opacity(0.15) : nil)
                }
            }

            Section {
                Button {
                    showSettings = true
                } label: {
                    Label(L10n.string("settings"), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SnipeMobile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if apiClient.assets.isEmpty && apiClient.users.isEmpty && apiClient.accessories.isEmpty && apiClient.locations.isEmpty {
                Task { await apiClient.fetchPrimaryThenBackground() }
            }
        }
    }

    private var ipadContentWithToolbar: some View {
        ipadContentColumn
            .navigationTitle(selectedSection.localizedTitle)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: Text(ipadSearchPrompt))
            .toolbar {
                if selectedSection == .hardware || selectedSection == .accessories {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 16) {
                            if selectedSection == .hardware {
                                Button(action: { showAddAsset = true }) {
                                    Image(systemName: "plus.circle")
                                }
                                .accessibilityLabel(L10n.string("add_asset"))
                            }
                            if selectedSection == .accessories {
                                Button(action: { showAddAccessory = true }) {
                                    Image(systemName: "plus.circle")
                                }
                                .accessibilityLabel(L10n.string("add_accessory"))
                            }
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var ipadDetailContent: some View {
        switch selectedSection {
        case .hardware:
            if let asset = selectedAsset {
                AssetDetailView(
                    asset: asset,
                    apiClient: apiClient,
                    selectedTab: $selectedAssetDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { [apiClient] user in
                        let resolved = apiClient.users.first(where: { $0.id == user.id }) ?? user
                        selectedUser = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLocation = nil
                        selectedUserDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .users
                    },
                    onOpenLocation: { [apiClient] location in
                        let resolved = apiClient.locations.first(where: { $0.id == location.id }) ?? location
                        selectedLocation = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocationDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .locations
                    }
                )
            } else {
                ContentUnavailableView(
                    L10n.string("select_asset"),
                    systemImage: "laptopcomputer",
                    description: Text("Choose an asset from the list")
                )
            }
        case .accessories:
            if let accessory = selectedAccessory {
                AccessoryDetailView(
                    accessory: accessory,
                    apiClient: apiClient,
                    selectedTab: $selectedAccessoryDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { [apiClient] user in
                        let resolved = apiClient.users.first(where: { $0.id == user.id }) ?? user
                        selectedUser = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLocation = nil
                        selectedUserDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .users
                    },
                    onOpenAsset: { [apiClient] asset in
                        let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAssetDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .hardware
                    },
                    onOpenLocation: { [apiClient] location in
                        let resolved = apiClient.locations.first(where: { $0.id == location.id }) ?? location
                        selectedLocation = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocationDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .locations
                    }
                )
            } else {
                ContentUnavailableView(
                    L10n.string("select_accessory"),
                    systemImage: "mediastick",
                    description: Text("Choose an accessory from the list")
                )
            }
        case .users:
            if let user = selectedUser {
                UserDetailView(
                    user: user,
                    apiClient: apiClient,
                    selectedTab: $selectedUserDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenAsset: { [apiClient] asset in
                        let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAssetDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .hardware
                    },
                    onOpenAccessory: { [apiClient] accessory in
                        let resolved = apiClient.accessories.first(where: { $0.id == accessory.id }) ?? accessory
                        selectedAccessory = resolved
                        selectedAsset = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAccessoryDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .accessories
                    },
                    onOpenLocation: { [apiClient] location in
                        let resolved = apiClient.locations.first(where: { $0.id == location.id }) ?? location
                        selectedLocation = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocationDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .locations
                    }
                )
            } else {
                ContentUnavailableView(
                    L10n.string("select_user"),
                    systemImage: "person.2",
                    description: Text("Choose a user from the list")
                )
            }
        case .locations:
            if let location = selectedLocation {
                LocationDetailView(
                    location: location,
                    apiClient: apiClient,
                    selectedTab: $selectedLocationDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { [apiClient] user in
                        let resolved = apiClient.users.first(where: { $0.id == user.id }) ?? user
                        selectedUser = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLocation = nil
                        selectedUserDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .users
                    },
                    onOpenAsset: { [apiClient] asset in
                        let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAssetDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .hardware
                    }
                )
            } else {
                ContentUnavailableView(
                    L10n.string("select_location"),
                    systemImage: "mappin.and.ellipse",
                    description: Text("Choose a location from the list")
                )
            }
        }
    }

    @ViewBuilder
    private var ipadContentColumn: some View {
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api_short"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiClient.isLoading && !isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = apiClient.errorMessage {
                ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedSection {
                case .hardware:
                    ipadAssetList
                case .accessories:
                    ipadAccessoryList
                case .users:
                    ipadUserList
                case .locations:
                    ipadLocationList
                }
            }
        }
    }

    private var ipadAssetList: some View {
        List {
            ForEach(filteredAssets) { asset in
                let isSelected = selectedAsset?.id == asset.id
                Button {
                    selectedAsset = asset
                } label: {
                    AssetCardView(asset: asset, useExplicitBackground: true)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .listSectionSeparator(.hidden)
        .overlay {
            if filteredAssets.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_hardware"), systemImage: "laptopcomputer")
            }
        }
        .refreshable {
            if apiClient.isConfigured {
                isRefreshing = true
                await apiClient.fetchPrimaryThenBackground()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private var ipadAccessoryList: some View {
        List {
            ForEach(filteredAccessories) { accessory in
                let isSelected = selectedAccessory?.id == accessory.id
                Button {
                    selectedAccessory = accessory
                } label: {
                    AccessoryCardView(accessory: accessory, useExplicitBackground: true)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .listSectionSeparator(.hidden)
        .overlay {
            if filteredAccessories.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_accessories"), systemImage: "mediastick")
            }
        }
        .refreshable {
            if apiClient.isConfigured {
                isRefreshing = true
                await apiClient.fetchPrimaryThenBackground()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private var ipadUserList: some View {
        List {
            ForEach(filteredUsers) { user in
                let isSelected = selectedUser?.id == user.id
                Button {
                    selectedUser = user
                } label: {
                    UserCardView(user: user, useExplicitBackground: true)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .listSectionSeparator(.hidden)
        .overlay {
            if filteredUsers.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_users"), systemImage: "person.2")
            }
        }
        .refreshable {
            if apiClient.isConfigured {
                isRefreshing = true
                await apiClient.fetchPrimaryThenBackground()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private var ipadLocationList: some View {
        List {
            ForEach(filteredLocations) { location in
                let isSelected = selectedLocation?.id == location.id
                Button {
                    selectedLocation = location
                } label: {
                    LocationCardView(location: location, useExplicitBackground: true)
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .listSectionSeparator(.hidden)
        .overlay {
            if filteredLocations.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_locations"), systemImage: "mappin.and.ellipse")
            }
        }
        .refreshable {
            if apiClient.isConfigured {
                isRefreshing = true
                await apiClient.fetchPrimaryThenBackground()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private func handleScanResult(_ result: Result<ScanResult, ScanError>) {
        showScanner = false
        switch result {
        case .success(let scanResult):
            guard let url = URL(string: scanResult.string) else {
                scanErrorMessage = L10n.string("invalid_qr_no_asset_id")
                showScanErrorAlert = true
                return
            }
            apiClient.errorMessage = nil

            // 1) Snipe-IT QR: URL met asset-ID in pad
            if let id = extractAssetId(from: url) {
                if apiClient.assets.first(where: { $0.id == id }) != nil {
                    scannedAssetId = id
                    selectedSection = .hardware
                } else if apiClient.assets.isEmpty {
                    scannedAssetId = id
                    selectedSection = .hardware
                    Task { await apiClient.fetchPrimaryThenBackground() }
                } else {
                    scannedAssetId = nil
                    scanErrorMessage = L10n.string("asset_not_found_id", String(id))
                    showScanErrorAlert = true
                }
                return
            }

            // 2) Dell QR: URL met service tag/serial; zoek asset op serienummer (alleen als instelling aan)
            if enableDellQrScan,
               let host = url.host, host.lowercased().contains("dell"),
               let serial = SnipeITAPIClient.extractDellServiceTag(from: url), !serial.isEmpty {
                let normalized = serial.trimmingCharacters(in: .whitespaces).lowercased()
                if let asset = apiClient.assets.first(where: {
                    $0.decodedSerial.trimmingCharacters(in: .whitespaces).lowercased() == normalized
                }) {
                    scannedAssetId = asset.id
                    selectedSection = .hardware
                } else {
                    scannedAssetId = nil
                    scanErrorMessage = L10n.string("asset_not_found_serial", serial)
                    showScanErrorAlert = true
                }
                return
            }

            scanErrorMessage = L10n.string("invalid_qr_no_asset_id")
            showScanErrorAlert = true
        case .failure(let error):
            scanErrorMessage = String(format: L10n.string("scan_failed"), error.localizedDescription)
            showScanErrorAlert = true
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

    private func toggleSidebar() {
        #if targetEnvironment(macCatalyst)
        UIApplication.shared.sendAction(Selector(("toggleSidebar:")), to: nil, from: nil, for: nil)
        #else
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if let splitViewController = scene.windows.first?.rootViewController as? UISplitViewController {
                splitViewController.show(.primary)
            }
        }
        #endif
    }
}

