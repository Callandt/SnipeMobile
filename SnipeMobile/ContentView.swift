import SwiftUI
import AVFoundation
import Foundation

// MARK: - Tab
enum MainTab: String, CaseIterable {
    case hardware = "Hardware"   // UI: Assets
    case accessories = "Accessories"
    case licenses = "Licenses"
    case stock = "Stock"         // consumables + components
    case directory = "Directory" // users + locations

    var localizedTitle: String {
        switch self {
        case .hardware: return L10n.string("tab_assets")
        case .accessories: return L10n.string("tab_accessories")
        case .licenses: return L10n.string("tab_licenses")
        case .stock: return L10n.string("tab_stock")
        case .directory: return L10n.string("tab_directory")
        }
    }

    var icon: String {
        switch self {
        case .hardware: return "laptopcomputer"
        case .accessories: return "mediastick"
        case .licenses: return "doc.text.fill"
        case .stock: return "shippingbox.fill"
        case .directory: return "person.2.crop.square.stack.fill"
        }
    }
}

enum StockSubmodule: String, CaseIterable, Identifiable {
    case consumables = "Consumables"
    case components = "Components"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .consumables: return L10n.string("tab_consumables")
        case .components: return L10n.string("tab_components")
        }
    }

    var icon: String {
        switch self {
        case .consumables: return "shippingbox.fill"
        case .components: return "cpu"
        }
    }
}

enum DirectorySubmodule: String, CaseIterable, Identifiable {
    case users = "Users"
    case locations = "Locations"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .users: return L10n.string("tab_users")
        case .locations: return L10n.string("tab_locations")
        }
    }

    var icon: String {
        switch self {
        case .users: return "person.2"
        case .locations: return "mappin.and.ellipse"
        }
    }
}

enum TabOrderStore {
    static let userDefaultsKey = "tabOrder"
    static let defaultOrder: [MainTab] = [
        .hardware, .accessories, .licenses, .stock, .directory,
    ]

    static func parse(_ raw: String) -> [MainTab] {
        let parsed = raw
            .split(separator: ",")
            .compactMap { MainTab(rawValue: String($0)) }
        let missing = defaultOrder.filter { !parsed.contains($0) }
        return parsed.isEmpty ? defaultOrder : parsed + missing
    }

    static func serialize(_ tabs: [MainTab]) -> String {
        tabs.map(\.rawValue).joined(separator: ",")
    }
}

enum AuditDateClassifier {
    private static let auditDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Treat date-only values as GMT to match Snipe-IT usage in the app.
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let gmtCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal
    }()

    static func nextAuditDateGMT(_ asset: Asset) -> Date? {
        guard let dateStr = asset.nextAuditDate?.date, !dateStr.isEmpty else { return nil }
        return auditDateFormatter.date(from: dateStr)
    }

    private static func auditDayStartGMT(for now: Date) -> Date {
        let todayStr = auditDateFormatter.string(from: now)
        // Parse again with the same formatter/tz (GMT) for consistency.
        return auditDateFormatter.date(from: todayStr) ?? now
    }

    static func isDueToday(_ asset: Asset, now: Date) -> Bool {
        guard let nextDate = nextAuditDateGMT(asset) else { return false }
        let todayStart = auditDayStartGMT(for: now)
        let tomorrowStart = gmtCalendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return nextDate >= todayStart && nextDate < tomorrowStart
    }

    static func isDueSoon(_ asset: Asset, now: Date, dueSoonDays: Int) -> Bool {
        guard dueSoonDays > 0 else { return false }
        guard let nextDate = nextAuditDateGMT(asset) else { return false }
        let todayStart = auditDayStartGMT(for: now)
        let start = gmtCalendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        // "Next N days" = tomorrow through (N-1) days later. With dueSoonDays=7: tomorrow..today+6.
        let endExclusive = gmtCalendar.date(byAdding: .day, value: dueSoonDays, to: todayStart) ?? start
        return nextDate >= start && nextDate < endExclusive
    }

    static func isOverdue(_ asset: Asset, now: Date) -> Bool {
        guard let nextDate = nextAuditDateGMT(asset) else { return false }
        let todayStart = auditDayStartGMT(for: now)
        return nextDate < todayStart
    }

    static func sortByNextAuditDateThenTag(_ assets: [Asset]) -> [Asset] {
        assets.sorted {
            let da = nextAuditDateGMT($0) ?? .distantFuture
            let db = nextAuditDateGMT($1) ?? .distantFuture
            if da == db { return $0.decodedAssetTag.lowercased() < $1.decodedAssetTag.lowercased() }
            return da < db
        }
    }
}

enum AuditListFilter: String {
    case all
    case dueToday
    case dueSoon
}

enum HardwareAuditSubtab: String {
    case all
    case audit
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
    @State private var accessoryDetailTab: Int = 0
    @State private var licenseDetailTab: Int = 0
    @State private var consumableDetailTab: Int = 0
    @State private var componentDetailTab: Int = 0
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject private var auditNotificationRouter: AuditNotificationRouter
    @State private var auditListFilter: AuditListFilter = .all
    @State private var hardwareSubtab: HardwareAuditSubtab = .all
    @State private var showTodayOnlyOverride = false
    @State private var showingSettings = false
    @State private var showingAddAsset = false
    @State private var showingAddAccessory = false
    @State private var pendingUserToOpen: User?
    @State private var pendingAssetToOpen: Asset?
    @State private var pendingLocationToOpen: Location?
    @State private var pendingAccessoryToOpen: Accessory?
    @State private var pendingLicenseToOpen: License?
    @State private var pendingConsumableToOpen: Consumable?
    @State private var pendingComponentToOpen: Component?
    @State private var returnToTab: MainTab?
    @State private var hardwarePath = NavigationPath()
    @State private var accessoriesPath = NavigationPath()
    @State private var licensesPath = NavigationPath()
    @State private var stockPath = NavigationPath()
    @State private var directoryPath = NavigationPath()
    /// Detail on stack. Tab bar stays visible.
    @State private var isDetailViewActive = false
    @State private var showScanErrorAlert = false
    @State private var scanErrorMessage: String?
    @State private var showAddDellAssetPrompt = false
    @State private var pendingDellURLForAdd: URL?
    @State private var pendingDellSerial: String?
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true
    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = false
    @AppStorage("showAccessoriesTab") private var showAccessoriesTab: Bool = true
    @AppStorage("showLicensesTab") private var showLicensesTab: Bool = true
    @AppStorage("showConsumablesTab") private var showConsumablesSub: Bool = true
    @AppStorage("showComponentsTab") private var showComponentsSub: Bool = true
    @State private var awaitingAuditNavigationResolution = false
    @State private var auditNotificationNavResolved = false

