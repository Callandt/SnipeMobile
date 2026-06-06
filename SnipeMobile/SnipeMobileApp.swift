//
//  SnipeMobileApp.swift
//  SnipeMobile
//
//  Created by Avery Callandt on 26/06/2025.
//

import SwiftUI
import LocalAuthentication
import AVFoundation
import StoreKit
import UIKit
import UserNotifications

private let pendingAuditIntentDefaultsKey = "pendingAuditIntent"

class AppSettings: ObservableObject {
    @AppStorage("appLanguage") var appLanguage: String = "en" { willSet { objectWillChange.send() } }
    @AppStorage("appTheme") var appTheme: String = "system" { willSet { objectWillChange.send() } }
    @AppStorage("useBiometrics") var useBiometrics: Bool = false { willSet { objectWillChange.send() } }
    var isDutch: Bool { appLanguage == "nl" }
    var isEnglish: Bool { appLanguage == "en" }
}

enum AuditNotificationIntent: String {
    case openDueToday
}

extension Notification.Name {
    static let auditNotificationTapped = Notification.Name("auditNotificationTapped")
}

@MainActor
final class AuditNotificationRouter: ObservableObject {
    struct PendingRequest: Identifiable {
        let id = UUID()
        let intent: AuditNotificationIntent
    }

    @Published var pendingRequest: PendingRequest?

    func set(intent: AuditNotificationIntent) {
        pendingRequest = PendingRequest(intent: intent)
    }

    func consume() {
        pendingRequest = nil
    }
}

final class AuditNotificationManager {
    static let shared = AuditNotificationManager()

    private let identifier = "audit-daily-notification"

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings: UNNotificationSettings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { notificationSettings in
                continuation.resume(returning: notificationSettings)
            }
        }

        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            return true
        }

        let granted: Bool = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                continuation.resume(returning: ok)
            }
        }

        return granted
    }

    func updateSchedule(
        enabled: Bool,
        hour: Int,
        minute: Int,
        assets: [Asset]
    ) async {
        let center = UNUserNotificationCenter.current()

        if !enabled {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            return
        }

        guard await requestAuthorizationIfNeeded() else { return }

        let dueTodayCount = assets.filter { AuditDateClassifier.isDueToday($0, now: Date()) }.count

        let content = UNMutableNotificationContent()
        content.title = L10n.string("audit_notification_title")
        content.body = String(format: L10n.string("audit_notification_body"), dueTodayCount)
        content.sound = .default
        content.userInfo = [
            "auditIntent": AuditNotificationIntent.openDueToday.rawValue
        ]

        var comps = DateComponents()
        comps.hour = max(0, min(hour, 23))
        comps.minute = max(0, min(minute, 59))

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // No crash; notification scheduling can fail if disabled by OS settings.
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banners even while the app is in the foreground.
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard
            let intentStr = response.notification.request.content.userInfo["auditIntent"] as? String,
            let intent = AuditNotificationIntent(rawValue: intentStr)
        else { return }

        // Persist fallback for cold-start: NotificationCenter event can fire
        // before SwiftUI `onReceive` observers are attached.
        UserDefaults.standard.set(intent.rawValue, forKey: pendingAuditIntentDefaultsKey)

        NotificationCenter.default.post(
            name: .auditNotificationTapped,
            object: nil,
            userInfo: ["intent": intent]
        )
    }
}

