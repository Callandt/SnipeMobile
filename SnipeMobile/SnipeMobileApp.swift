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
    @AppStorage("showMaintenance") private var showMaintenance: Bool = true
    @AppStorage("auditNotificationsEnabled") private var auditNotificationsEnabled: Bool = false
    @AppStorage("auditNotificationHour") private var auditNotificationHour: Int = 9
    @AppStorage("auditNotificationMinute") private var auditNotificationMinute: Int = 0
    private let dueSoonDays: Int = 7

    // Audit completion sheet (iPad list quick action).
    @State private var showAuditCompletionSheet = false
    @State private var auditCompletionAsset: Asset?
    @State private var auditCompletionNextAuditDate: Date = Date()
    @State private var auditCompletionSetDate = true
    @State private var auditCompletionNote = ""
    @State private var isSavingAuditCompletion = false
    @State private var showAuditCompletionErrorAlert = false
    @State private var auditCompletionErrorMessage = ""
    @State private var isOverdueExpanded = false

    // Cross-asset maintenance overview (Hardware → Maintenance subtab).
    // The records live in the cached `apiClient.maintenances` list.
    @State private var isLoadingMaintenances = false
    @State private var maintenanceError: String? = nil
    @State private var maintenanceLoadedOnce = false
    @State private var selectedMaintenance: AssetMaintenance? = nil
    @State private var selectedAuditAsset: Asset? = nil
    @State private var showAddMaintenance = false
    @State private var showBulkAudit = false
    @State private var showBulkLabels = false
    @State private var isSelectingMaintenances = false
    @State private var selectedMaintenanceIds: Set<Int> = []
    @State private var maintenanceFilter: MaintenanceStatusFilter = .all

    // Quick swipe-to-complete from the maintenance overview.
    @State private var maintenanceToComplete: AssetMaintenance?
    @State private var maintenanceCompleteNote = ""
    @State private var isCompletingMaintenanceSwipe = false
    @State private var showMaintenanceCompleteError = false
    @State private var maintenanceCompleteErrorMessage = ""

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

    private var isMaintenanceSubtabActive: Bool {
        showMaintenance && hardwareSubtab == .maintenance
    }

    private var isAuditSubtabActive: Bool {
        enableAuditSubtab && hardwareSubtab == .audit
    }

    private var auditOverviewCount: Int {
        switch auditListFilter {
        case .dueToday: return dueTodayAssets.count
        case .dueSoon: return dueSoonAssets.count
        case .all: return dueTodayAssets.count + dueSoonAssets.count + overdueAssets.count
        }
    }

    private var showSubtabPicker: Bool {
        enableAuditSubtab || showMaintenance
    }

    private var displayedMaintenances: [AssetMaintenance] {
        var records = apiClient.maintenances.filter { maintenanceFilter.matches($0) }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            records = records.filter {
                $0.decodedTitle.lowercased().contains(q) ||
                ($0.displayType?.lowercased().contains(q) ?? false) ||
                ($0.assetDisplayLabel?.lowercased().contains(q) ?? false)
            }
        }
        return records
    }

    private var selectableMaintenances: [AssetMaintenance] {
        MaintenanceBulkCompleter.inProgress(from: displayedMaintenances)
    }

    private func loadAllMaintenances(force: Bool = false) async {
        guard apiClient.isConfigured else { return }
        if isLoadingMaintenances { return }
        if !force && maintenanceLoadedOnce { return }
        isLoadingMaintenances = true
        maintenanceError = nil
        let fetched = await apiClient.fetchAllMaintenances()
        isLoadingMaintenances = false
        maintenanceLoadedOnce = true
        if fetched == nil {
            maintenanceError = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
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

    private var maintenanceFilterMenu: some View {
        Group {
            if MaintenanceStatusFilter.hasChoices(in: apiClient.maintenances) {
                Menu {
                    Picker(L10n.string("filter"), selection: $maintenanceFilter) {
                        ForEach(MaintenanceStatusFilter.available(in: apiClient.maintenances)) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(maintenanceFilter.localizedTitle)
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // Count row at the top of each iPad list, like on iPhone.
    @ViewBuilder
    private func ipadCountHeader(count: Int, icon: String, trailing: String? = nil) -> some View {
        Section {
            HStack {
                Label("\(count)", systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
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
            // Keep detail content at a readable width on wide iPads.
            ipadDetailContent
                .frame(maxWidth: 760, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).ignoresSafeArea())
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
        .sheet(isPresented: $showAddMaintenance, onDismiss: {
            Task { await loadAllMaintenances(force: true) }
        }) {
            BulkMaintenanceFormSheet(apiClient: apiClient)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showBulkAudit) {
            BulkAuditView(apiClient: apiClient, onSave: {
                if auditNotificationsEnabled {
                    Task {
                        await AuditNotificationManager.shared.updateSchedule(
                            enabled: true,
                            hour: auditNotificationHour,
                            minute: auditNotificationMinute,
                            assets: apiClient.assets
                        )
                    }
                }
            })
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showBulkLabels) {
            BulkLabelView(apiClient: apiClient)
                .presentationDetents([.large])
        }
        .sheet(item: $selectedMaintenance, onDismiss: {
            Task { await loadAllMaintenances(force: true) }
        }) { record in
            MaintenanceDetailSheet(
                apiClient: apiClient,
                assetId: record.assetId ?? 0,
                record: record,
                onMutated: {}
            )
            .presentationDetents([.large])
        }
        .sheet(item: $selectedAuditAsset) { asset in
            AuditDetailSheet(apiClient: apiClient, asset: asset, onCompleted: {
                if auditNotificationsEnabled {
                    Task {
                        await AuditNotificationManager.shared.updateSchedule(
                            enabled: true,
                            hour: auditNotificationHour,
                            minute: auditNotificationMinute,
                            assets: apiClient.assets
                        )
                    }
                }
            })
            .presentationDetents([.large])
        }
        .sheet(item: $maintenanceToComplete) { record in
            CompletionActionSheet(
                title: L10n.string("mark_complete_confirm_title"),
                message: L10n.string("mark_complete_confirm_message"),
                note: $maintenanceCompleteNote,
                confirmTitle: L10n.string("mark_complete"),
                isSaving: isCompletingMaintenanceSwipe,
                onSave: { Task { await completeMaintenanceFromSwipe(record) } }
            )
        }
        .alert(L10n.string("error"), isPresented: $showMaintenanceCompleteError) {
            Button(L10n.string("ok"), role: .cancel) { maintenanceCompleteErrorMessage = "" }
        } message: {
            Text(maintenanceCompleteErrorMessage)
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
        .sheet(isPresented: $showScanner) {
            ZoomableQRScannerView(
                completion: handleScanResult,
                supportedTypes: [.qr, .dataMatrix, .code39, .code128, .ean13, .upce]
            )
        }
        .sheet(isPresented: $showAuditCompletionSheet) {
            CompletionActionSheet(
                title: L10n.string("complete_audit_confirm_title"),
                message: L10n.string("complete_audit_confirm_message"),
                dateLabel: L10n.string("next_audit_date"),
                date: $auditCompletionNextAuditDate,
                includeDate: $auditCompletionSetDate,
                includeDateLabel: L10n.string("audit_set_next_audit_date"),
                note: $auditCompletionNote,
                confirmTitle: L10n.string("complete_audit"),
                isSaving: isSavingAuditCompletion,
                onSave: { Task { await saveAuditCompletionForIpad() } }
            )
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
        .onChange(of: apiClient.assets.count) { _, _ in
            if awaitingAuditNavigationResolution {
                tryResolveAndOpenAuditTarget()
            }
        }
    }

    private var settingsSheet: some View {
        SettingsView(apiClient: apiClient)
            .preferredColorScheme(
                appSettings.appTheme == "light" ? .light :
                appSettings.appTheme == "dark" ? .dark : nil
            )
    }

    private func saveAuditCompletionForIpad() async {
        guard !isSavingAuditCompletion, let asset = auditCompletionAsset else { return }
        let tag = asset.decodedAssetTag
        guard !tag.isEmpty else {
            auditCompletionErrorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showAuditCompletionErrorAlert = true
            return
        }

        isSavingAuditCompletion = true
        defer { isSavingAuditCompletion = false }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let nextAuditStr = auditCompletionSetDate ? formatter.string(from: auditCompletionNextAuditDate) : nil
        let noteOpt = auditCompletionNote.trimmingCharacters(in: .whitespaces).isEmpty ? nil : auditCompletionNote

        let ok = await apiClient.auditAsset(
            assetTag: tag,
            assetId: asset.id,
            nextAuditDate: nextAuditStr,
            note: noteOpt
        )
        if ok {
            showAuditCompletionSheet = false
            auditCompletionAsset = nil
            auditCompletionNote = ""
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

    // Single-selection binding; selectedSection is non-optional.
    private var sidebarSelection: Binding<MainTab?> {
        Binding(
            get: { selectedSection },
            set: { if let value = $0 { selectedSection = value } }
        )
    }

    private var ipadSidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                Button {
                    showScanner = true
                } label: {
                    Label(L10n.string("scan_qr"), systemImage: "qrcode.viewfinder")
                }
            }

            Section {
                ForEach(orderedVisibleSections, id: \.self) { section in
                    Label(sectionTitle(section), systemImage: sectionIcon(section))
                        .tag(section)
                }
            }

            Section {
                Button {
                    showSettings = true
                } label: {
                    Label(L10n.string("settings"), systemImage: "gearshape")
                }
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
                        if isMaintenanceSubtabActive && isSelectingMaintenances {
                            EmptyView()
                        } else if showMaintenance || enableAuditSubtab {
                            Menu {
                                Button(action: { showAddAsset = true }) {
                                    Label(L10n.string("add_asset"), systemImage: "laptopcomputer")
                                }
                                if showMaintenance {
                                    Button(action: { showAddMaintenance = true }) {
                                        Label(L10n.string("add_maintenance"), systemImage: "wrench.and.screwdriver")
                                    }
                                }
                                if enableAuditSubtab {
                                    Button(action: { showBulkAudit = true }) {
                                        Label(L10n.string("add_audit"), systemImage: "checklist")
                                    }
                                }
                                Button(action: { showBulkLabels = true }) {
                                    Label(L10n.string("generate_labels"), systemImage: "tag")
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .accessibilityLabel(L10n.string("add"))
                        } else {
                            Menu {
                                Button(action: { showAddAsset = true }) {
                                    Label(L10n.string("add_asset"), systemImage: "laptopcomputer")
                                }
                                Button(action: { showBulkLabels = true }) {
                                    Label(L10n.string("generate_labels"), systemImage: "tag")
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .accessibilityLabel(L10n.string("add"))
                        }
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
            .maintenanceBulkSelection(
                isActive: selectedSection == .hardware && isMaintenanceSubtabActive,
                selectableRecords: selectableMaintenances,
                apiClient: apiClient,
                isSelecting: $isSelectingMaintenances,
                selectedIds: $selectedMaintenanceIds,
                onRefresh: { await loadAllMaintenances(force: true) }
            )
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
                    description: Text(L10n.string("select_asset_desc"))
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
                    description: Text(L10n.string("select_accessory_desc"))
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
                    description: Text(L10n.string("select_license_desc"))
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
                    description: Text(L10n.string("select_user_desc"))
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
                    description: Text(L10n.string("select_location_desc"))
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
        let isAuditTabActive = enableAuditSubtab && hardwareSubtab == .audit
        let canMarkAuditCompleted = isAuditTabActive && (AuditDateClassifier.isDueToday(asset, now: Date()) || AuditDateClassifier.isOverdue(asset, now: Date()))

        Button {
            if isAuditTabActive {
                selectedAuditAsset = asset
            } else {
                selectedAsset = asset
            }
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
                    auditCompletionNextAuditDate = AuditDateClassifier.nextAuditDateGMT(asset) ?? Date()
                    auditCompletionSetDate = true
                    auditCompletionNote = ""
                    showAuditCompletionSheet = true
                } label: {
                    Label(L10n.string("mark_complete"), systemImage: "checkmark.seal")
                }
                .tint(.green)
            }
        }
    }

    private var ipadAssetList: some View {
        VStack(spacing: 0) {
            if showSubtabPicker {
                Picker(selection: $hardwareSubtab, label: Text("Hardware")) {
                    Text(L10n.string("tab_hardware")).tag(HardwareAuditSubtab.all)
                    if enableAuditSubtab {
                        Text(L10n.string("audit")).tag(HardwareAuditSubtab.audit)
                    }
                    if showMaintenance {
                        Text(L10n.string("maintenance")).tag(HardwareAuditSubtab.maintenance)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 2)
                .padding(.bottom, 0)
                .onChange(of: hardwareSubtab) { _, newValue in
                    if newValue == .all {
                        showTodayOnlyOverride = false
                        auditListFilter = .all
                    } else if newValue == .maintenance {
                        Task { await loadAllMaintenances() }
                    }
                }
            }

            List {
                if isMaintenanceSubtabActive {
                    Section {
                        HStack {
                            Label("\(displayedMaintenances.count)", systemImage: "wrench.and.screwdriver")
                                .foregroundStyle(.primary)
                            Spacer()
                            maintenanceFilterMenu
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                    Section {
                        ForEach(displayedMaintenances) { record in
                            ipadMaintenanceRow(record)
                        }
                    }
                } else {
                if isAuditSubtabActive {
                    ipadCountHeader(count: auditOverviewCount, icon: "checkmark.seal")
                } else {
                    ipadCountHeader(
                        count: apiClient.assets.count,
                        icon: "laptopcomputer",
                        trailing: L10n.string("assigned_count", apiClient.assets.filter { $0.assignedTo != nil }.count)
                    )
                }
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
            }
            .listStyle(.insetGrouped)
            .browseListBackground()
            .listSectionSpacing(0)
            .listSectionSeparator(.hidden)
            // Drop the list's default top inset so it sits under the picker.
            .contentMargins(.top, 0, for: .scrollContent)
            .overlay {
                if isMaintenanceSubtabActive {
                    if isLoadingMaintenances && apiClient.maintenances.isEmpty {
                        ProgressView(L10n.string("loading_maintenance"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else if let maintenanceError, apiClient.maintenances.isEmpty {
                        ContentUnavailableView(
                            L10n.string("error"),
                            systemImage: "exclamationmark.triangle",
                            description: Text(maintenanceError)
                        )
                    } else if displayedMaintenances.isEmpty {
                        ContentUnavailableView(
                            L10n.string("no_maintenance"),
                            systemImage: "wrench.and.screwdriver",
                            description: Text(L10n.string("no_maintenance_overview_desc"))
                        )
                    }
                } else {
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
            }
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    if isMaintenanceSubtabActive {
                        await loadAllMaintenances(force: true)
                    } else {
                        await apiClient.fetchAssets()
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .task(id: isMaintenanceSubtabActive) {
                if isMaintenanceSubtabActive {
                    await loadAllMaintenances()
                }
            }
        }
    }

    @ViewBuilder
    private func ipadMaintenanceRow(_ record: AssetMaintenance) -> some View {
        MaintenanceOverviewRow(
            record: record,
            linkedAsset: linkedAsset(for: record),
            isSelecting: isSelectingMaintenances,
            isSelected: selectedMaintenanceIds.contains(record.id),
            onTap: { handleMaintenanceOverviewTap(record) }
        )
        .foregroundStyle(.primary)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelectingMaintenances, !record.isCompleted {
                Button {
                    maintenanceCompleteNote = ""
                    maintenanceToComplete = record
                } label: {
                    Label(L10n.string("mark_complete"), systemImage: "checkmark.seal")
                }
                .tint(.green)
            }
        }
    }

    private func completeMaintenanceFromSwipe(_ record: AssetMaintenance) async {
        guard !isCompletingMaintenanceSwipe else { return }
        isCompletingMaintenanceSwipe = true
        defer { isCompletingMaintenanceSwipe = false }

        let trimmed = maintenanceCompleteNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed.isEmpty ? nil : trimmed
        let ok = await apiClient.completeMaintenance(id: record.id, note: note)
        maintenanceToComplete = nil
        if ok {
            await loadAllMaintenances(force: true)
        } else {
            maintenanceCompleteErrorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showMaintenanceCompleteError = true
        }
    }

    private func handleMaintenanceOverviewTap(_ record: AssetMaintenance) {
        if isSelectingMaintenances {
            guard !record.isCompleted else { return }
            if selectedMaintenanceIds.contains(record.id) {
                selectedMaintenanceIds.remove(record.id)
            } else {
                selectedMaintenanceIds.insert(record.id)
            }
        } else {
            selectedMaintenance = record
        }
    }

    private func linkedAsset(for record: AssetMaintenance) -> Asset? {
        guard let id = record.assetId else { return nil }
        return apiClient.assets.first { $0.id == id }
    }

    private var ipadAccessoryList: some View {
        List {
            ipadCountHeader(count: apiClient.accessories.count, icon: "mediastick")
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
        .browseListBackground()
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
            ipadCountHeader(count: apiClient.licenses.count, icon: "doc.text.fill")
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
        .browseListBackground()
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
            ipadCountHeader(count: apiClient.consumables.count, icon: "shippingbox")
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
        .browseListBackground()
        .listSectionSpacing(.compact)
        .listSectionSeparator(.hidden)
        .overlay {
            if filteredConsumables.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_consumables"), systemImage: "shippingbox")
            }
        }
        .onAppear {
            if apiClient.isConfigured && apiClient.consumables.isEmpty && !apiClient.isLoading {
                Task { await apiClient.fetchConsumables() }
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
            ipadCountHeader(count: apiClient.components.count, icon: "cpu")
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
        .browseListBackground()
        .listSectionSpacing(.compact)
        .listSectionSeparator(.hidden)
        .overlay {
            if filteredComponents.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                ContentUnavailableView(L10n.string("no_components"), systemImage: "cpu")
            }
        }
        .onAppear {
            // Self-heal if the shared initial sync skipped/failed the components page
            // (it's fetched last, so a transient hiccup can leave this list empty).
            if apiClient.isConfigured && apiClient.components.isEmpty && !apiClient.isLoading {
                Task { await apiClient.fetchComponents() }
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
            ipadCountHeader(count: apiClient.users.count, icon: "person.2")
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
        .browseListBackground()
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
            ipadCountHeader(count: apiClient.locations.count, icon: "mappin.and.ellipse")
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
        .browseListBackground()
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

            @MainActor
            func openHardwareForScannedValueByTag(_ value: String) async {
                let asset = await apiClient.fetchHardwareByTag(assetTag: value)
                if let asset {
                    if let idx = apiClient.assets.firstIndex(where: { $0.id == asset.id }) {
                        apiClient.assets[idx] = asset
                    } else {
                        apiClient.assets.append(asset)
                    }
                    selectedSection = .hardware
                    selectedAsset = asset
                    selectedAssetDetailTab = 0
                } else {
                    scanErrorMessage = L10n.string("asset_not_found_scanned_value", value)
                    showScanErrorAlert = true
                }
            }

            if scanResult.type == .qr, let url = URL(string: scannedValue) {
                if let link = SnipeITQRLink.parse(from: url) {
                    Task { await openSnipeITQRLink(link) }
                    return
                }

                if enableDellQrScan,
                   let host = url.host, host.lowercased().contains("dell"),
                   let serial = SnipeITAPIClient.extractDellServiceTag(from: url), !serial.isEmpty {
                    let normalized = serial.trimmingCharacters(in: .whitespaces).lowercased()

                    if let asset = apiClient.assets.first(where: {
                        $0.decodedSerial.trimmingCharacters(in: .whitespaces).lowercased() == normalized
                    }) {
                        selectedSection = .hardware
                        selectedAsset = asset
                        selectedAssetDetailTab = 0
                    } else if apiClient.assets.isEmpty {
                        Task {
                            await apiClient.fetchPrimaryThenBackground()
                            await MainActor.run {
                                if let asset = findAsset(for: normalized) {
                                    selectedSection = .hardware
                                    selectedAsset = asset
                                    selectedAssetDetailTab = 0
                                } else {
                                    promptAddDellAsset(url: url, serial: serial)
                                }
                            }
                        }
                    } else {
                        promptAddDellAsset(url: url, serial: serial)
                    }
                    return
                }

                scanErrorMessage = L10n.string("invalid_qr_unrecognized")
                showScanErrorAlert = true
                return
            }

            if let asset = findAsset(for: scannedValue) {
                selectedSection = .hardware
                selectedAsset = asset
                selectedAssetDetailTab = 0
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

    @MainActor
    private func openSnipeITQRLink(_ link: SnipeITQRLink) async {
        func clearNonHardwareSelection() {
            selectedAccessory = nil
            selectedLicense = nil
            selectedConsumable = nil
            selectedComponent = nil
        }

        switch link {
        case .hardwareByTag(let assetTag):
            let asset = await apiClient.fetchHardwareByTag(assetTag: assetTag)
            if let asset {
                if let idx = apiClient.assets.firstIndex(where: { $0.id == asset.id }) {
                    apiClient.assets[idx] = asset
                } else {
                    apiClient.assets.append(asset)
                }
                clearNonHardwareSelection()
                selectedSection = .hardware
                selectedAsset = asset
                selectedAssetDetailTab = 0
            } else {
                scanErrorMessage = L10n.string("asset_not_found_scanned_value", assetTag)
                showScanErrorAlert = true
            }

        case .hardware(let id):
            clearNonHardwareSelection()
            selectedSection = .hardware
            if apiClient.assets.first(where: { $0.id == id }) == nil, apiClient.assets.isEmpty {
                await apiClient.fetchPrimaryThenBackground()
            }
            if let asset = apiClient.assets.first(where: { $0.id == id }) {
                selectedAsset = asset
                selectedAssetDetailTab = 0
            } else if let detailed = await apiClient.fetchHardwareDetails(assetId: id) {
                apiClient.applyUpdatedAsset(detailed)
                selectedAsset = detailed
                selectedAssetDetailTab = 0
            } else {
                scanErrorMessage = link.notFoundMessage(id: id)
                showScanErrorAlert = true
            }

        case .component(let id):
            stockSelectedRaw = StockSubmodule.components.rawValue
            selectedAsset = nil
            selectedAccessory = nil
            selectedLicense = nil
            selectedConsumable = nil
            selectedSection = .stock
            if apiClient.components.first(where: { $0.id == id }) == nil, apiClient.components.isEmpty {
                await apiClient.fetchComponents()
            }
            if let component = apiClient.components.first(where: { $0.id == id }) {
                selectedComponent = component
                selectedComponentDetailTab = 0
            } else if let detailed = await apiClient.fetchComponentDetails(componentId: id) {
                apiClient.applyUpdatedComponent(detailed)
                selectedComponent = detailed
                selectedComponentDetailTab = 0
            } else {
                scanErrorMessage = link.notFoundMessage(id: id)
                showScanErrorAlert = true
            }

        case .consumable(let id):
            stockSelectedRaw = StockSubmodule.consumables.rawValue
            selectedAsset = nil
            selectedAccessory = nil
            selectedLicense = nil
            selectedComponent = nil
            selectedSection = .stock
            if apiClient.consumables.first(where: { $0.id == id }) == nil, apiClient.consumables.isEmpty {
                await apiClient.fetchConsumables()
            }
            if let consumable = apiClient.consumables.first(where: { $0.id == id }) {
                selectedConsumable = consumable
                selectedConsumableDetailTab = 0
            } else if let detailed = await apiClient.fetchConsumableDetails(consumableId: id) {
                apiClient.applyUpdatedConsumable(detailed)
                selectedConsumable = detailed
                selectedConsumableDetailTab = 0
            } else {
                scanErrorMessage = link.notFoundMessage(id: id)
                showScanErrorAlert = true
            }

        case .accessory(let id):
            selectedAsset = nil
            selectedLicense = nil
            selectedConsumable = nil
            selectedComponent = nil
            selectedSection = .accessories
            if apiClient.accessories.first(where: { $0.id == id }) == nil, apiClient.accessories.isEmpty {
                await apiClient.fetchAccessories()
            }
            if let accessory = apiClient.accessories.first(where: { $0.id == id }) {
                selectedAccessory = accessory
                selectedAccessoryDetailTab = 0
            } else if let detailed = await apiClient.fetchAccessoryDetails(accessoryId: id) {
                apiClient.applyUpdatedAccessory(detailed)
                selectedAccessory = detailed
                selectedAccessoryDetailTab = 0
            } else {
                scanErrorMessage = link.notFoundMessage(id: id)
                showScanErrorAlert = true
            }

        case .license(let id):
            selectedAsset = nil
            selectedAccessory = nil
            selectedConsumable = nil
            selectedComponent = nil
            selectedSection = .licenses
            if apiClient.licenses.first(where: { $0.id == id }) == nil, apiClient.licenses.isEmpty {
                await apiClient.fetchLicenses()
            }
            if let license = apiClient.licenses.first(where: { $0.id == id }) {
                selectedLicense = license
                selectedLicenseDetailTab = 0
            } else if let detailed = await apiClient.fetchLicenseDetails(licenseId: id) {
                apiClient.applyUpdatedLicense(detailed)
                selectedLicense = detailed
                selectedLicenseDetailTab = 0
            } else {
                scanErrorMessage = link.notFoundMessage(id: id)
                showScanErrorAlert = true
            }
        }
    }

    private func promptAddDellAsset(url: URL, serial: String) {
        pendingDellURLForAdd = url
        pendingDellSerial = serial
        showAddDellAssetPrompt = true
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