    private var orderedVisibleTabs: [MainTab] {
        TabOrderStore.defaultOrder.filter(isTabVisible)
    }

    private var enabledStockSubmodules: [StockSubmodule] {
        var subs: [StockSubmodule] = []
        if showConsumablesSub { subs.append(.consumables) }
        if showComponentsSub { subs.append(.components) }
        return subs
    }

    // Stock tab label/icon follows the sole enabled submodule when only one is on.
    private func displayTitle(for tab: MainTab) -> String {
        switch tab {
        case .stock where enabledStockSubmodules.count == 1:
            return enabledStockSubmodules[0].localizedTitle
        default:
            return tab.localizedTitle
        }
    }

    private func displayIcon(for tab: MainTab) -> String {
        switch tab {
        case .stock where enabledStockSubmodules.count == 1:
            return enabledStockSubmodules[0].icon
        default:
            return tab.icon
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(orderedVisibleTabs, id: \.self) { tab in
                tabView(for: tab)
                    .tag(tab)
                    .tabItem { Label(displayTitle(for: tab), systemImage: displayIcon(for: tab)) }
            }
        }
        #if os(iOS)
        .tabViewStyle(.automatic)
        #endif
        .onChange(of: showAccessoriesTab) { _, _ in resetSelectedTabIfHidden() }
        .onChange(of: showLicensesTab) { _, _ in resetSelectedTabIfHidden() }
        .onChange(of: showConsumablesSub) { _, _ in resetSelectedTabIfHidden() }
        .onChange(of: showComponentsSub) { _, _ in resetSelectedTabIfHidden() }
        .onChange(of: selectedTab) { _, newTab in
            // Reset search
            searchText = ""
            // Tab state from visible view
            isDetailViewActive = false
            // Back to list only on tab tap. Programmatic nav keeps path.
            guard returnToTab == nil else { return }
            if !awaitingAuditNavigationResolution {
                auditListFilter = .all
                showTodayOnlyOverride = false
                hardwareSubtab = .all
            }
            switch newTab {
            case .hardware: hardwarePath = NavigationPath()
            case .accessories: accessoriesPath = NavigationPath()
            case .directory: directoryPath = NavigationPath()
            case .stock: stockPath = NavigationPath()
            case .licenses:
                break
            }
        }
        .modifier(TabBarMinimizeBehaviorModifier(isDetailVisible: isDetailViewActive))
        .sheet(isPresented: $showingScanner, onDismiss: {
            selectedTab = .hardware
        }) {
            ZoomableQRScannerView(
                completion: handleScanResult,
                supportedTypes: [.qr, .dataMatrix, .code39, .code128, .ean13, .upce]
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(apiClient: apiClient)
                .preferredColorScheme(
                    appSettings.appTheme == "light" ? .light :
                    appSettings.appTheme == "dark" ? .dark : nil
                )
        }
        .sheet(isPresented: $showingAddAsset, onDismiss: {
            pendingDellURLForAdd = nil
            pendingDellSerial = nil
        }) {
            AddAssetSheet(
                apiClient: apiClient,
                isPresented: $showingAddAsset,
                prefilledDellURL: pendingDellURLForAdd,
                prefilledSerial: pendingDellSerial
            )
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
                showingAddAsset = true
            }
        } message: {
            if let s = pendingDellSerial {
                Text(L10n.string("dell_asset_not_found_message", s))
            }
        }
        .sheet(isPresented: $showingAddAccessory) {
            AddAccessorySheet(apiClient: apiClient, isPresented: $showingAddAccessory)
        }
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

            // Cold boot: `pendingRequest` may already be set before `onChange` fires.
            if auditNotificationRouter.pendingRequest != nil, !auditNotificationNavResolved {
                awaitingAuditNavigationResolution = true
                auditNotificationNavResolved = false
                selectedTab = .hardware
                hardwarePath = NavigationPath()
                isDetailViewActive = false
                tryResolveAndOpenAuditListFilter()
            }
        }
        .onChange(of: auditNotificationRouter.pendingRequest?.id) { _, _ in
            guard auditNotificationRouter.pendingRequest != nil else { return }
            // Set this immediately so `onChange(of: selectedTab)` doesn't override this transition.
            awaitingAuditNavigationResolution = true
            auditNotificationNavResolved = false
            selectedTab = .hardware
            hardwarePath = NavigationPath()
            isDetailViewActive = false
            tryResolveAndOpenAuditListFilter()
        }
        .onChange(of: apiClient.assets.count) { _, _ in
            guard awaitingAuditNavigationResolution, auditNotificationRouter.pendingRequest != nil else { return }
            tryResolveAndOpenAuditListFilter()
        }
    }

    @ViewBuilder
    private func tabView(for tab: MainTab) -> some View {
        switch tab {
        case .hardware:
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
                auditListFilter: $auditListFilter,
                hardwareSubtab: $hardwareSubtab,
                showTodayOnlyOverride: $showTodayOnlyOverride,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; hardwarePath = NavigationPath() } },
                onOpenUser: { u in pendingUserToOpen = u; selectedTab = .directory; returnToTab = .hardware },
                onOpenLocation: { pendingLocationToOpen = $0; selectedTab = .directory; returnToTab = .hardware },
                onOpenLicense: { pendingLicenseToOpen = $0; selectedTab = .licenses; returnToTab = .hardware },
                onOpenAccessory: { pendingAccessoryToOpen = $0; selectedTab = .accessories; returnToTab = .hardware },
                onOpenComponent: { pendingComponentToOpen = $0; selectedTab = .stock; returnToTab = .hardware }
            )
        case .accessories:
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
                onOpenUser: { u in pendingUserToOpen = u; selectedTab = .directory; returnToTab = .accessories },
                onOpenAsset: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .accessories },
                onOpenLocation: { pendingLocationToOpen = $0; selectedTab = .directory; returnToTab = .accessories }
            )
        case .licenses:
            LicensesTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                licenseDetailTab: $licenseDetailTab,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                navigationPath: $licensesPath,
                isDetailViewActive: $isDetailViewActive,
                pendingLicenseToOpen: $pendingLicenseToOpen,
                returnToTab: $returnToTab,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; licensesPath = NavigationPath() } },
                onOpenUser: { u in pendingUserToOpen = u; selectedTab = .directory; returnToTab = .licenses },
                onOpenAsset: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .licenses }
            )
        case .stock:
            StockTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                consumableDetailTab: $consumableDetailTab,
                componentDetailTab: $componentDetailTab,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                navigationPath: $stockPath,
                isDetailViewActive: $isDetailViewActive,
                pendingConsumableToOpen: $pendingConsumableToOpen,
                pendingComponentToOpen: $pendingComponentToOpen,
                returnToTab: $returnToTab,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; stockPath = NavigationPath() } },
                onOpenUser: { u in pendingUserToOpen = u; selectedTab = .directory; returnToTab = .stock },
                onOpenAsset: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .stock }
            )
        case .directory:
            DirectoryTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                navigationPath: $directoryPath,
                isDetailViewActive: $isDetailViewActive,
                pendingUserToOpen: $pendingUserToOpen,
                pendingLocationToOpen: $pendingLocationToOpen,
                returnToTab: $returnToTab,
                onBackToPreviousTab: { if let t = returnToTab { selectedTab = t; returnToTab = nil; directoryPath = NavigationPath() } },
                onOpenAssetFromUser: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .directory },
                onOpenAccessoryFromUser: { pendingAccessoryToOpen = $0; selectedTab = .accessories; returnToTab = .directory },
                onOpenLicenseFromUser: { pendingLicenseToOpen = $0; selectedTab = .licenses; returnToTab = .directory },
                onOpenConsumableFromUser: { pendingConsumableToOpen = $0; selectedTab = .stock; returnToTab = .directory },
                onOpenLocationFromUser: { pendingLocationToOpen = $0 },
                onOpenUserFromLocation: { pendingUserToOpen = $0 },
                onOpenAssetFromLocation: { pendingAssetToOpen = $0; selectedTab = .hardware; returnToTab = .directory },
                onOpenAccessoryFromLocation: { pendingAccessoryToOpen = $0; selectedTab = .accessories; returnToTab = .directory }
            )
        }
    }

    private func isTabVisible(_ tab: MainTab) -> Bool {
        switch tab {
        case .hardware, .directory:
            return true
        case .accessories: return showAccessoriesTab
        case .licenses: return showLicensesTab
        case .stock:
            return showConsumablesSub || showComponentsSub
        }
    }

    private func resetSelectedTabIfHidden() {
        if !isTabVisible(selectedTab) {
            selectedTab = .hardware
        }
    }

    private func tryResolveAndOpenAuditListFilter() {
        guard !auditNotificationNavResolved else { return }

        // For this notification, switch to the Audit subtab and show full results
        // (not just the "due today" view).
        auditListFilter = .all
        showTodayOnlyOverride = false
        hardwareSubtab = enableAuditSubtab ? .audit : .all

        // Avoid landing on an asset detail view.
        pendingAssetToOpen = nil
        auditNotificationNavResolved = true

        // Defer resetting `selectedTab` until after the state changes,
        // so SwiftUI doesn't override the Audit subtab.
        DispatchQueue.main.async {
            awaitingAuditNavigationResolution = false
            auditNotificationRouter.consume()
        }
    }

    private func handleScanResult(_ result: Result<ScanResult, ScanError>) {
        showingScanner = false
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
                    selectedTab = .hardware
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
                // Snipe-IT QR: asset ID in path
                if let id = extractAssetId(from: url) {
                    if let asset = apiClient.assets.first(where: { $0.id == id }) {
                        scannedAssetId = asset.id
                        selectedTab = .hardware
                    } else if apiClient.assets.isEmpty {
                        scannedAssetId = id
                        selectedTab = .hardware
                        Task { await apiClient.fetchPrimaryThenBackground() }
                    } else {
                        scannedAssetId = nil
                        scanErrorMessage = L10n.string("asset_not_found_id", String(id))
                        showScanErrorAlert = true
                    }
                    return
                }

                // Dell QR: service tag. Look up by serial.
                if enableDellQrScan,
                   let host = url.host, host.lowercased().contains("dell"),
                   let serial = SnipeITAPIClient.extractDellServiceTag(from: url), !serial.isEmpty {
                    let normalized = serial.trimmingCharacters(in: .whitespaces).lowercased()

                    if let asset = apiClient.assets.first(where: {
                        $0.decodedSerial.trimmingCharacters(in: .whitespaces).lowercased() == normalized
                    }) {
                        scannedAssetId = asset.id
                        selectedTab = .hardware
                    } else if apiClient.assets.isEmpty {
                        Task {
                            await apiClient.fetchPrimaryThenBackground()
                            await MainActor.run {
                                if let asset = findAsset(for: normalized) {
                                    scannedAssetId = asset.id
                                    selectedTab = .hardware
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
                                selectedTab = .hardware
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
                selectedTab = .hardware
                return
            } else if apiClient.assets.isEmpty {
                Task {
                    await apiClient.fetchPrimaryThenBackground()
                    // continue below
                    await openHardwareForScannedValueByTag(scannedValue)
                }
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

    /// Prompt to create a new asset when a Dell QR has no match in Snipe-IT.
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
    @Binding var auditListFilter: AuditListFilter
    @Binding var hardwareSubtab: HardwareAuditSubtab
    @Binding var showTodayOnlyOverride: Bool
    var onBackToPreviousTab: () -> Void
    var onOpenUser: (User) -> Void
    var onOpenLocation: (Location) -> Void
    var onOpenLicense: (License) -> Void
    var onOpenAccessory: (Accessory) -> Void
    var onOpenComponent: (Component) -> Void

    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = false
    @AppStorage("auditNotificationsEnabled") private var auditNotificationsEnabled: Bool = false
    @AppStorage("auditNotificationHour") private var auditNotificationHour: Int = 9
    @AppStorage("auditNotificationMinute") private var auditNotificationMinute: Int = 0
    private let dueSoonDays: Int = 7

    @State private var assetToDelete: Asset?
    @State private var showDeleteConfirm = false

    // Quick audit completion from the audit list.
    @State private var showAuditCompletionSheet = false
    @State private var auditCompletionAsset: Asset?
    @State private var auditCompletionNextAuditDate: Date = Date()
    @State private var isSavingAuditCompletion = false
    @State private var showAuditCompletionErrorAlert = false
    @State private var auditCompletionErrorMessage = ""
    @State private var isOverdueExpanded = false

    private var searchFilteredAssets: [Asset] {
        if searchText.isEmpty { return apiClient.assets }
        let q = searchText.lowercased()
        return apiClient.assets.filter {
            $0.decodedName.lowercased().contains(q) ||
            $0.decodedModelName.lowercased().contains(q) ||
            $0.decodedAssetTag.lowercased().contains(q) ||
            $0.decodedLocationName.lowercased().contains(q) ||
            $0.decodedAssignedToName.lowercased().contains(q)
        }
    }

    private var dueTodayAssets: [Asset] {
        let now = Date()
        return AuditDateClassifier.sortByNextAuditDateThenTag(
            searchFilteredAssets.filter { AuditDateClassifier.isDueToday($0, now: now) }
        )
    }

    private var dueSoonAssets: [Asset] {
        let now = Date()
        return AuditDateClassifier.sortByNextAuditDateThenTag(
            searchFilteredAssets.filter { AuditDateClassifier.isDueSoon($0, now: now, dueSoonDays: dueSoonDays) }
        )
    }

    private var overdueAssets: [Asset] {
        let now = Date()
        return AuditDateClassifier.sortByNextAuditDateThenTag(
            searchFilteredAssets.filter { AuditDateClassifier.isOverdue($0, now: now) }
        )
    }

    private var shouldShowNextAuditDateOnCard: Bool {
        enableAuditSubtab && hardwareSubtab == .audit
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            hardwareTabContent
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
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
                            Task { await saveAuditCompletionFromList() }
                        }
                        .disabled(isSavingAuditCompletion)
                    }
                }
            }
        }
        .alert(L10n.string("error"), isPresented: $showAuditCompletionErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {
                auditCompletionErrorMessage = ""
            }
        } message: {
            Text(auditCompletionErrorMessage)
        }
    }

    private func saveAuditCompletionFromList() async {
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

    @ViewBuilder
    private var hardwareTabContent: some View {
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api"))
                )
            } else if let error = apiClient.errorMessage {
                ScrollView {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(error))
                        .frame(minHeight: 400)
                }
            } else {
                hardwareAssetList
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
                await apiClient.fetchAssets()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
        .navigationDestination(for: Asset.self) { asset in
            AssetDetailView(asset: asset, apiClient: apiClient, selectedTab: $assetDetailTab, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenUser: onOpenUser, onOpenLocation: onOpenLocation, onOpenLicense: onOpenLicense, onOpenAccessory: onOpenAccessory, onOpenComponent: onOpenComponent, onOpenAsset: { navigationPath.append($0) })
        }
        .alert(L10n.string("delete_asset_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L10n.string("cancel"), role: .cancel) {
                assetToDelete = nil
            }
            Button(L10n.string("delete"), role: .destructive) {
                guard let a = assetToDelete else { return }
                #if DEBUG
                print("[SnipeMobile] Gebruiker bevestigde delete: asset id=\(a.id) tag=\(a.decodedAssetTag) — roep DELETE API aan")
                #endif
                Task {
                    let ok = await apiClient.deleteAsset(assetId: a.id)
                    #if DEBUG
                    print("[SnipeMobile] deleteAsset(\(a.id)) result: \(ok)")
                    #endif
                }
                assetToDelete = nil
                showDeleteConfirm = false
            }
        } message: {
            if let a = assetToDelete {
                Text(L10n.string("delete_asset_confirm_message", a.decodedAssetTag))
            }
        }
    }

    private var isHardwareListContentEmpty: Bool {
        if enableAuditSubtab, hardwareSubtab == .audit {
            switch auditListFilter {
            case .dueToday: return dueTodayAssets.isEmpty
            case .dueSoon: return dueSoonAssets.isEmpty
            case .all: return dueTodayAssets.isEmpty && dueSoonAssets.isEmpty && overdueAssets.isEmpty
            }
        }
        let assetsToShow = showTodayOnlyOverride ? dueTodayAssets : searchFilteredAssets
        return assetsToShow.isEmpty
    }

    private var hardwareEmptyTitle: String {
        searchText.isEmpty ? L10n.string("no_assets") : L10n.string("no_assets_match")
    }

    private var hardwareAssetList: some View {
        let showLoadingPlaceholder = apiClient.isLoading && !isRefreshing && apiClient.assets.isEmpty
        return List {
            if enableAuditSubtab {
                Section {
                    Picker(selection: $hardwareSubtab, label: Text("Hardware")) {
                        Text(L10n.string("tab_hardware")).tag(HardwareAuditSubtab.all)
                        Text(L10n.string("audit")).tag(HardwareAuditSubtab.audit)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: hardwareSubtab) { _, newValue in
                        if newValue == .all {
                            showTodayOnlyOverride = false
                            auditListFilter = .all
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 0, trailing: 12))
            }

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

            if showLoadingPlaceholder {
                // Keep header/subtab visible while loading; content loader is centered via overlay.
            } else if enableAuditSubtab, hardwareSubtab == .audit {
                switch auditListFilter {
                case .dueToday:
                    if !dueTodayAssets.isEmpty {
                        Section(header: Text(L10n.string("audit_due_today_header", dueTodayAssets.count))) {
                            ForEach(dueTodayAssets) { asset in
                                auditAssetRow(asset)
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
                                auditAssetRow(asset)
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
                                    auditAssetRow(asset)
                                }
                            }
                        }
                    }
                    if !dueTodayAssets.isEmpty {
                        Section(header: Text(L10n.string("audit_due_today_header", dueTodayAssets.count))) {
                            ForEach(dueTodayAssets) { asset in
                                auditAssetRow(asset)
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
                                auditAssetRow(asset)
                            }
                        }
                    }
                }
            } else {
                let assetsToShow = showTodayOnlyOverride ? dueTodayAssets : searchFilteredAssets
                if !assetsToShow.isEmpty {
                    Section {
                        ForEach(assetsToShow) { asset in
                            auditAssetRow(asset)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(0)
        .listSectionSeparator(.hidden)
        .overlay {
            if showLoadingPlaceholder {
                ProgressView(L10n.string("loading_assets"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if isHardwareListContentEmpty && apiClient.isConfigured && !apiClient.isLoading && apiClient.hasCompletedInitialLoad {
                ContentUnavailableView(hardwareEmptyTitle, systemImage: "laptopcomputer")
            }
        }
    }

    @ViewBuilder
    private func auditAssetRow(_ asset: Asset) -> some View {
        let isAuditTabActive = enableAuditSubtab && hardwareSubtab == .audit

        Button {
            navigationPath.append(asset)
        } label: {
            AssetCardView(asset: asset, showNextAuditDate: shouldShowNextAuditDateOnCard)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if shouldShowNextAuditDateOnCard, (AuditDateClassifier.isDueToday(asset, now: Date()) || AuditDateClassifier.isOverdue(asset, now: Date())) {
                Button {
                    auditCompletionAsset = asset
                    auditCompletionNextAuditDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
                    showAuditCompletionSheet = true
                } label: {
                    Label(L10n.string("audit_completed_action"), systemImage: "checkmark.seal")
                }
                .tint(.purple)
            }
            if !isAuditTabActive {
                Button(role: .destructive) {
                    assetToDelete = asset
                    showDeleteConfirm = true
                } label: {
                    Label(L10n.string("delete"), systemImage: "trash")
                }
            }
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AccessoriesContent(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                navigationPath: $navigationPath
            )
            .onAppear { isDetailViewActive = false }
            .navigationTitle(L10n.string("tab_accessories"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingAddAccessory = true } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(L10n.string("add_accessory"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingScanner = true } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(L10n.string("scan_qr"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.string("search_accessories"))
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    await apiClient.fetchAccessories()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: Accessory.self) { accessory in
                AccessoryDetailView(accessory: accessory, apiClient: apiClient, selectedTab: $accessoryDetailTab, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenUser: onOpenUser, onOpenAsset: onOpenAsset, onOpenLocation: onOpenLocation)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .onChange(of: pendingAccessoryToOpen) { _, new in
            if let accessory = new {
                navigationPath.append(accessory)
                pendingAccessoryToOpen = nil
            }
        }
    }
}

// MARK: - Licenses Tab

struct LicensesTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var licenseDetailTab: Int
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingLicenseToOpen: License?
    @Binding var returnToTab: MainTab?
    var onBackToPreviousTab: () -> Void
    var onOpenUser: (User) -> Void
    var onOpenAsset: (Asset) -> Void

    @State private var showingAddLicense = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            LicensesContent(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                navigationPath: $navigationPath
            )
            .onAppear { isDetailViewActive = false }
            .navigationTitle(L10n.string("tab_licenses"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingAddLicense = true } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(L10n.string("add_license"))
                }
                commonModuleToolbar(showingSettings: $showingSettings, showingScanner: $showingScanner)
            }
            .searchable(text: $searchText, prompt: L10n.string("search_licenses"))
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    await apiClient.fetchLicenses()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: License.self) { license in
                LicenseDetailView(
                    license: license,
                    apiClient: apiClient,
                    selectedTab: $licenseDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    returnToTab: returnToTab,
                    onBackToPrevious: onBackToPreviousTab,
                    onOpenUser: onOpenUser,
                    onOpenAsset: onOpenAsset
                )
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .sheet(isPresented: $showingAddLicense) {
                AddLicenseSheet(
                    apiClient: apiClient,
                    isPresented: $showingAddLicense,
                    onCreated: { newId in
                        Task {
                            if let newId,
                               let detailed = await apiClient.fetchLicenseDetails(licenseId: newId) {
                                await MainActor.run {
                                    navigationPath.append(detailed)
                                }
                            }
                        }
                    }
                )
            }
        }
        .onChange(of: pendingLicenseToOpen) { _, new in
            if let license = new {
                navigationPath.append(license)
                pendingLicenseToOpen = nil
            }
        }
    }
}

private struct LicensesContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

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

    var body: some View {
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api_short"))
                )
            } else if apiClient.isLoading && !isRefreshing && apiClient.licenses.isEmpty {
                ProgressView(L10n.string("loading_licenses"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiClient.errorMessage != nil {
                ScrollView {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(apiClient.errorMessage ?? ""))
                        .frame(minHeight: 400)
                }
            } else {
                List {
                    Section {
                        HStack {
                            Label("\(apiClient.licenses.count)", systemImage: "doc.text.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }

                    Section {
                        ForEach(filteredLicenses) { license in
                            Button {
                                navigationPath.append(license)
                            } label: {
                                LicenseCardView(license: license)
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
                .overlay {
                    if filteredLicenses.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                        ContentUnavailableView(L10n.string("no_licenses"), systemImage: "doc.text.fill")
                    }
                }
            }
        }
    }
}

// MARK: - Stock Tab (consumables + components)

struct StockTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var consumableDetailTab: Int
    @Binding var componentDetailTab: Int
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingConsumableToOpen: Consumable?
    @Binding var pendingComponentToOpen: Component?
    @Binding var returnToTab: MainTab?
    var onBackToPreviousTab: () -> Void
    var onOpenUser: (User) -> Void
    var onOpenAsset: (Asset) -> Void

    @AppStorage("showConsumablesTab") private var showConsumablesSub: Bool = true
    @AppStorage("showComponentsTab") private var showComponentsSub: Bool = true
    @AppStorage("stockSelectedSubmodule") private var selectedSubmoduleRaw: String = StockSubmodule.consumables.rawValue

    @State private var showingComingSoon = false
    @State private var showingAddConsumable = false
    @State private var showingAddComponent = false

    private var enabledSubmodules: [StockSubmodule] {
        StockSubmodule.allCases.filter { isEnabled($0) }
    }

    private var selectedSubmodule: StockSubmodule {
        let stored = StockSubmodule(rawValue: selectedSubmoduleRaw) ?? .consumables
        return isEnabled(stored) ? stored : (enabledSubmodules.first ?? .consumables)
    }

    private func isEnabled(_ s: StockSubmodule) -> Bool {
        switch s {
        case .consumables: return showConsumablesSub
        case .components: return showComponentsSub
        }
    }

    private var searchPrompt: String {
        switch selectedSubmodule {
        case .consumables: return L10n.string("search_consumables")
        case .components: return L10n.string("search_components")
        }
    }

    private var addLabel: String {
        switch selectedSubmodule {
        case .consumables: return L10n.string("add_consumable")
        case .components: return L10n.string("add_component")
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if selectedSubmodule == .consumables {
                    ConsumablesContent(
                        apiClient: apiClient,
                        searchText: $searchText,
                        isRefreshing: $isRefreshing,
                        navigationPath: $navigationPath
                    )
                } else {
                    ComponentsContent(
                        apiClient: apiClient,
                        searchText: $searchText,
                        isRefreshing: $isRefreshing,
                        navigationPath: $navigationPath
                    )
                }
            }
            .onAppear { isDetailViewActive = false }
            .navigationTitle(selectedSubmodule.localizedTitle)
            .toolbar {
                if enabledSubmodules.count > 1 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        submodulePickerMenu(
                            current: selectedSubmodule.icon,
                            options: enabledSubmodules.map { ($0.rawValue, $0.localizedTitle, $0.icon) },
                            selection: $selectedSubmoduleRaw
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if selectedSubmodule == .consumables {
                            showingAddConsumable = true
                        } else {
                            showingAddComponent = true
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(addLabel)
                }
                commonModuleToolbar(showingSettings: $showingSettings, showingScanner: $showingScanner)
            }
            .searchable(text: $searchText, prompt: searchPrompt)
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    if selectedSubmodule == .consumables {
                        await apiClient.fetchConsumables()
                    } else {
                        await apiClient.fetchComponents()
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: Consumable.self) { consumable in
                ConsumableDetailView(
                    consumable: consumable,
                    apiClient: apiClient,
                    selectedTab: $consumableDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    returnToTab: returnToTab,
                    onBackToPrevious: onBackToPreviousTab,
                    onOpenUser: onOpenUser
                )
            }
            .navigationDestination(for: Component.self) { component in
                ComponentDetailView(
                    component: component,
                    apiClient: apiClient,
                    selectedTab: $componentDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    returnToTab: returnToTab,
                    onBackToPrevious: onBackToPreviousTab,
                    onOpenAsset: onOpenAsset
                )
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .alert(L10n.string("module_coming_soon_title"), isPresented: $showingComingSoon) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(L10n.string("module_coming_soon"))
            }
            .sheet(isPresented: $showingAddConsumable) {
                AddConsumableSheet(
                    apiClient: apiClient,
                    isPresented: $showingAddConsumable,
                    onCreated: { newId in
                        Task {
                            if let newId,
                               let detailed = await apiClient.fetchConsumableDetails(consumableId: newId) {
                                await MainActor.run {
                                    navigationPath.append(detailed)
                                }
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showingAddComponent) {
                AddComponentSheet(
                    apiClient: apiClient,
                    isPresented: $showingAddComponent,
                    onCreated: { newId in
                        Task {
                            if let newId,
                               let detailed = await apiClient.fetchComponentDetails(componentId: newId) {
                                await MainActor.run {
                                    navigationPath.append(detailed)
                                }
                            }
                        }
                    }
                )
            }
        }
        .onChange(of: pendingConsumableToOpen) { _, new in
            if let consumable = new {
                navigationPath.append(consumable)
                pendingConsumableToOpen = nil
            }
        }
        .onChange(of: pendingComponentToOpen) { _, new in
            if let component = new {
                navigationPath.append(component)
                pendingComponentToOpen = nil
            }
        }
    }
}

private struct ConsumablesContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

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

    var body: some View {
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api_short"))
                )
            } else if apiClient.isLoading && !isRefreshing && apiClient.consumables.isEmpty {
                ProgressView(L10n.string("loading_consumables"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiClient.errorMessage != nil {
                ScrollView {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(apiClient.errorMessage ?? ""))
                        .frame(minHeight: 400)
                }
            } else {
                List {
                    Section {
                        HStack {
                            Label("\(apiClient.consumables.count)", systemImage: "shippingbox")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }

                    Section {
                        ForEach(filteredConsumables) { consumable in
                            Button {
                                navigationPath.append(consumable)
                            } label: {
                                ConsumableCardView(consumable: consumable)
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
                .overlay {
                    if filteredConsumables.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                        ContentUnavailableView(L10n.string("no_consumables"), systemImage: "shippingbox")
                    }
                }
            }
        }
    }
}

private struct ComponentsContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

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

    var body: some View {
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api_short"))
                )
            } else if apiClient.isLoading && !isRefreshing && apiClient.components.isEmpty {
                ProgressView(L10n.string("loading_components"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiClient.errorMessage != nil {
                ScrollView {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(apiClient.errorMessage ?? ""))
                        .frame(minHeight: 400)
                }
            } else {
                List {
                    Section {
                        HStack {
                            Label("\(apiClient.components.count)", systemImage: "cpu")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }

                    Section {
                        ForEach(filteredComponents) { component in
                            Button {
                                navigationPath.append(component)
                            } label: {
                                ComponentCardView(component: component)
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
                .overlay {
                    if filteredComponents.isEmpty && apiClient.isConfigured && !apiClient.isLoading {
                        ContentUnavailableView(L10n.string("no_components"), systemImage: "cpu")
                    }
                }
            }
        }
    }
}

// MARK: - Shared helpers for module toolbars

@ToolbarContentBuilder
func commonModuleToolbar(showingSettings: Binding<Bool>, showingScanner: Binding<Bool>) -> some ToolbarContent {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button { showingScanner.wrappedValue = true } label: {
            Image(systemName: "qrcode.viewfinder")
        }
        .accessibilityLabel(L10n.string("scan_qr"))
    }
    ToolbarItem(placement: .navigationBarTrailing) {
        Button { showingSettings.wrappedValue = true } label: {
            Image(systemName: "gearshape")
        }
    }
}

func submodulePickerMenu(
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
        .padding(.horizontal, 4)
    }
    .accessibilityLabel(L10n.string("switch_module"))
}

private struct AccessoriesContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

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
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api_short"))
                )
            } else if apiClient.isLoading && !isRefreshing && apiClient.accessories.isEmpty {
                ProgressView(L10n.string("loading_accessories"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiClient.errorMessage != nil {
                ScrollView {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(apiClient.errorMessage ?? ""))
                        .frame(minHeight: 400)
                }
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
                .moduleEmptyOverlay(
                    isVisible: filteredAccessories.isEmpty && apiClient.isConfigured && !apiClient.isLoading,
                    title: L10n.string("no_accessories"),
                    systemImage: "mediastick"
                )
            }
        }
    }
}

// MARK: - Directory Tab (users + locations)

struct DirectoryTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingUserToOpen: User?
    @Binding var pendingLocationToOpen: Location?
    @Binding var returnToTab: MainTab?
    var onBackToPreviousTab: () -> Void
    var onOpenAssetFromUser: (Asset) -> Void
    var onOpenAccessoryFromUser: (Accessory) -> Void
    var onOpenLicenseFromUser: (License) -> Void
    var onOpenConsumableFromUser: (Consumable) -> Void
    var onOpenLocationFromUser: (Location) -> Void
    var onOpenUserFromLocation: (User) -> Void
    var onOpenAssetFromLocation: (Asset) -> Void
    var onOpenAccessoryFromLocation: (Accessory) -> Void

    @AppStorage("directorySelectedSubmodule") private var selectedSubmoduleRaw: String = DirectorySubmodule.users.rawValue

    @State private var showingComingSoon = false
    @State private var showingAddUser = false
    @State private var showingAddLocation = false

    private var enabledSubmodules: [DirectorySubmodule] { DirectorySubmodule.allCases }

    private var selectedSubmodule: DirectorySubmodule {
        DirectorySubmodule(rawValue: selectedSubmoduleRaw) ?? .users
    }

    private var addLabel: String {
        selectedSubmodule == .users
            ? L10n.string("add_user")
            : L10n.string("add_location")
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                switch selectedSubmodule {
                case .users:
                    UsersContent(
                        apiClient: apiClient,
                        searchText: $searchText,
                        isRefreshing: $isRefreshing,
                        navigationPath: $navigationPath
                    )
                case .locations:
                    LocationsContent(
                        apiClient: apiClient,
                        searchText: $searchText,
                        isRefreshing: $isRefreshing,
                        navigationPath: $navigationPath
                    )
                }
            }
            .onAppear {
                if navigationPath.isEmpty {
                    isDetailViewActive = false
                }
            }
            .navigationTitle(selectedSubmodule.localizedTitle)
            .toolbar {
                if enabledSubmodules.count > 1 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        submodulePickerMenu(
                            current: selectedSubmodule.icon,
                            options: enabledSubmodules.map { ($0.rawValue, $0.localizedTitle, $0.icon) },
                            selection: $selectedSubmoduleRaw
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        switch selectedSubmodule {
                        case .users: showingAddUser = true
                        case .locations: showingAddLocation = true
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(addLabel)
                }
                commonModuleToolbar(showingSettings: $showingSettings, showingScanner: $showingScanner)
            }
            .sheet(isPresented: $showingAddUser) {
                AddUserSheet(
                    apiClient: apiClient,
                    isPresented: $showingAddUser,
                    onCreated: { newId in
                        Task {
                            if let newId,
                               let detailed = await apiClient.fetchUserDetails(userId: newId) {
                                await MainActor.run {
                                    if selectedSubmoduleRaw != DirectorySubmodule.users.rawValue {
                                        selectedSubmoduleRaw = DirectorySubmodule.users.rawValue
                                    }
                                    navigationPath.append(detailed)
                                }
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showingAddLocation) {
                AddLocationSheet(
                    apiClient: apiClient,
                    isPresented: $showingAddLocation,
                    onCreated: { newId in
                        Task {
                            await apiClient.fetchLocations()
                            await MainActor.run {
                                guard let newId,
                                      let created = apiClient.locations.first(where: { $0.id == newId }) else { return }
                                if selectedSubmoduleRaw != DirectorySubmodule.locations.rawValue {
                                    selectedSubmoduleRaw = DirectorySubmodule.locations.rawValue
                                }
                                navigationPath.append(created)
                            }
                        }
                    }
                )
            }
            .searchable(
                text: $searchText,
                prompt: selectedSubmodule == .users
                    ? L10n.string("search_users")
                    : L10n.string("search_locations")
            )
            .alert(L10n.string("module_coming_soon_title"), isPresented: $showingComingSoon) {
                Button(L10n.string("ok"), role: .cancel) { }
            } message: {
                Text(L10n.string("module_coming_soon"))
            }
            .refreshable {
                if apiClient.isConfigured {
                    isRefreshing = true
                    switch selectedSubmodule {
                    case .users:
                        await apiClient.fetchUsers()
                    case .locations:
                        await apiClient.fetchLocations()
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .navigationDestination(for: User.self) { user in
                UserDetailView(user: user, apiClient: apiClient, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenAsset: onOpenAssetFromUser, onOpenAccessory: onOpenAccessoryFromUser, onOpenLocation: onOpenLocationFromUser, onOpenLicense: onOpenLicenseFromUser, onOpenConsumable: onOpenConsumableFromUser)
                    .id(user.id)
            }
            .navigationDestination(for: Location.self) { location in
                LocationDetailView(location: location, apiClient: apiClient, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenUser: onOpenUserFromLocation, onOpenAsset: onOpenAssetFromLocation, onOpenAccessory: onOpenAccessoryFromLocation)
                    .id(location.id)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .onChange(of: pendingUserToOpen) { _, new in
            guard let user = new else { return }
            pendingUserToOpen = nil
            DispatchQueue.main.async {
                if selectedSubmoduleRaw != DirectorySubmodule.users.rawValue {
                    selectedSubmoduleRaw = DirectorySubmodule.users.rawValue
                }
                navigationPath.append(user)
            }
        }
        .onChange(of: pendingLocationToOpen) { _, new in
            guard let location = new else { return }
            pendingLocationToOpen = nil
            DispatchQueue.main.async {
                if selectedSubmoduleRaw != DirectorySubmodule.locations.rawValue {
                    selectedSubmoduleRaw = DirectorySubmodule.locations.rawValue
                }
                navigationPath.append(location)
            }
        }
    }
}

private struct UsersContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

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
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api_short"))
                )
            } else if apiClient.isLoading && !isRefreshing && apiClient.users.isEmpty {
                ProgressView(L10n.string("loading_users"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiClient.errorMessage != nil {
                ScrollView {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(apiClient.errorMessage ?? ""))
                        .frame(minHeight: 400)
                }
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
                .moduleEmptyOverlay(
                    isVisible: filteredUsers.isEmpty && apiClient.isConfigured && !apiClient.isLoading,
                    title: L10n.string("no_users"),
                    systemImage: "person.2"
                )
            }
        }
    }
}

private struct LocationsContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

    var filteredLocations: [Location] {
        if searchText.isEmpty { return apiClient.locations }
        return apiClient.locations.filter { $0.decodedName.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        Group {
            if !apiClient.isConfigured {
                ContentUnavailableView(
                    L10n.string("no_data_yet"),
                    systemImage: "link.badge.plus",
                    description: Text(L10n.string("configure_api_short"))
                )
            } else if apiClient.isLoading && !isRefreshing && apiClient.locations.isEmpty {
                ProgressView(L10n.string("loading_locations"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apiClient.errorMessage != nil {
                ScrollView {
                    ContentUnavailableView(L10n.string("error"), systemImage: "exclamationmark.triangle", description: Text(apiClient.errorMessage ?? ""))
                        .frame(minHeight: 400)
                }
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
                .moduleEmptyOverlay(
                    isVisible: filteredLocations.isEmpty && apiClient.isConfigured && !apiClient.isLoading,
                    title: L10n.string("no_locations"),
                    systemImage: "mappin.and.ellipse"
                )
            }
        }
    }
}

struct TabBarMinimizeBehaviorModifier: ViewModifier {
    let isDetailVisible: Bool
    @State private var deferredDetailVisible = false

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content.tabBarMinimizeBehavior(deferredDetailVisible ? .never : .onScrollDown)
            } else {
                content
            }
        }
        .onAppear {
            deferredDetailVisible = isDetailVisible
        }
        .onChange(of: isDetailVisible) { _, visible in
            DispatchQueue.main.async {
                deferredDetailVisible = visible
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}