@main struct SnipeMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        KeychainSecretStore.migrateLegacyUserDefaultsSecretsIfNeeded()
        KeychainSecretStore.migrateLocalSecretsToICloudKeychainIfNeeded()
        CloudSettingsStore.shared.mergeFromCloud()
    }
    @StateObject private var apiClient = SnipeITAPIClient()
    @StateObject private var appSettings = AppSettings()
    @StateObject private var auditNotificationRouter = AuditNotificationRouter()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hasSeenModulesIntro") private var hasSeenModulesIntro: Bool = false
    @State private var showAPISettings: Bool = false
    @State private var showModuleSelection: Bool = false
    @State private var showModulesIntroForExisting: Bool = false
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
    @State private var didRequestReviewThisLaunch = false
    @State private var didCountLaunchThisSession = false
    @AppStorage("reviewPromptLaunchCount") private var reviewPromptLaunchCount: Int = 0
    @AppStorage("reviewPromptLastRequestedAt") private var reviewPromptLastRequestedAt: Double = 0
    @AppStorage("reviewPromptLastRequestedVersion") private var reviewPromptLastRequestedVersion: String = ""

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !hasCompletedOnboarding {
                    if showModuleSelection {
                        ModuleSelectionView(onDone: {
                            hasCompletedOnboarding = true
                            hasSeenModulesIntro = true
                            CloudSettingsStore.shared.setHasCompletedOnboarding(true)
                            CloudSettingsStore.shared.setHasSeenModulesIntro(true)
                            showModuleSelection = false
                            showAPISettings = false
                        })
                    } else if showAPISettings {
                        APISettingsOnboardingView(
                            onContinue: { url, key in
                                apiClient.saveConfiguration(baseURL: url, apiToken: key)
                                showModuleSelection = true
                            },
                            onSkip: {
                                showModuleSelection = true
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
                    .environmentObject(auditNotificationRouter)
                    .preferredColorScheme(
                        appSettings.appTheme == "light" ? .light :
                        appSettings.appTheme == "dark" ? .dark : nil
                    )
                    // Blur until biometrics done
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
                // Cold boot fallback: if notification tap happened before observers
                // attached, recover the pending intent from UserDefaults.
                if let raw = UserDefaults.standard.string(forKey: pendingAuditIntentDefaultsKey),
                   let intent = AuditNotificationIntent(rawValue: raw) {
                    auditNotificationRouter.set(intent: intent)
                    UserDefaults.standard.removeObject(forKey: pendingAuditIntentDefaultsKey)
                }

                if hasCompletedOnboarding && appSettings.useBiometrics == true && !isLocked && !justAuthenticated {
                    isLocked = true
                    authenticateBiometric()
                }

                // Count app launches once per process, after onboarding completion.
                if hasCompletedOnboarding && !didCountLaunchThisSession {
                    reviewPromptLaunchCount += 1
                    didCountLaunchThisSession = true
                }

                // One-time module picker for users upgrading from before it existed.
                if hasCompletedOnboarding && !hasSeenModulesIntro {
                    showModulesIntroForExisting = true
                }
            }
            .fullScreenCover(isPresented: $showModulesIntroForExisting) {
                ModuleSelectionView(onDone: {
                    hasSeenModulesIntro = true
                    CloudSettingsStore.shared.setHasSeenModulesIntro(true)
                    showModulesIntroForExisting = false
                })
                .environmentObject(appSettings)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if hasCompletedOnboarding && appSettings.useBiometrics == true && !isLocked && !justAuthenticated {
                    isLocked = true
                    authenticateBiometric()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .auditNotificationTapped)) { note in
                guard hasCompletedOnboarding else { return }
                guard let intent = note.userInfo?["intent"] as? AuditNotificationIntent else { return }
                UserDefaults.standard.removeObject(forKey: pendingAuditIntentDefaultsKey)
                auditNotificationRouter.set(intent: intent)
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
                guard hasCompletedOnboarding, !didRequestReviewThisLaunch else { return }
                maybeRequestAppStoreReviewIfEligible()
            }
        }
    }

    private var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func maybeRequestAppStoreReviewIfEligible() {
        let minimumLaunches = 12
        let cooldownDays = 180

        guard reviewPromptLaunchCount >= minimumLaunches else { return }
        guard reviewPromptLastRequestedVersion != currentAppVersion else { return }

        if reviewPromptLastRequestedAt > 0 {
            let lastPromptDate = Date(timeIntervalSince1970: reviewPromptLastRequestedAt)
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastPromptDate, to: Date()).day ?? 0
            guard daysSinceLastPrompt >= cooldownDays else { return }
        }

        didRequestReviewThisLaunch = true
        reviewPromptLastRequestedAt = Date().timeIntervalSince1970
        reviewPromptLastRequestedVersion = currentAppVersion
        requestAppStoreReview()
    }

    private func requestAppStoreReview() {
        // iOS 18+: AppStore.requestReview(in:)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })

        guard let scene else { return }

        AppStore.requestReview(in: scene)
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
    @EnvironmentObject private var auditNotificationRouter: AuditNotificationRouter
    @State private var selectedSection: MainTab = .hardware
    @State private var selectedAsset: Asset?
    @State private var selectedAccessory: Accessory?
    @State private var selectedLicense: License?
    @State private var selectedConsumable: Consumable?
    @State private var selectedComponent: Component?
    @State private var selectedUser: User?
    @State private var selectedLocation: Location?
    @State private var showSettings = false
    @State private var showAddAsset = false
    @State private var showAddAccessory = false
    @State private var showAddLicense = false
    @State private var showAddConsumable = false
    @State private var showAddComponent = false
    @State private var showComingSoonAlert = false
    @State private var showScanner = false
    @State private var scannedAssetId: Int?
    @State private var isRefreshing = false
    @State private var searchText: String = ""
    @State private var awaitingAuditNavigationResolution = false
	    @State private var auditNotificationNavResolved = false
    @State private var auditListFilter: AuditListFilter = .all
    @State private var hardwareSubtab: HardwareAuditSubtab = .all
    @State private var showTodayOnlyOverride = false
    @State private var selectedAssetDetailTab: Int = 0
    @State private var selectedAccessoryDetailTab: Int = 0
    @State private var selectedLicenseDetailTab: Int = 0
    @State private var selectedConsumableDetailTab: Int = 0
    @State private var selectedComponentDetailTab: Int = 0
    @State private var selectedUserDetailTab: Int = 0
    @State private var selectedLocationDetailTab: Int = 0
    @AppStorage("showAccessoriesTab") private var showAccessoriesTab: Bool = true
    @AppStorage("showLicensesTab") private var showLicensesTab: Bool = true
    @AppStorage("showConsumablesTab") private var showConsumablesSub: Bool = true
    @AppStorage("showComponentsTab") private var showComponentsSub: Bool = true
    @AppStorage("stockSelectedSubmodule") private var stockSelectedRaw: String = StockSubmodule.consumables.rawValue
    @AppStorage("directorySelectedSubmodule") private var directorySelectedRaw: String = DirectorySubmodule.users.rawValue

    private var orderedVisibleSections: [MainTab] {
        TabOrderStore.defaultOrder.filter { tab in
            switch tab {
            case .hardware, .directory: return true
            case .accessories: return showAccessoriesTab
            case .licenses: return showLicensesTab
            case .stock: return showConsumablesSub || showComponentsSub
            }
        }
    }

    private var enabledStockSubmodules: [StockSubmodule] {
        StockSubmodule.allCases.filter {
            switch $0 {
            case .consumables: return showConsumablesSub
            case .components: return showComponentsSub
            }
        }
    }

    private var stockSelectedSubmodule: StockSubmodule {
        let stored = StockSubmodule(rawValue: stockSelectedRaw) ?? .consumables
        return enabledStockSubmodules.contains(stored) ? stored : (enabledStockSubmodules.first ?? .consumables)
    }

    private var enabledDirectorySubmodules: [DirectorySubmodule] { DirectorySubmodule.allCases }

    private var directorySelectedSubmodule: DirectorySubmodule {
        DirectorySubmodule(rawValue: directorySelectedRaw) ?? .users
    }

    private func sectionTitle(_ section: MainTab) -> String {
        switch section {
        case .stock where enabledStockSubmodules.count == 1:
            return enabledStockSubmodules[0].localizedTitle
        default:
            return section.localizedTitle
        }
    }

    private func sectionIcon(_ section: MainTab) -> String {
        switch section {
        case .stock where enabledStockSubmodules.count == 1:
            return enabledStockSubmodules[0].icon
        default:
            return section.icon
        }
    }
    /// Tab bar state. iPhone only.
    @State private var isDetailViewActive = false
    /// From detail link. Don't clear section onChange.
    @State private var skipClearSelectionOnSectionChange = false
    @State private var showScanErrorAlert = false
    @State private var scanErrorMessage: String?
    @State private var showAddDellAssetPrompt = false
    @State private var pendingDellURLForAdd: URL?
    @State private var pendingDellSerial: String?
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true
    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = false
    @AppStorage("auditNotificationsEnabled") private var auditNotificationsEnabled: Bool = false
    @AppStorage("auditNotificationHour") private var auditNotificationHour: Int = 9
    @AppStorage("auditNotificationMinute") private var auditNotificationMinute: Int = 0
    private let dueSoonDays: Int = 7

    // Audit completion sheet (iPad list quick action).
    @State private var showAuditCompletionSheet = false
    @State private var auditCompletionAsset: Asset?
    @State private var auditCompletionNextAuditDate: Date = Date()
    @State private var isSavingAuditCompletion = false
    @State private var showAuditCompletionErrorAlert = false
    @State private var auditCompletionErrorMessage = ""
    @State private var isOverdueExpanded = false

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
    var filteredLicenses: [License] {
        if searchText.isEmpty { return apiClient.licenses }
        let needle = searchText.lowercased()
        return apiClient.licenses.filter {
            $0.decodedName.lowercased().contains(needle) ||
            $0.decodedManufacturerName.lowercased().contains(needle) ||
            $0.decodedCategoryName.lowercased().contains(needle) ||
            $0.decodedLicenseName.lowercased().contains(needle) ||
            $0.decodedLicenseEmail.lowercased().contains(needle)
        }
    }
    var filteredConsumables: [Consumable] {
        if searchText.isEmpty { return apiClient.consumables }
        let needle = searchText.lowercased()
        return apiClient.consumables.filter {
            $0.decodedName.lowercased().contains(needle) ||
            $0.decodedItemNo.lowercased().contains(needle) ||
            $0.decodedModelNumber.lowercased().contains(needle) ||
            $0.decodedLocationName.lowercased().contains(needle) ||
            $0.decodedManufacturerName.lowercased().contains(needle) ||
            $0.decodedCategoryName.lowercased().contains(needle)
        }
    }
    var filteredComponents: [Component] {
        if searchText.isEmpty { return apiClient.components }
        let needle = searchText.lowercased()
        return apiClient.components.filter {
            $0.decodedName.lowercased().contains(needle) ||
            $0.decodedSerial.lowercased().contains(needle) ||
            $0.decodedModelNumber.lowercased().contains(needle) ||
            $0.decodedLocationName.lowercased().contains(needle) ||
            $0.decodedManufacturerName.lowercased().contains(needle) ||
            $0.decodedCategoryName.lowercased().contains(needle)
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
            $0.decodedName.lowercased().contains(searchText.lowercased())
        }
    }

    private var auditNow: Date { Date() }

    private var dueTodayAssets: [Asset] {
        let now = auditNow
        return AuditDateClassifier.sortByNextAuditDateThenTag(
            filteredAssets.filter { AuditDateClassifier.isDueToday($0, now: now) }
        )
    }

    private var dueSoonAssets: [Asset] {
        let now = auditNow
        return AuditDateClassifier.sortByNextAuditDateThenTag(
            filteredAssets.filter { AuditDateClassifier.isDueSoon($0, now: now, dueSoonDays: dueSoonDays) }
        )
    }

    private var overdueAssets: [Asset] {
        let now = auditNow
        return AuditDateClassifier.sortByNextAuditDateThenTag(
            filteredAssets.filter { AuditDateClassifier.isOverdue($0, now: now) }
        )
    }

    private func tryResolveAndOpenAuditTarget() {
        guard !auditNotificationNavResolved else { return }

        // For this notification, switch to the Audit subtab and show full results
        // (not just the "due today" view).
        auditListFilter = .all
        showTodayOnlyOverride = false
        hardwareSubtab = enableAuditSubtab ? .audit : .all
        auditNotificationNavResolved = true

        // Open hardware list, not asset detail.
        searchText = ""
        let needsSectionChange = selectedSection != .hardware
        skipClearSelectionOnSectionChange = needsSectionChange
        selectedSection = .hardware
        selectedAssetDetailTab = 0
        selectedAsset = nil

        // Wait for the `selectedSection`/`assets.count` updates to land, then proceed.
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                awaitingAuditNavigationResolution = false
                auditNotificationRouter.consume()
            }
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
        case .licenses: return L10n.string("search_licenses")
        case .stock:
            return stockSelectedSubmodule == .consumables
                ? L10n.string("search_consumables")
                : L10n.string("search_components")
        case .directory:
            return directorySelectedSubmodule == .users
                ? L10n.string("search_users")
                : L10n.string("search_locations")
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
        .alert(
            L10n.string("refresh_failed_title"),
            isPresented: Binding(
                get: { apiClient.refreshErrorMessage != nil },
                set: { if !$0 { apiClient.refreshErrorMessage = nil } }
            )
        ) {
            Button(L10n.string("ok"), role: .cancel) { apiClient.refreshErrorMessage = nil }
        } message: {
            Text(apiClient.refreshErrorMessage ?? "")
        }
        .onChange(of: selectedSection) { _, newSection in
            if skipClearSelectionOnSectionChange {
                skipClearSelectionOnSectionChange = false
                return
            }
            if newSection != .hardware {
                showTodayOnlyOverride = false
                auditListFilter = .all
                hardwareSubtab = .all
            }
            selectedAsset = nil
            selectedAccessory = nil
            selectedLicense = nil
            selectedConsumable = nil
            selectedComponent = nil
            selectedUser = nil
            selectedLocation = nil
        }
        .onChange(of: selectedAsset?.id) { _, _ in
            selectedAssetDetailTab = 0
        }
        .onChange(of: selectedAccessory?.id) { _, _ in
            selectedAccessoryDetailTab = 0
        }
        .onChange(of: selectedConsumable?.id) { _, _ in
            selectedConsumableDetailTab = 0
        }
        .onChange(of: selectedComponent?.id) { _, _ in
            selectedComponentDetailTab = 0
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
        .sheet(isPresented: $showAddAsset, onDismiss: {
            pendingDellURLForAdd = nil
            pendingDellSerial = nil
        }) {
            AddAssetSheet(
                apiClient: apiClient,
                isPresented: $showAddAsset,
                prefilledDellURL: pendingDellURLForAdd,
                prefilledSerial: pendingDellSerial
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddAccessory) {
            AddAccessorySheet(apiClient: apiClient, isPresented: $showAddAccessory)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddLicense) {
            AddLicenseSheet(
                apiClient: apiClient,
                isPresented: $showAddLicense,
                onCreated: { newId in
                    Task {
                        if let newId,
                           let detailed = await apiClient.fetchLicenseDetails(licenseId: newId) {
                            await MainActor.run {
                                selectedLicense = detailed
                            }
                        }
                    }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddConsumable) {
            AddConsumableSheet(
                apiClient: apiClient,
                isPresented: $showAddConsumable,
                onCreated: { newId in
                    Task {
                        if let newId,
                           let detailed = await apiClient.fetchConsumableDetails(consumableId: newId) {
                            await MainActor.run {
                                selectedConsumable = detailed
                            }
                        }
                    }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showAddComponent) {
            AddComponentSheet(
                apiClient: apiClient,
                isPresented: $showAddComponent,
                onCreated: { newId in
                    Task {
                        if let newId,
                           let detailed = await apiClient.fetchComponentDetails(componentId: newId) {
                            await MainActor.run {
                                selectedComponent = detailed
                            }
                        }
                    }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showScanner, onDismiss: scannerDismiss) {
            ZoomableQRScannerView(
                completion: handleScanResult,
                supportedTypes: [.qr, .dataMatrix, .code39, .code128, .ean13, .upce]
            )
        }
        .sheet(isPresented: $showAuditCompletionSheet) {
            NavigationStack {
                Form {
                    Section {
                        Text(L10n.string("audit_completed_sheet_message"))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        DatePicker(
                            L10n.string("next_audit_date"),
                            selection: $auditCompletionNextAuditDate,
                            displayedComponents: .date
                        )
                    }
                }
                .navigationTitle(L10n.string("audit_completed_sheet_title"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.string("cancel"), role: .cancel) {
                            showAuditCompletionSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.string("save")) {
                            Task { await saveAuditCompletionForIpad() }
                        }
                        .disabled(isSavingAuditCompletion)
                    }
                }
            }
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
        .alert(
            L10n.string("dell_asset_not_found_title"),
            isPresented: $showAddDellAssetPrompt
        ) {
            Button(L10n.string("cancel"), role: .cancel) {
                pendingDellURLForAdd = nil
                pendingDellSerial = nil
            }
            Button(L10n.string("dell_asset_not_found_add")) {
                showAddAsset = true
            }
        } message: {
            if let s = pendingDellSerial {
                Text(L10n.string("dell_asset_not_found_message", s))
            }
        }
        .alert(L10n.string("error"), isPresented: $showAuditCompletionErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {
                auditCompletionErrorMessage = ""
            }
        } message: {
            Text(auditCompletionErrorMessage)
        }
        .onAppear {
            // Cold boot: `pendingRequest` may already be set before `onChange` fires.
            if auditNotificationRouter.pendingRequest != nil, !auditNotificationNavResolved {
                awaitingAuditNavigationResolution = true
                auditNotificationNavResolved = false
                tryResolveAndOpenAuditTarget()
            }
        }
        .onChange(of: auditNotificationRouter.pendingRequest?.id) { _, _ in
            guard auditNotificationRouter.pendingRequest != nil else { return }
            awaitingAuditNavigationResolution = true
            auditNotificationNavResolved = false
            tryResolveAndOpenAuditTarget()
        }
        .onChange(of: scannedAssetId) { _, new in
            selectScannedAsset(id: new)
        }
        .onChange(of: apiClient.assets.count) { _, _ in
            if awaitingAuditNavigationResolution {
                tryResolveAndOpenAuditTarget()
            }
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

    private func saveAuditCompletionForIpad() async {
        guard !isSavingAuditCompletion, let assetId = auditCompletionAsset?.id else { return }
        isSavingAuditCompletion = true
        defer { isSavingAuditCompletion = false }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let nextAuditStr = formatter.string(from: auditCompletionNextAuditDate)

        let update = SnipeITAPIClient.AssetUpdateRequest(
            name: nil,
            asset_tag: nil,
            serial: nil,
            model_id: nil,
            status_id: nil,
            category_id: nil,
            manufacturer_id: nil,
            supplier_id: nil,
            notes: nil,
            order_number: nil,
            location_id: nil,
            purchase_cost: nil,
            book_value: nil,
            custom_fields: nil,
            purchase_date: nil,
            next_audit_date: .value(nextAuditStr),
            expected_checkin: nil,
            eol_date: nil,
            warranty_months: nil,
            image_delete: nil
        )

        let ok = await apiClient.updateAsset(assetId: assetId, update: update)
        if ok {
            showAuditCompletionSheet = false
            auditCompletionAsset = nil
            await apiClient.fetchPrimaryThenBackground()

            if auditNotificationsEnabled {
                await AuditNotificationManager.shared.updateSchedule(
                    enabled: true,
                    hour: auditNotificationHour,
                    minute: auditNotificationMinute,
                    assets: apiClient.assets
                )
            }
        } else {
            auditCompletionErrorMessage = apiClient.lastApiMessage ?? (apiClient.errorMessage ?? L10n.string("error"))
            showAuditCompletionErrorAlert = true
        }
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

                ForEach(orderedVisibleSections, id: \.self) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(sectionTitle(section), systemImage: sectionIcon(section))
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
            .navigationTitle(comboAwareSectionTitle)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: Text(ipadSearchPrompt))
            .toolbar {
                if selectedSection == .stock, enabledStockSubmodules.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        comboPicker(
                            current: stockSelectedSubmodule.icon,
                            options: enabledStockSubmodules.map { ($0.rawValue, $0.localizedTitle, $0.icon) },
                            selection: $stockSelectedRaw
                        )
                    }
                }
                if selectedSection == .directory, enabledDirectorySubmodules.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        comboPicker(
                            current: directorySelectedSubmodule.icon,
                            options: enabledDirectorySubmodules.map { ($0.rawValue, $0.localizedTitle, $0.icon) },
                            selection: Binding(
                                get: { directorySelectedRaw },
                                set: { newValue in
                                    directorySelectedRaw = newValue
                                    selectedUser = nil
                                    selectedLocation = nil
                                }
                            )
                        )
                    }
                }
                if selectedSection == .hardware {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showAddAsset = true }) {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel(L10n.string("add_asset"))
                    }
                }
                if selectedSection == .accessories {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showAddAccessory = true }) {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel(L10n.string("add_accessory"))
                    }
                }
                if selectedSection == .licenses {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showAddLicense = true }) {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel(L10n.string("add_license"))
                    }
                }
                if selectedSection == .stock {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            if stockSelectedSubmodule == .consumables {
                                showAddConsumable = true
                            } else if stockSelectedSubmodule == .components {
                                showAddComponent = true
                            } else {
                                showComingSoonAlert = true
                            }
                        }) {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel(L10n.string("add"))
                    }
                }
                if selectedSection == .directory {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showComingSoonAlert = true }) {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel(directoryAddLabel)
                    }
                }
            }
            .alert(L10n.string("module_coming_soon_title"), isPresented: $showComingSoonAlert) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(comingSoonMessage)
            }
    }

    private var directoryAddLabel: String {
        directorySelectedSubmodule == .users
            ? L10n.string("add_user")
            : L10n.string("add_location")
    }

    private var comingSoonMessage: String {
        L10n.string("module_coming_soon")
    }

    private var comboAwareSectionTitle: String {
        switch selectedSection {
        case .stock: return stockSelectedSubmodule.localizedTitle
        case .directory: return directorySelectedSubmodule.localizedTitle
        default: return selectedSection.localizedTitle
        }
    }

    private func comboPicker(
        current iconName: String,
        options: [(raw: String, title: String, icon: String)],
        selection: Binding<String>
    ) -> some View {
        Menu {
            Picker(selection: selection) {
                ForEach(options, id: \.raw) { option in
                    Label(option.title, systemImage: option.icon)
                        .tag(option.raw)
                }
            } label: {
                Text(L10n.string("switch_module"))
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: iconName)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
        .accessibilityLabel(L10n.string("switch_module"))
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
                        selectedLicense = nil
                        selectedLocation = nil
                        selectedUserDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        directorySelectedRaw = DirectorySubmodule.users.rawValue
                        selectedSection = .directory
                    },
                    onOpenLocation: { [apiClient] location in
                        let resolved = apiClient.locations.first(where: { $0.id == location.id }) ?? location
                        selectedLocation = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocationDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        directorySelectedRaw = DirectorySubmodule.locations.rawValue
                        selectedSection = .directory
                    },
                    onOpenLicense: { [apiClient] license in
                        let resolved = apiClient.licenses.first(where: { $0.id == license.id }) ?? license
                        selectedLicense = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedLicenseDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .licenses
                    },
                    onOpenAccessory: { [apiClient] accessory in
                        let resolved = apiClient.accessories.first(where: { $0.id == accessory.id }) ?? accessory
                        selectedAccessory = resolved
                        selectedAsset = nil
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAccessoryDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .accessories
                    },
                    onOpenComponent: { [apiClient] component in
                        let resolved = apiClient.components.first(where: { $0.id == component.id }) ?? component
                        selectedComponent = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedComponentDetailTab = 0
                        stockSelectedRaw = StockSubmodule.components.rawValue
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .stock
                    },
                    onOpenAsset: { [apiClient] target in
                        let resolved = apiClient.assets.first(where: { $0.id == target.id }) ?? target
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAssetDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .hardware
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
                        selectedLicense = nil
                        selectedLocation = nil
                        selectedUserDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        directorySelectedRaw = DirectorySubmodule.users.rawValue
                        selectedSection = .directory
                    },
                    onOpenAsset: { [apiClient] asset in
                        let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedLicense = nil
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
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocationDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        directorySelectedRaw = DirectorySubmodule.locations.rawValue
                        selectedSection = .directory
                    }
                )
            } else {
                ContentUnavailableView(
                    L10n.string("select_accessory"),
                    systemImage: "mediastick",
                    description: Text("Choose an accessory from the list")
                )
            }
        case .licenses:
            if let license = selectedLicense {
                LicenseDetailView(
                    license: license,
                    apiClient: apiClient,
                    selectedTab: $selectedLicenseDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { [apiClient] user in
                        let resolved = apiClient.users.first(where: { $0.id == user.id }) ?? user
                        selectedUser = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLicense = nil
                        selectedLocation = nil
                        selectedUserDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        directorySelectedRaw = DirectorySubmodule.users.rawValue
                        selectedSection = .directory
                    },
                    onOpenAsset: { [apiClient] asset in
                        let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAssetDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .hardware
                    }
                )
            } else {
                ContentUnavailableView(
                    L10n.string("select_license"),
                    systemImage: "doc.text.fill",
                    description: Text("Choose a license from the list")
                )
            }
        case .stock:
            if stockSelectedSubmodule == .consumables {
                if let consumable = selectedConsumable {
                    ConsumableDetailView(
                        consumable: consumable,
                        apiClient: apiClient,
                        selectedTab: $selectedConsumableDetailTab,
                        isDetailViewActive: $isDetailViewActive,
                        onOpenUser: { [apiClient] user in
                            let resolved = apiClient.users.first(where: { $0.id == user.id }) ?? user
                            selectedUser = resolved
                            selectedAsset = nil
                            selectedAccessory = nil
                            selectedLicense = nil
                            selectedConsumable = nil
                            selectedLocation = nil
                            selectedUserDetailTab = 0
                            skipClearSelectionOnSectionChange = true
                            directorySelectedRaw = DirectorySubmodule.users.rawValue
                            selectedSection = .directory
                        }
                    )
                } else {
                    ContentUnavailableView(
                        L10n.string("select_consumable"),
                        systemImage: "shippingbox",
                        description: Text(L10n.string("select_consumable_desc"))
                    )
                }
            } else if stockSelectedSubmodule == .components {
                if let component = selectedComponent {
                    ComponentDetailView(
                        component: component,
                        apiClient: apiClient,
                        selectedTab: $selectedComponentDetailTab,
                        isDetailViewActive: $isDetailViewActive,
                        onOpenAsset: { [apiClient] asset in
                            let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                            selectedAsset = resolved
                            selectedAccessory = nil
                            selectedLicense = nil
                            selectedConsumable = nil
                            selectedComponent = nil
                            selectedUser = nil
                            selectedLocation = nil
                            selectedAssetDetailTab = 0
                            skipClearSelectionOnSectionChange = true
                            selectedSection = .hardware
                        }
                    )
                } else {
                    ContentUnavailableView(
                        L10n.string("select_component"),
                        systemImage: "cpu",
                        description: Text(L10n.string("select_component_desc"))
                    )
                }
            } else {
                ContentUnavailableView(
                    stockSelectedSubmodule.localizedTitle,
                    systemImage: stockSelectedSubmodule.icon,
                    description: Text(L10n.string("module_coming_soon"))
                )
            }
        case .directory:
            ipadDirectoryDetail
        }
    }

    @ViewBuilder
    private var ipadDirectoryDetail: some View {
        switch directorySelectedSubmodule {
        case .users:
            if let user = selectedUser {
                UserDetailView(
                    user: user,
                    apiClient: apiClient,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenAsset: { [apiClient] asset in
                        let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedLicense = nil
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
                        selectedLicense = nil
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
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocationDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        directorySelectedRaw = DirectorySubmodule.locations.rawValue
                    },
                    onOpenLicense: { [apiClient] license in
                        let resolved = apiClient.licenses.first(where: { $0.id == license.id }) ?? license
                        selectedLicense = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedLicenseDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .licenses
                    },
                    onOpenConsumable: { [apiClient] consumable in
                        let resolved = apiClient.consumables.first(where: { $0.id == consumable.id }) ?? consumable
                        selectedConsumable = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedConsumableDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        stockSelectedRaw = StockSubmodule.consumables.rawValue
                        selectedSection = .stock
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
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { [apiClient] user in
                        let resolved = apiClient.users.first(where: { $0.id == user.id }) ?? user
                        selectedUser = resolved
                        selectedAsset = nil
                        selectedAccessory = nil
                        selectedLicense = nil
                        selectedLocation = nil
                        selectedUserDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        directorySelectedRaw = DirectorySubmodule.users.rawValue
                    },
                    onOpenAsset: { [apiClient] asset in
                        let resolved = apiClient.assets.first(where: { $0.id == asset.id }) ?? asset
                        selectedAsset = resolved
                        selectedAccessory = nil
                        selectedLicense = nil
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
                        selectedLicense = nil
                        selectedUser = nil
                        selectedLocation = nil
                        selectedAccessoryDetailTab = 0
                        skipClearSelectionOnSectionChange = true
                        selectedSection = .accessories
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
    private var ipadDirectoryList: some View {
        switch directorySelectedSubmodule {
        case .users: ipadUserList
        case .locations: ipadLocationList
        }
    }

    // Don't show the loader if the active section already has cached rows.
    private var currentSectionListIsEmpty: Bool {
        switch selectedSection {
        case .hardware: return apiClient.assets.isEmpty
        case .accessories: return apiClient.accessories.isEmpty
        case .licenses: return apiClient.licenses.isEmpty
        case .stock:
            return stockSelectedSubmodule == .consumables
                ? apiClient.consumables.isEmpty
                : apiClient.components.isEmpty
        case .directory:
            return directorySelectedSubmodule == .users
                ? apiClient.users.isEmpty
                : apiClient.locations.isEmpty
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
            } else if apiClient.isLoading && !isRefreshing && currentSectionListIsEmpty {
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
                case .licenses:
                    ipadLicenseList
                case .stock:
                    if stockSelectedSubmodule == .consumables {
                        ipadConsumableList
                    } else if stockSelectedSubmodule == .components {
                        ipadComponentList
                    } else {
                        ContentUnavailableView(
                            stockSelectedSubmodule.localizedTitle,
                            systemImage: stockSelectedSubmodule.icon,
                            description: Text(L10n.string("module_coming_soon"))
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .directory:
                    ipadDirectoryList
                }
            }
        }
    }

    @ViewBuilder
    private func ipadAssetRow(_ asset: Asset) -> some View {
        let isSelected = selectedAsset?.id == asset.id
        let canMarkAuditCompleted = enableAuditSubtab && hardwareSubtab == .audit && (AuditDateClassifier.isDueToday(asset, now: Date()) || AuditDateClassifier.isOverdue(asset, now: Date()))

        Button {
            selectedAsset = asset
        } label: {
            AssetCardView(
                asset: asset,
                useExplicitBackground: true,
                showNextAuditDate: enableAuditSubtab && hardwareSubtab == .audit
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if canMarkAuditCompleted {
                Button {
                    auditCompletionAsset = asset
                    auditCompletionNextAuditDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
                    showAuditCompletionSheet = true
                } label: {
                    Label(L10n.string("audit_completed_action"), systemImage: "checkmark.seal")
                }
                .tint(.purple)
            }
        }
    }

    private var ipadAssetList: some View {
        VStack(spacing: 0) {
            if enableAuditSubtab {
                Picker(selection: $hardwareSubtab, label: Text("Hardware")) {
                    Text(L10n.string("tab_hardware")).tag(HardwareAuditSubtab.all)
                    Text(L10n.string("audit")).tag(HardwareAuditSubtab.audit)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 2)
                .padding(.bottom, 0)
                .onChange(of: hardwareSubtab) { _, newValue in
                    if newValue == .all {
                        showTodayOnlyOverride = false
                        auditListFilter = .all
                    }
                }
            }

            List {
                // Audit subtab: today + upcoming audits.
                if enableAuditSubtab, hardwareSubtab == .audit {
                    switch auditListFilter {
                    case .dueToday:
                        if !dueTodayAssets.isEmpty {
                            Section(header: Text(L10n.string("audit_due_today_header", dueTodayAssets.count))) {
                                ForEach(dueTodayAssets) { asset in
                                    ipadAssetRow(asset)
                                }
                            }
                        }

                    case .dueSoon:
                        if !dueSoonAssets.isEmpty {
                            Section(
                                header: VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.string("audit_due_soon_header", dueSoonAssets.count))
                                    Text(L10n.string("audit_due_soon_within_days", dueSoonDays))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            ) {
                                ForEach(dueSoonAssets) { asset in
                                    ipadAssetRow(asset)
                                }
                            }
                        }

                    case .all:
                        if !overdueAssets.isEmpty {
                            Section(
                                header: Button {
                                    isOverdueExpanded.toggle()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isOverdueExpanded ? "chevron.down" : "chevron.right")
                                            .foregroundStyle(.secondary)
                                        Text(L10n.string("audit_overdue_header", overdueAssets.count))
                                    }
                                }
                                .buttonStyle(.plain)
                            ) {
                                if isOverdueExpanded {
                                    ForEach(overdueAssets) { asset in
                                        ipadAssetRow(asset)
                                    }
                                }
                            }
                        }
                        if !dueTodayAssets.isEmpty {
                            Section(header: Text(L10n.string("audit_due_today_header", dueTodayAssets.count))) {
                                ForEach(dueTodayAssets) { asset in
                                    ipadAssetRow(asset)
                                }
                            }
                        }
                        if !dueSoonAssets.isEmpty {
                            Section(
                                header: VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.string("audit_due_soon_header", dueSoonAssets.count))
                                    Text(L10n.string("audit_due_soon_within_days", dueSoonDays))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            ) {
                                ForEach(dueSoonAssets) { asset in
                                    ipadAssetRow(asset)
                                }
                            }
                        }
                    }
                } else {
                    let assetsToShow = showTodayOnlyOverride ? dueTodayAssets : filteredAssets
                    if !assetsToShow.isEmpty {
                        ForEach(assetsToShow) { asset in
                            ipadAssetRow(asset)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(0)
            .listSectionSeparator(.hidden)
            .overlay {
                let isRelevantAssetsEmpty: Bool = {
                    if enableAuditSubtab && hardwareSubtab == .audit {
                        switch auditListFilter {
                        case .dueToday: return dueTodayAssets.isEmpty
                        case .dueSoon: return dueSoonAssets.isEmpty
                        case .all: return dueTodayAssets.isEmpty && dueSoonAssets.isEmpty && overdueAssets.isEmpty
                        }
                    } else {
                        return (showTodayOnlyOverride ? dueTodayAssets.isEmpty : filteredAssets.isEmpty)
                    }
                }()

                if isRelevantAssetsEmpty && apiClient.isConfigured && !apiClient.isLoading && apiClient.hasCompletedInitialLoad {
                    ContentUnavailableView(
                        searchText.isEmpty ? L10n.string("no_assets") : L10n.string("no_assets_match"),
                        systemImage: "laptopcomputer"
                    )
                }
            }
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    await apiClient.fetchAssets()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
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
                await apiClient.fetchAccessories()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private var ipadLicenseList: some View {
        List {
            ForEach(filteredLicenses) { license in
                let isSelected = selectedLicense?.id == license.id
                Button {
                    selectedLicense = license
                } label: {
                    LicenseCardView(license: license, useExplicitBackground: true)
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
            if filteredLicenses.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_licenses"), systemImage: "doc.text.fill")
            }
        }
        .refreshable {
            if apiClient.isConfigured {
                isRefreshing = true
                await apiClient.fetchLicenses()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private var ipadConsumableList: some View {
        List {
            ForEach(filteredConsumables) { consumable in
                let isSelected = selectedConsumable?.id == consumable.id
                Button {
                    selectedConsumable = consumable
                } label: {
                    ConsumableCardView(consumable: consumable, useExplicitBackground: true)
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
            if filteredConsumables.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_consumables"), systemImage: "shippingbox")
            }
        }
        .refreshable {
            if apiClient.isConfigured {
                isRefreshing = true
                await apiClient.fetchConsumables()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private var ipadComponentList: some View {
        List {
            ForEach(filteredComponents) { component in
                let isSelected = selectedComponent?.id == component.id
                Button {
                    selectedComponent = component
                } label: {
                    ComponentCardView(component: component, useExplicitBackground: true)
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
            if filteredComponents.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_components"), systemImage: "cpu")
            }
        }
        .refreshable {
            if apiClient.isConfigured {
                isRefreshing = true
                await apiClient.fetchComponents()
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
                await apiClient.fetchUsers()
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
                await apiClient.fetchLocations()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
    }

    private func handleScanResult(_ result: Result<ScanResult, ScanError>) {
        showScanner = false
        switch result {
        case .success(let scanResult):
            apiClient.errorMessage = nil
            let scannedValue = scanResult.string.trimmingCharacters(in: .whitespacesAndNewlines)

            func findAsset(for value: String) -> Asset? {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { return nil }

                return apiClient.assets.first(where: { asset in
                    asset.decodedAssetTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized ||
                    asset.decodedSerial.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized ||
                    (asset.altBarcode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "") == normalized
                })
            }

            func extractAssetTagFromByTagURL(from url: URL) -> String? {
                guard url.path.lowercased().contains("/hardware/bytag") else { return nil }
                guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
                let item = components.queryItems?.first(where: { name in
                    name.name == "assetTag" || name.name == "asset_tag"
                })
                return item?.value
            }

            @MainActor
            func openHardwareForScannedValueByTag(_ value: String) async {
                let asset = await apiClient.fetchHardwareByTag(assetTag: value)
                if let asset {
                    // Patch cache so navigation can resolve the asset.
                    if let idx = apiClient.assets.firstIndex(where: { $0.id == asset.id }) {
                        apiClient.assets[idx] = asset
                    } else {
                        apiClient.assets.append(asset)
                    }
                    scannedAssetId = asset.id
                    selectedSection = .hardware
                } else {
                    scannedAssetId = nil
                    scanErrorMessage = L10n.string("asset_not_found_scanned_value", value)
                    showScanErrorAlert = true
                }
            }

            // Only QR codes carry a Snipe-IT URL with an internal asset id. A 1D barcode is
            // the asset tag verbatim, so it must not be parsed as a URL/number (which would
            // strip leading zeros); it falls through to the literal tag lookup below.
            if scanResult.type == .qr, let url = URL(string: scannedValue) {
                // Snipe-IT QR
                if let id = extractAssetId(from: url) {
                    if let asset = apiClient.assets.first(where: { $0.id == id }) {
                        scannedAssetId = asset.id
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

                // Dell QR. Look up by serial.
                if enableDellQrScan,
                   let host = url.host, host.lowercased().contains("dell"),
                   let serial = SnipeITAPIClient.extractDellServiceTag(from: url), !serial.isEmpty {
                    let normalized = serial.trimmingCharacters(in: .whitespaces).lowercased()

                    if let asset = apiClient.assets.first(where: {
                        $0.decodedSerial.trimmingCharacters(in: .whitespaces).lowercased() == normalized
                    }) {
                        scannedAssetId = asset.id
                        selectedSection = .hardware
                    } else if apiClient.assets.isEmpty {
                        Task {
                            await apiClient.fetchPrimaryThenBackground()
                            await MainActor.run {
                                if let asset = findAsset(for: normalized) {
                                    scannedAssetId = asset.id
                                    selectedSection = .hardware
                                } else {
                                    scannedAssetId = nil
                                    promptAddDellAsset(url: url, serial: serial)
                                }
                            }
                        }
                    } else {
                        scannedAssetId = nil
                        promptAddDellAsset(url: url, serial: serial)
                    }
                    return
                }

                // bytag URL: https://.../hardware/bytag?assetTag=XYZ
                if let assetTag = extractAssetTagFromByTagURL(from: url) {
                    Task {
                        let asset = await apiClient.fetchHardwareByTag(assetTag: assetTag)
                        await MainActor.run {
                            if let asset {
                                // Patch cache so navigation can resolve the asset.
                                if let idx = apiClient.assets.firstIndex(where: { $0.id == asset.id }) {
                                    apiClient.assets[idx] = asset
                                } else {
                                    apiClient.assets.append(asset)
                                }
                                scannedAssetId = asset.id
                                selectedSection = .hardware
                            } else {
                                scannedAssetId = nil
                                scanErrorMessage = L10n.string("asset_not_found_scanned_value", assetTag)
                                showScanErrorAlert = true
                            }
                        }
                    }
                    return
                }

                scanErrorMessage = L10n.string("invalid_qr_no_asset_id")
                showScanErrorAlert = true
                return
            }

            // 1D barcode: match raw value against assetTag/serial/altBarcode.
            if let asset = findAsset(for: scannedValue) {
                scannedAssetId = asset.id
                selectedSection = .hardware
                return
            } else {
                Task {
                    await openHardwareForScannedValueByTag(scannedValue)
                }
                return
            }
        case .failure(let error):
            scanErrorMessage = String(format: L10n.string("scan_failed"), error.localizedDescription)
            showScanErrorAlert = true
        }
    }

    private func promptAddDellAsset(url: URL, serial: String) {
        pendingDellURLForAdd = url
        pendingDellSerial = serial
        showAddDellAssetPrompt = true
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

