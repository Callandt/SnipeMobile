//
//  SnipeMobileApp.swift
//  SnipeMobile
//
//  Created by Avery Callandt on 26/06/2025.
//

import SwiftUI
import LocalAuthentication

class AppSettings: ObservableObject {
    @AppStorage("appLanguage") var appLanguage: String = "en" { willSet { objectWillChange.send() } }
    @AppStorage("appTheme") var appTheme: String = "system" { willSet { objectWillChange.send() } }
    @AppStorage("useBiometrics") var useBiometrics: Bool = false { willSet { objectWillChange.send() } }
    var isDutch: Bool { appLanguage == "nl" }
    var isEnglish: Bool { appLanguage == "en" }
}

@main struct SnipeMobileApp: App {
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
                                showAPISettings = false
                            },
                            onSkip: {
                                hasCompletedOnboarding = true
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
    @State private var selectedTab: String
    @State private var selectedAsset: Asset?
    @State private var selectedAccessory: Accessory?
    @State private var selectedUser: User?
    @State private var selectedLocation: Location?
    @State private var showSettings = false
    @State private var searchText: String = ""
    @State private var selectedAssetDetailTab: Int = 0
    @State private var selectedAccessoryDetailTab: Int = 0
    @State private var selectedUserDetailTab: Int = 0
    @State private var selectedLocationDetailTab: Int = 0

    let tabs: [String]
    init(apiClient: SnipeITAPIClient) {
        self.apiClient = apiClient
        let settings = AppSettings()
        if settings.isDutch {
            _selectedTab = State(initialValue: "Hardware")
            self.tabs = ["Hardware", "Accessoires", "Gebruikers", "Locaties"]
        } else {
            _selectedTab = State(initialValue: "Hardware")
            self.tabs = ["Hardware", "Accessories", "Users", "Locations"]
        }
    }

    var tabGrid: [[String]] {
        [[tabs[0], tabs[1]], [tabs[2], tabs[3]]]
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

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // 2x2 grid tabbar direct onder navigationbar
                VStack(spacing: 12) {
                    ForEach(tabGrid, id: \.self) { row in
                        HStack(spacing: 16) {
                            ForEach(row, id: \.self) { tab in
                                Button(action: { selectedTab = tab }) {
                                    Text(tab)
                                        .font(.headline)
                                        .foregroundColor(selectedTab == tab ? .white : .accentColor)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity)
                                        .background(selectedTab == tab ? Color.accentColor : Color(.systemGray5))
                                        .clipShape(Capsule())
                                        .shadow(color: selectedTab == tab ? Color.accentColor.opacity(0.18) : .clear, radius: 6, y: 2)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .bottom)
                // Zoekbalk
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                .padding(10)
                .background(Color(.systemGray5))
                .cornerRadius(14)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 12)
                // Cards
                Group {
                    switch selectedTab {
                    case tabs[0]:
                        ScrollView {
                            LazyVStack(spacing: 24) {
                                ForEach(filteredAssets) { asset in
                                    AssetCardView(asset: asset)
                                        .onTapGesture {
                                            selectedAsset = asset
                                            selectedAssetDetailTab = 0
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 24)
                                                .fill(.ultraThinMaterial)
                                                .shadow(color: selectedAsset?.id == asset.id ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.07), radius: 10, y: 4)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 24)
                                                .stroke(selectedAsset?.id == asset.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                        .frame(maxWidth: 600)
                                        .padding(.horizontal)
                                }
                                if filteredAssets.isEmpty {
                                    Text("No hardware found.")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 40)
                                }
                                Spacer(minLength: 32)
                            }
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                        }
                    case tabs[1]:
                        ScrollView {
                            LazyVStack(spacing: 24) {
                                ForEach(filteredAccessories) { accessory in
                                    AccessoryCardView(accessory: accessory)
                                        .onTapGesture {
                                            selectedAccessory = accessory
                                            selectedAccessoryDetailTab = 0
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 24)
                                                .fill(.ultraThinMaterial)
                                                .shadow(color: selectedAccessory?.id == accessory.id ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.07), radius: 10, y: 4)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 24)
                                                .stroke(selectedAccessory?.id == accessory.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                        .frame(maxWidth: 600)
                                        .padding(.horizontal)
                                }
                                if filteredAccessories.isEmpty {
                                    Text("No accessories found.")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 40)
                                }
                                Spacer(minLength: 32)
                            }
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                        }
                    case tabs[2]:
                        ScrollView {
                            LazyVStack(spacing: 24) {
                                ForEach(filteredUsers) { user in
                                    UserCardView(user: user)
                                        .onTapGesture {
                                            selectedUser = user
                                            selectedUserDetailTab = 0
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 24)
                                                .fill(.ultraThinMaterial)
                                                .shadow(color: selectedUser?.id == user.id ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.07), radius: 10, y: 4)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 24)
                                                .stroke(selectedUser?.id == user.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                        .frame(maxWidth: 600)
                                        .padding(.horizontal)
                                }
                                if filteredUsers.isEmpty {
                                    Text("No users found.")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 40)
                                }
                                Spacer(minLength: 32)
                            }
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                        }
                    case tabs[3]:
                        ScrollView {
                            LazyVStack(spacing: 24) {
                                ForEach(filteredLocations) { location in
                                    LocationCardView(location: location)
                                        .onTapGesture {
                                            selectedLocation = location
                                            selectedLocationDetailTab = 0
                                        }
                                        .background(
                                            RoundedRectangle(cornerRadius: 24)
                                                .fill(.ultraThinMaterial)
                                                .shadow(color: selectedLocation?.id == location.id ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.07), radius: 10, y: 4)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 24)
                                                .stroke(selectedLocation?.id == location.id ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )
                                        .frame(maxWidth: 600)
                                        .padding(.horizontal)
                                }
                                if filteredLocations.isEmpty {
                                    Text("No locations found.")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 40)
                                }
                                Spacer(minLength: 32)
                            }
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(apiClient: apiClient)
            }
            .onAppear {
                if apiClient.assets.isEmpty && apiClient.users.isEmpty && apiClient.accessories.isEmpty && apiClient.locations.isEmpty {
                    Task { await apiClient.fetchPrimaryThenBackground() }
                }
            }
            .navigationTitle("SnipeMobile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .onChange(of: selectedTab) {
                selectedAsset = nil
                selectedAccessory = nil
                selectedUser = nil
                selectedLocation = nil
            }
        } detail: {
            switch selectedTab {
            case "Hardware":
                if let asset = selectedAsset {
                    AssetDetailView(asset: asset, apiClient: apiClient, selectedTab: $selectedAssetDetailTab)
                } else {
                    Text("Select an asset")
                        .foregroundColor(.secondary)
                }
            case "Accessories":
                if let accessory = selectedAccessory {
                    AccessoryDetailView(accessory: accessory, apiClient: apiClient, selectedTab: $selectedAccessoryDetailTab)
                } else {
                    Text("Select an accessory")
                        .foregroundColor(.secondary)
                }
            case "Users":
                if let user = selectedUser {
                    UserDetailView(user: user, apiClient: apiClient, selectedTab: $selectedUserDetailTab)
                } else {
                    Text("Select a user")
                        .foregroundColor(.secondary)
                }
            case "Locations":
                if let location = selectedLocation {
                    LocationDetailView(location: location, apiClient: apiClient, selectedTab: $selectedLocationDetailTab)
                } else {
                    Text("Select a location")
                        .foregroundColor(.secondary)
                }
            default:
                EmptyView()
            }
        }
    }

    // Helper om de sidebar te togglen
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
