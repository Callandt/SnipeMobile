import SwiftUI
import AVFoundation
import Foundation
import UIKit

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
    static let defaultOrder: [MainTab] = [
        .hardware, .accessories, .licenses, .stock, .directory,
    ]
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
    case maintenance
}

struct ContentView: View {
    @StateObject private var apiClient = SnipeITAPIClient()
    @State private var selectedTab: MainTab = .hardware
    @State private var showingScanner = false
    @State private var pendingQRLink: SnipeITQRLink?
    @AppStorage("stockSelectedSubmodule") private var stockSelectedSubmoduleRaw: String = StockSubmodule.consumables.rawValue
    @State private var searchText: String = ""
    @State private var isRefreshing: Bool = false
    @State private var hasLoadedInitialAssets: Bool = false
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject private var auditNotificationRouter: AuditNotificationRouter
    @EnvironmentObject private var widgetNavigationRouter: WidgetNavigationRouter
    @State private var auditListFilter: AuditListFilter = .all
    @State private var hardwareSubtab: HardwareAuditSubtab = .all
    @State private var showTodayOnlyOverride = false
    @State private var showingSettings = false
    @State private var showingAddAsset = false
    @State private var showingAddAccessory = false
    @State private var hardwarePath = NavigationPath()
    @State private var accessoriesPath = NavigationPath()
    @State private var licensesPath = NavigationPath()
    @State private var stockPath = NavigationPath()
    @State private var directoryPath = NavigationPath()
    @State private var isDetailViewActive = false
    /// True when a detail screen is pushed.
    @State private var showScanErrorAlert = false
    @State private var scanErrorMessage: String?
    @State private var showAddDellAssetPrompt = false
    @State private var pendingDellURLForAdd: URL?
    @State private var pendingDellSerial: String?
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true
    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = false
    @AppStorage("showMaintenance") private var showMaintenance: Bool = true
    @AppStorage("showAccessoriesTab") private var showAccessoriesTab: Bool = true
    @AppStorage("showLicensesTab") private var showLicensesTab: Bool = true
    @AppStorage("showConsumablesTab") private var showConsumablesSub: Bool = true
    @AppStorage("showComponentsTab") private var showComponentsSub: Bool = true
    @State private var awaitingAuditNavigationResolution = false
    @State private var auditNotificationNavResolved = false
    @State private var awaitingWidgetNavigation = false
    @State private var widgetNavigationResolved = false

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
            if !awaitingAuditNavigationResolution && !awaitingWidgetNavigation {
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
        .sheet(isPresented: $showingScanner) {
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
                get: { apiClient.refreshErrorMessage != nil && !apiClient.pendingUnauthorizedSessionWipe },
                set: { newValue in
                    if !newValue {
                        // Defer out of the view-update cycle to avoid
                        // "Publishing changes from within view updates".
                        DispatchQueue.main.async { apiClient.refreshErrorMessage = nil }
                    }
                }
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

            if widgetNavigationRouter.pendingRequest != nil, !widgetNavigationResolved {
                beginWidgetNavigation()
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
        .onChange(of: widgetNavigationRouter.pendingRequest?.id) { _, _ in
            guard widgetNavigationRouter.pendingRequest != nil else { return }
            widgetNavigationResolved = false
            beginWidgetNavigation()
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
                pendingQRLink: $pendingQRLink,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                showingAddAsset: $showingAddAsset,
                navigationPath: $hardwarePath,
                isDetailViewActive: $isDetailViewActive,
                auditListFilter: $auditListFilter,
                hardwareSubtab: $hardwareSubtab,
                showTodayOnlyOverride: $showTodayOnlyOverride
            )
        case .accessories:
            AccessoriesTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                showingAddAccessory: $showingAddAccessory,
                navigationPath: $accessoriesPath,
                isDetailViewActive: $isDetailViewActive,
                pendingQRLink: $pendingQRLink
            )
        case .licenses:
            LicensesTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                navigationPath: $licensesPath,
                isDetailViewActive: $isDetailViewActive,
                pendingQRLink: $pendingQRLink
            )
        case .stock:
            StockTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                navigationPath: $stockPath,
                isDetailViewActive: $isDetailViewActive,
                pendingQRLink: $pendingQRLink
            )
        case .directory:
            DirectoryTab(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                showingSettings: $showingSettings,
                showingScanner: $showingScanner,
                navigationPath: $directoryPath,
                isDetailViewActive: $isDetailViewActive
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
        auditNotificationNavResolved = true

        // Defer resetting `selectedTab` until after the state changes,
        // so SwiftUI doesn't override the Audit subtab.
        DispatchQueue.main.async {
            awaitingAuditNavigationResolution = false
            auditNotificationRouter.consume()
        }
    }

    private func beginWidgetNavigation() {
        guard !widgetNavigationResolved, widgetNavigationRouter.pendingRequest != nil else { return }
        awaitingWidgetNavigation = true

        WidgetNavigation.apply(
            destination: widgetNavigationRouter.pendingRequest!.destination,
            enableAuditSubtab: enableAuditSubtab,
            showMaintenance: showMaintenance,
            selectedTab: &selectedTab,
            hardwareSubtab: &hardwareSubtab,
            auditListFilter: &auditListFilter,
            showTodayOnlyOverride: &showTodayOnlyOverride
        )

        hardwarePath = NavigationPath()
        accessoriesPath = NavigationPath()
        licensesPath = NavigationPath()
        stockPath = NavigationPath()
        directoryPath = NavigationPath()
        isDetailViewActive = false
        widgetNavigationResolved = true

        DispatchQueue.main.async {
            awaitingWidgetNavigation = false
            widgetNavigationRouter.consume()
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
                    pendingQRLink = .hardware(id: asset.id)
                    selectedTab = .hardware
                } else {
                    pendingQRLink = nil
                    scanErrorMessage = L10n.string("asset_not_found_scanned_value", value)
                    showScanErrorAlert = true
                }
            }

            // QR = Snipe-IT URL; 1D barcode = literal tag (keeps leading zeros).
            if scanResult.type == .qr, let url = URL(string: scannedValue) {
                if let link = SnipeITQRLink.parse(from: url) {
                    handleSnipeITQRLink(link)
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
                        pendingQRLink = .hardware(id: asset.id)
                        selectedTab = .hardware
                    } else if apiClient.assets.isEmpty {
                        Task {
                            await apiClient.fetchPrimaryThenBackground()
                            await MainActor.run {
                                if let asset = findAsset(for: normalized) {
                                    pendingQRLink = .hardware(id: asset.id)
                                    selectedTab = .hardware
                                } else {
                                    pendingQRLink = nil
                                    promptAddDellAsset(url: url, serial: serial)
                                }
                            }
                        }
                    } else {
                        pendingQRLink = nil
                        promptAddDellAsset(url: url, serial: serial)
                    }
                    return
                }

                scanErrorMessage = L10n.string("invalid_qr_unrecognized")
                showScanErrorAlert = true
                return
            }

            // 1D barcode: match raw value against assetTag/serial/altBarcode.
            if let asset = findAsset(for: scannedValue) {
                pendingQRLink = .hardware(id: asset.id)
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

    private func handleSnipeITQRLink(_ link: SnipeITQRLink) {
        switch link {
        case .hardwareByTag(let assetTag):
            Task {
                let asset = await apiClient.fetchHardwareByTag(assetTag: assetTag)
                await MainActor.run {
                    if let asset {
                        if let idx = apiClient.assets.firstIndex(where: { $0.id == asset.id }) {
                            apiClient.assets[idx] = asset
                        } else {
                            apiClient.assets.append(asset)
                        }
                        pendingQRLink = .hardware(id: asset.id)
                        selectedTab = .hardware
                    } else {
                        pendingQRLink = nil
                        scanErrorMessage = L10n.string("asset_not_found_scanned_value", assetTag)
                        showScanErrorAlert = true
                    }
                }
            }

        case .hardware(let id):
            pendingQRLink = link
            selectedTab = .hardware
            if apiClient.assets.first(where: { $0.id == id }) == nil {
                Task {
                    if apiClient.assets.isEmpty {
                        await apiClient.fetchPrimaryThenBackground()
                    }
                    await resolveMissingQRLink(link, id: id)
                }
            }

        case .component(let id):
            stockSelectedSubmoduleRaw = StockSubmodule.components.rawValue
            pendingQRLink = link
            selectedTab = .stock
            if apiClient.components.first(where: { $0.id == id }) == nil {
                Task {
                    if apiClient.components.isEmpty {
                        await apiClient.fetchComponents()
                    }
                    await resolveMissingQRLink(link, id: id)
                }
            }

        case .consumable(let id):
            stockSelectedSubmoduleRaw = StockSubmodule.consumables.rawValue
            pendingQRLink = link
            selectedTab = .stock
            if apiClient.consumables.first(where: { $0.id == id }) == nil {
                Task {
                    if apiClient.consumables.isEmpty {
                        await apiClient.fetchConsumables()
                    }
                    await resolveMissingQRLink(link, id: id)
                }
            }

        case .accessory(let id):
            pendingQRLink = link
            selectedTab = .accessories
            if apiClient.accessories.first(where: { $0.id == id }) == nil {
                Task {
                    if apiClient.accessories.isEmpty {
                        await apiClient.fetchAccessories()
                    }
                    await resolveMissingQRLink(link, id: id)
                }
            }

        case .license(let id):
            pendingQRLink = link
            selectedTab = .licenses
            if apiClient.licenses.first(where: { $0.id == id }) == nil {
                Task {
                    if apiClient.licenses.isEmpty {
                        await apiClient.fetchLicenses()
                    }
                    await resolveMissingQRLink(link, id: id)
                }
            }
        }
    }

    @MainActor
    private func resolveMissingQRLink(_ link: SnipeITQRLink, id: Int) async {
        let resolved: Bool
        switch link {
        case .hardware:
            if apiClient.assets.first(where: { $0.id == id }) != nil {
                resolved = true
            } else if let detailed = await apiClient.fetchHardwareDetails(assetId: id) {
                apiClient.applyUpdatedAsset(detailed)
                resolved = true
            } else {
                resolved = false
            }
        case .component:
            if apiClient.components.first(where: { $0.id == id }) != nil {
                resolved = true
            } else if let detailed = await apiClient.fetchComponentDetails(componentId: id) {
                apiClient.applyUpdatedComponent(detailed)
                resolved = true
            } else {
                resolved = false
            }
        case .consumable:
            if apiClient.consumables.first(where: { $0.id == id }) != nil {
                resolved = true
            } else if let detailed = await apiClient.fetchConsumableDetails(consumableId: id) {
                apiClient.applyUpdatedConsumable(detailed)
                resolved = true
            } else {
                resolved = false
            }
        case .accessory:
            if apiClient.accessories.first(where: { $0.id == id }) != nil {
                resolved = true
            } else if let detailed = await apiClient.fetchAccessoryDetails(accessoryId: id) {
                apiClient.applyUpdatedAccessory(detailed)
                resolved = true
            } else {
                resolved = false
            }
        case .license:
            if apiClient.licenses.first(where: { $0.id == id }) != nil {
                resolved = true
            } else if let detailed = await apiClient.fetchLicenseDetails(licenseId: id) {
                apiClient.applyUpdatedLicense(detailed)
                resolved = true
            } else {
                resolved = false
            }
        case .hardwareByTag:
            resolved = true
        }

        if resolved {
            pendingQRLink = link
        } else {
            pendingQRLink = nil
            scanErrorMessage = link.notFoundMessage(id: id)
            showScanErrorAlert = true
        }
    }

    /// Prompt to create a new asset when a Dell QR has no match in Snipe-IT.
    private func promptAddDellAsset(url: URL, serial: String) {
        pendingDellURLForAdd = url
        pendingDellSerial = serial
        showAddDellAssetPrompt = true
    }
}

// MARK: - Shared navigation destinations

/// Registers detail destinations for every entity type on a single `NavigationStack`,
/// so cross-module links (e.g. user → asset → license) push onto the *current* tab's
/// stack instead of switching tabs. This keeps the native back button and the
/// edge-swipe-to-go-back gesture working as users expect.
private struct AppNavigationDestinations: ViewModifier {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @State private var assetDetailTab = 0
    @State private var accessoryDetailTab = 0
    @State private var licenseDetailTab = 0
    @State private var consumableDetailTab = 0
    @State private var componentDetailTab = 0

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Asset.self) { asset in
                AssetDetailView(
                    asset: asset,
                    apiClient: apiClient,
                    selectedTab: $assetDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { navigationPath.append($0) },
                    onOpenLocation: { navigationPath.append($0) },
                    onOpenLicense: { navigationPath.append($0) },
                    onOpenAccessory: { navigationPath.append($0) },
                    onOpenComponent: { navigationPath.append($0) },
                    onOpenAsset: { navigationPath.append($0) }
                )
            }
            .navigationDestination(for: User.self) { user in
                UserDetailView(
                    user: user,
                    apiClient: apiClient,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenAsset: { navigationPath.append($0) },
                    onOpenAccessory: { navigationPath.append($0) },
                    onOpenLocation: { navigationPath.append($0) },
                    onOpenLicense: { navigationPath.append($0) },
                    onOpenConsumable: { navigationPath.append($0) }
                )
                .id(user.id)
            }
            .navigationDestination(for: Location.self) { location in
                LocationDetailView(
                    location: location,
                    apiClient: apiClient,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { navigationPath.append($0) },
                    onOpenAsset: { navigationPath.append($0) },
                    onOpenAccessory: { navigationPath.append($0) }
                )
                .id(location.id)
            }
            .navigationDestination(for: Accessory.self) { accessory in
                AccessoryDetailView(
                    accessory: accessory,
                    apiClient: apiClient,
                    selectedTab: $accessoryDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { navigationPath.append($0) },
                    onOpenAsset: { navigationPath.append($0) },
                    onOpenLocation: { navigationPath.append($0) }
                )
            }
            .navigationDestination(for: License.self) { license in
                LicenseDetailView(
                    license: license,
                    apiClient: apiClient,
                    selectedTab: $licenseDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { navigationPath.append($0) },
                    onOpenAsset: { navigationPath.append($0) }
                )
            }
            .navigationDestination(for: Consumable.self) { consumable in
                ConsumableDetailView(
                    consumable: consumable,
                    apiClient: apiClient,
                    selectedTab: $consumableDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenUser: { navigationPath.append($0) }
                )
            }
            .navigationDestination(for: Component.self) { component in
                ComponentDetailView(
                    component: component,
                    apiClient: apiClient,
                    selectedTab: $componentDetailTab,
                    isDetailViewActive: $isDetailViewActive,
                    onOpenAsset: { navigationPath.append($0) }
                )
            }
    }
}

extension View {
    /// Attaches the shared detail destinations to the current `NavigationStack`.
    func appNavigationDestinations(
        apiClient: SnipeITAPIClient,
        navigationPath: Binding<NavigationPath>,
        isDetailViewActive: Binding<Bool>
    ) -> some View {
        modifier(AppNavigationDestinations(
            apiClient: apiClient,
            navigationPath: navigationPath,
            isDetailViewActive: isDetailViewActive
        ))
    }
}

// MARK: - Hardware Tab
struct HardwareTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var hasLoadedInitialAssets: Bool
    @Binding var pendingQRLink: SnipeITQRLink?
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var showingAddAsset: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var auditListFilter: AuditListFilter
    @Binding var hardwareSubtab: HardwareAuditSubtab
    @Binding var showTodayOnlyOverride: Bool

    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = false
    @AppStorage("showMaintenance") private var showMaintenance: Bool = true
    @AppStorage("auditNotificationsEnabled") private var auditNotificationsEnabled: Bool = false
    @AppStorage("auditNotificationHour") private var auditNotificationHour: Int = 9
    @AppStorage("auditNotificationMinute") private var auditNotificationMinute: Int = 0
    private let dueSoonDays: Int = 7

    @State private var assetToDelete: Asset?
    @State private var showDeleteConfirm = false
    @State private var isDeletingAsset = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    // Cross-asset maintenance overview (Hardware → Maintenance subtab).
    // The records live in the cached `apiClient.maintenances` list.
    @State private var isLoadingMaintenances = false
    @State private var maintenanceError: String? = nil
    @State private var maintenanceLoadedOnce = false
    @State private var selectedMaintenance: AssetMaintenance? = nil
    @State private var showingAddMaintenance = false
    @State private var showingBulkAudit = false
    @State private var showingBulkLabels = false
    @State private var isSelectingMaintenances = false
    @State private var selectedMaintenanceIds: Set<Int> = []
    @State private var maintenanceFilter: MaintenanceStatusFilter = .all

    // Quick swipe-to-complete from the maintenance overview.
    @State private var maintenanceToComplete: AssetMaintenance?
    @State private var maintenanceCompleteNote = ""
    @State private var isCompletingMaintenanceSwipe = false
    @State private var showMaintenanceCompleteError = false
    @State private var maintenanceCompleteErrorMessage = ""

    // Audit detail sheet from the audit subtab.
    @State private var selectedAuditAsset: Asset?

    // Quick audit completion from the audit list.
    @State private var showAuditCompletionSheet = false
    @State private var auditCompletionAsset: Asset?
    @State private var auditCompletionNextAuditDate: Date = Date()
    @State private var auditCompletionSetDate = true
    @State private var auditCompletionNote = ""
    @State private var auditCompletionImage: UIImage? = nil
    @State private var auditCompletionShowCamera = false
    @State private var isSavingAuditCompletion = false
    @State private var showAuditCompletionErrorAlert = false
    @State private var auditCompletionErrorMessage = ""
    @State private var isOverdueExpanded = false

    // Multi-dimension filter for the normal assets list (status/category/model/…).
    @State private var assetFilter = AssetFilter()

    private var assetFilterOptions: AssetFilterOptions {
        AssetFilterOptions(
            assets: apiClient.assets,
            statusLabels: apiClient.statusLabels,
            categoryNames: apiClient.categories(for: "asset").map { HTMLDecoder.decode($0.name) },
            modelNames: apiClient.models.map { HTMLDecoder.decode($0.name) },
            manufacturerNames: apiClient.manufacturers.map { HTMLDecoder.decode($0.name) },
            locationNames: apiClient.locations.map(\.decodedName)
        )
    }

    private var searchFilteredAssets: [Asset] {
        var assets = apiClient.assets
        if assetFilter.isActive {
            assets = assets.filter { assetFilter.matches($0, statusLabels: apiClient.statusLabels) }
        }
        if searchText.isEmpty { return assets }
        return assets.filter { SearchHelpers.assetMatches($0, query: searchText) }
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
            records = records.filter { SearchHelpers.maintenanceMatches($0, query: searchText) }
        }
        return records
    }

    private var selectableMaintenances: [AssetMaintenance] {
        MaintenanceBulkCompleter.inProgress(from: displayedMaintenances)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            hardwareTabContent
                .background(Color(.systemBackground).ignoresSafeArea())
        }
        .syncTabBarWithNavigationPath(navigationPath)
        .onAppear {
            // Initial sync is owned by the parent.
            if apiClient.isConfigured,
               apiClient.statusLabels.isEmpty
                || apiClient.manufacturers.isEmpty
                || apiClient.categories.isEmpty
                || apiClient.models.isEmpty {
                Task { await apiClient.fetchListFilterCatalogs() }
            }
            tryPushPendingQRLink()
        }
        .onChange(of: pendingQRLink) { _, _ in
            tryPushPendingQRLink()
        }
        .onChange(of: apiClient.assets) { _, _ in
            tryPushPendingQRLink()
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
                selectedImage: $auditCompletionImage,
                showCamera: $auditCompletionShowCamera,
                confirmTitle: L10n.string("complete_audit"),
                isSaving: isSavingAuditCompletion,
                onSave: { Task { await saveAuditCompletionFromList() } }
            )
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
            note: noteOpt,
            image: auditCompletionImage
        )
        if ok {
            showAuditCompletionSheet = false
            auditCompletionAsset = nil
            auditCompletionNote = ""
            auditCompletionImage = nil
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
                if isMaintenanceSubtabActive && isSelectingMaintenances {
                    EmptyView()
                } else if showMaintenance || enableAuditSubtab {
                    Menu {
                        Button {
                            showingAddAsset = true
                        } label: {
                            Label(L10n.string("add_asset"), systemImage: "laptopcomputer")
                        }
                        if showMaintenance {
                            Button {
                                showingAddMaintenance = true
                            } label: {
                                Label(L10n.string("add_maintenance"), systemImage: "wrench.and.screwdriver")
                            }
                        }
                        if enableAuditSubtab {
                            Button {
                                showingBulkAudit = true
                            } label: {
                                Label(L10n.string("add_audit"), systemImage: "checklist")
                            }
                        }
                        Button {
                            showingBulkLabels = true
                        } label: {
                            Label(L10n.string("generate_labels"), systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(L10n.string("add"))
                } else {
                    Menu {
                        Button {
                            showingAddAsset = true
                        } label: {
                            Label(L10n.string("add_asset"), systemImage: "laptopcomputer")
                        }
                        Button {
                            showingBulkLabels = true
                        } label: {
                            Label(L10n.string("generate_labels"), systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel(L10n.string("add"))
                }
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
                apiClient.clearRefreshError()
                if isMaintenanceSubtabActive {
                    await loadAllMaintenances(force: true)
                } else {
                    await apiClient.fetchAssets()
                    await apiClient.fetchListFilterCatalogs()
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
        .sheet(isPresented: $showingAddMaintenance, onDismiss: {
            Task { await loadAllMaintenances(force: true) }
        }) {
            BulkMaintenanceFormSheet(apiClient: apiClient)
        }
        .sheet(isPresented: $showingBulkAudit) {
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
        }
        .sheet(isPresented: $showingBulkLabels) {
            BulkLabelView(apiClient: apiClient)
        }
        .sheet(item: $selectedMaintenance, onDismiss: {
            Task { await loadAllMaintenances(force: true) }
        }) { record in
            MaintenanceDetailSheet(
                apiClient: apiClient,
                assetId: record.assetId ?? 0,
                record: record,
                onMutated: {
                    Task { await loadAllMaintenances(force: true) }
                }
            )
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
        .onChange(of: hardwareSubtab) { _, newValue in
            if newValue == .maintenance {
                Task { await loadAllMaintenances() }
            }
        }
        .onAppear {
            if isMaintenanceSubtabActive {
                Task { await loadAllMaintenances() }
            }
        }
        .maintenanceBulkSelection(
            isActive: isMaintenanceSubtabActive,
            selectableRecords: selectableMaintenances,
            apiClient: apiClient,
            isSelecting: $isSelectingMaintenances,
            selectedIds: $selectedMaintenanceIds,
            onRefresh: { await loadAllMaintenances(force: true) }
        )
        .appNavigationDestinations(apiClient: apiClient, navigationPath: $navigationPath, isDetailViewActive: $isDetailViewActive)
        .alert(L10n.string("delete_asset_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L10n.string("cancel"), role: .cancel) {
                assetToDelete = nil
            }
            Button(L10n.string("delete"), role: .destructive) {
                guard let a = assetToDelete else { return }
                Task {
                    isDeletingAsset = true
                    let ok = await apiClient.deleteAsset(assetId: a.id)
                    isDeletingAsset = false
                    if !ok {
                        deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
                        showDeleteError = true
                    }
                    assetToDelete = nil
                }
            }
        } message: {
            if let a = assetToDelete {
                Text(
                    a.assignedTo != nil
                        ? L10n.string("delete_asset_confirm_message_checked_out", a.decodedAssetTag)
                        : L10n.string("delete_asset_confirm_message", a.decodedAssetTag)
                )
            }
        }
        .alert(L10n.string("delete_failed"), isPresented: $showDeleteError) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
        .overlay {
            if isDeletingAsset {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView(L10n.string("deleting"))
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var isHardwareListContentEmpty: Bool {
        if isMaintenanceSubtabActive {
            // Maintenance handles its own loading/empty states inline.
            return false
        }
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
        (searchText.isEmpty && !assetFilter.isActive) ? L10n.string("no_assets") : L10n.string("no_assets_match")
    }

    private var hardwareAssetList: some View {
        let showLoadingPlaceholder = apiClient.isLoading && !isRefreshing && apiClient.assets.isEmpty
        return List {
            if showSubtabPicker {
                Section {
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
                    if isMaintenanceSubtabActive {
                        Label("\(displayedMaintenances.count)", systemImage: "wrench.and.screwdriver")
                            .foregroundStyle(.primary)
                        Spacer()
                        maintenanceFilterMenu
                    } else if isAuditSubtabActive {
                        Label("\(auditOverviewCount)", systemImage: "checkmark.seal")
                            .foregroundStyle(.primary)
                        Spacer()
                    } else {
                        Label("\(searchFilteredAssets.count)", systemImage: "laptopcomputer")
                            .foregroundStyle(.primary)
                        Spacer()
                        if assetFilterOptions.hasFilterOptions {
                            AssetFilterMenu(filter: $assetFilter, options: assetFilterOptions)
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            if isMaintenanceSubtabActive {
                maintenanceSubtabSections
            } else if showLoadingPlaceholder {
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
        .browseListBackground()
        .listSectionSpacing(0)
        .listSectionSeparator(.hidden)
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
            } else if showLoadingPlaceholder {
                ProgressView(L10n.string("loading_assets"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if isHardwareListContentEmpty && apiClient.isConfigured && !apiClient.isLoading && apiClient.hasCompletedInitialLoad {
                ContentUnavailableView(hardwareEmptyTitle, systemImage: "laptopcomputer")
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

    @ViewBuilder
    private var maintenanceSubtabSections: some View {
        Section {
            ForEach(displayedMaintenances) { record in
                MaintenanceOverviewRow(
                    record: record,
                    linkedAsset: linkedAsset(for: record),
                    isSelecting: isSelectingMaintenances,
                    isSelected: selectedMaintenanceIds.contains(record.id),
                    onTap: { handleMaintenanceOverviewTap(record) }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .listRowBackground(Color.clear)
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

    @ViewBuilder
    private func auditAssetRow(_ asset: Asset) -> some View {
        let isAuditTabActive = enableAuditSubtab && hardwareSubtab == .audit

        Button {
            if isAuditTabActive {
                selectedAuditAsset = asset
            } else {
                navigationPath.append(asset)
            }
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
                    auditCompletionNextAuditDate = AuditDateClassifier.nextAuditDateGMT(asset) ?? Date()
                    auditCompletionSetDate = true
                    auditCompletionNote = ""
                    auditCompletionImage = nil
                    showAuditCompletionSheet = true
                } label: {
                    Label(L10n.string("mark_complete"), systemImage: "checkmark.seal")
                }
                .tint(.green)
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

    private func tryPushPendingQRLink() {
        guard case .hardware(let id) = pendingQRLink,
              let asset = apiClient.assets.first(where: { $0.id == id }) else { return }
        navigationPath.append(asset)
        pendingQRLink = nil
    }
}

// MARK: - Accessories Tab

struct AccessoriesTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var showingAddAccessory: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingQRLink: SnipeITQRLink?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            AccessoriesContent(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                navigationPath: $navigationPath
            )
            .onAppear {
                isDetailViewActive = false
                tryPushPendingQRLink()
            }
            .onChange(of: pendingQRLink) { _, _ in tryPushPendingQRLink() }
            .onChange(of: apiClient.accessories) { _, _ in tryPushPendingQRLink() }
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
                    await apiClient.fetchListFilterCatalogs()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .appNavigationDestinations(apiClient: apiClient, navigationPath: $navigationPath, isDetailViewActive: $isDetailViewActive)
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .syncTabBarWithNavigationPath(navigationPath)
    }

    private func tryPushPendingQRLink() {
        guard case .accessory(let id) = pendingQRLink,
              let accessory = apiClient.accessories.first(where: { $0.id == id }) else { return }
        navigationPath.append(accessory)
        pendingQRLink = nil
    }
}

// MARK: - Licenses Tab

struct LicensesTab: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingQRLink: SnipeITQRLink?

    @State private var showingAddLicense = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            LicensesContent(
                apiClient: apiClient,
                searchText: $searchText,
                isRefreshing: $isRefreshing,
                navigationPath: $navigationPath
            )
            .onAppear {
                isDetailViewActive = false
                tryPushPendingQRLink()
            }
            .onChange(of: pendingQRLink) { _, _ in tryPushPendingQRLink() }
            .onChange(of: apiClient.licenses) { _, _ in tryPushPendingQRLink() }
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
                    await apiClient.fetchListFilterCatalogs()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .appNavigationDestinations(apiClient: apiClient, navigationPath: $navigationPath, isDetailViewActive: $isDetailViewActive)
            .background(Color(.systemBackground).ignoresSafeArea())
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
        .syncTabBarWithNavigationPath(navigationPath)
    }

    private func tryPushPendingQRLink() {
        guard case .license(let id) = pendingQRLink,
              let license = apiClient.licenses.first(where: { $0.id == id }) else { return }
        navigationPath.append(license)
        pendingQRLink = nil
    }
}

private struct LicensesContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

    @State private var filter = ListFilter()
    @State private var itemToDelete: License?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    private var dimensions: [FilterDimension<License>] {
        [
            FilterDimension(title: L10n.string("category")) { $0.decodedCategoryName },
            FilterDimension(title: L10n.string("manufacturer")) { $0.decodedManufacturerName },
            FilterDimension(title: L10n.string("supplier")) { $0.decodedSupplierName },
            FilterDimension(title: L10n.string("company")) { $0.decodedCompanyName }
        ]
    }

    private var filterOptions: [(title: String, values: [String])] {
        [
            (
                L10n.string("category"),
                listFilterValues(
                    catalog: apiClient.categories(for: "license").map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.licenses.map(\.decodedCategoryName)
                )
            ),
            (
                L10n.string("manufacturer"),
                listFilterValues(
                    catalog: apiClient.manufacturers.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.licenses.map(\.decodedManufacturerName)
                )
            ),
            (
                L10n.string("supplier"),
                listFilterValues(
                    catalog: apiClient.suppliers.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.licenses.map(\.decodedSupplierName)
                )
            ),
            (
                L10n.string("company"),
                listFilterValues(
                    catalog: apiClient.companies.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.licenses.map(\.decodedCompanyName)
                )
            )
        ]
    }

    var filteredLicenses: [License] {
        var items = apiClient.licenses
        if filter.isActive {
            items = items.filter { filter.matches($0, dimensions: dimensions) }
        }
        if searchText.isEmpty { return items }
        return items.filter { SearchHelpers.licenseMatches($0, query: searchText) }
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
                            Label("\(filteredLicenses.count)", systemImage: "doc.text.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            ListFilterMenu(filter: $filter, options: filterOptions)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    itemToDelete = license
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string("delete"), systemImage: "trash")
                                }
                            }
                        }
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
                .alert(
                    itemToDelete.map { L10n.string("delete_item_confirm_title", $0.decodedName) } ?? L10n.string("delete"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(L10n.string("cancel"), role: .cancel) { itemToDelete = nil }
                    Button(L10n.string("delete"), role: .destructive) {
                        guard let item = itemToDelete else { return }
                        Task {
                            isDeleting = true
                            let ok = await apiClient.deleteLicense(licenseId: item.id)
                            isDeleting = false
                            if !ok {
                                deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
                                showDeleteError = true
                            }
                            itemToDelete = nil
                        }
                    }
                } message: {
                    if let item = itemToDelete {
                        let hasAssignments = (item.seats ?? 0) > (item.freeSeatsCount ?? item.remaining ?? item.seats ?? 0)
                        Text(
                            hasAssignments
                                ? L10n.string("delete_item_confirm_message_with_checkin", item.decodedName)
                                : L10n.string("delete_item_confirm_message", item.decodedName)
                        )
                    }
                }
                .alert(L10n.string("delete_failed"), isPresented: $showDeleteError) {
                    Button(L10n.string("ok"), role: .cancel) {}
                } message: {
                    Text(deleteErrorMessage)
                }
                .overlay {
                    if isDeleting {
                        ProgressView(L10n.string("deleting"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
    @Binding var showingSettings: Bool
    @Binding var showingScanner: Bool
    @Binding var navigationPath: NavigationPath
    @Binding var isDetailViewActive: Bool
    @Binding var pendingQRLink: SnipeITQRLink?

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
            .onAppear {
                isDetailViewActive = false
                tryPushPendingQRLink()
            }
            .onChange(of: pendingQRLink) { _, _ in tryPushPendingQRLink() }
            .onChange(of: apiClient.components) { _, _ in tryPushPendingQRLink() }
            .onChange(of: apiClient.consumables) { _, _ in tryPushPendingQRLink() }
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
                    await apiClient.fetchListFilterCatalogs()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .appNavigationDestinations(apiClient: apiClient, navigationPath: $navigationPath, isDetailViewActive: $isDetailViewActive)
            .background(Color(.systemBackground).ignoresSafeArea())
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
        .syncTabBarWithNavigationPath(navigationPath)
    }

    private func tryPushPendingQRLink() {
        switch pendingQRLink {
        case .component(let id):
            guard selectedSubmodule == .components,
                  let component = apiClient.components.first(where: { $0.id == id }) else { return }
            navigationPath.append(component)
            pendingQRLink = nil
        case .consumable(let id):
            guard selectedSubmodule == .consumables,
                  let consumable = apiClient.consumables.first(where: { $0.id == id }) else { return }
            navigationPath.append(consumable)
            pendingQRLink = nil
        default:
            return
        }
    }
}

private struct ConsumablesContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

    @State private var filter = ListFilter()
    @State private var itemToDelete: Consumable?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    private var dimensions: [FilterDimension<Consumable>] {
        [
            FilterDimension(title: L10n.string("category")) { $0.decodedCategoryName },
            FilterDimension(title: L10n.string("manufacturer")) { $0.decodedManufacturerName },
            FilterDimension(title: L10n.string("company")) { $0.decodedCompanyName },
            FilterDimension(title: L10n.string("location")) { $0.decodedLocationName }
        ]
    }

    private var filterOptions: [(title: String, values: [String])] {
        [
            (
                L10n.string("category"),
                listFilterValues(
                    catalog: apiClient.categories(for: "consumable").map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.consumables.map(\.decodedCategoryName)
                )
            ),
            (
                L10n.string("manufacturer"),
                listFilterValues(
                    catalog: apiClient.manufacturers.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.consumables.map(\.decodedManufacturerName)
                )
            ),
            (
                L10n.string("company"),
                listFilterValues(
                    catalog: apiClient.companies.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.consumables.map(\.decodedCompanyName)
                )
            ),
            (
                L10n.string("location"),
                listFilterValues(
                    catalog: apiClient.locations.map(\.decodedName),
                    itemValues: apiClient.consumables.map(\.decodedLocationName)
                )
            )
        ]
    }

    var filteredConsumables: [Consumable] {
        var items = apiClient.consumables
        if filter.isActive {
            items = items.filter { filter.matches($0, dimensions: dimensions) }
        }
        if searchText.isEmpty { return items }
        return items.filter { SearchHelpers.consumableMatches($0, query: searchText) }
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
                            Label("\(filteredConsumables.count)", systemImage: "shippingbox")
                                .foregroundStyle(.primary)
                            Spacer()
                            ListFilterMenu(filter: $filter, options: filterOptions)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    itemToDelete = consumable
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string("delete"), systemImage: "trash")
                                }
                            }
                        }
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
                .alert(
                    itemToDelete.map { L10n.string("delete_item_confirm_title", $0.decodedName) } ?? L10n.string("delete"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(L10n.string("cancel"), role: .cancel) { itemToDelete = nil }
                    Button(L10n.string("delete"), role: .destructive) {
                        guard let item = itemToDelete else { return }
                        Task {
                            isDeleting = true
                            let ok = await apiClient.deleteConsumable(consumableId: item.id)
                            isDeleting = false
                            if !ok {
                                deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
                                showDeleteError = true
                            }
                            itemToDelete = nil
                        }
                    }
                } message: {
                    if let item = itemToDelete {
                        Text(L10n.string("delete_consumable_confirm_message", item.decodedName))
                    }
                }
                .alert(L10n.string("delete_failed"), isPresented: $showDeleteError) {
                    Button(L10n.string("ok"), role: .cancel) {}
                } message: {
                    Text(deleteErrorMessage)
                }
                .overlay {
                    if isDeleting {
                        ProgressView(L10n.string("deleting"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    @State private var filter = ListFilter()
    @State private var itemToDelete: Component?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    private var dimensions: [FilterDimension<Component>] {
        [
            FilterDimension(title: L10n.string("category")) { $0.decodedCategoryName },
            FilterDimension(title: L10n.string("manufacturer")) { $0.decodedManufacturerName },
            FilterDimension(title: L10n.string("company")) { $0.decodedCompanyName },
            FilterDimension(title: L10n.string("location")) { $0.decodedLocationName }
        ]
    }

    private var filterOptions: [(title: String, values: [String])] {
        [
            (
                L10n.string("category"),
                listFilterValues(
                    catalog: apiClient.categories(for: "component").map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.components.map(\.decodedCategoryName)
                )
            ),
            (
                L10n.string("manufacturer"),
                listFilterValues(
                    catalog: apiClient.manufacturers.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.components.map(\.decodedManufacturerName)
                )
            ),
            (
                L10n.string("company"),
                listFilterValues(
                    catalog: apiClient.companies.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.components.map(\.decodedCompanyName)
                )
            ),
            (
                L10n.string("location"),
                listFilterValues(
                    catalog: apiClient.locations.map(\.decodedName),
                    itemValues: apiClient.components.map(\.decodedLocationName)
                )
            )
        ]
    }

    var filteredComponents: [Component] {
        var items = apiClient.components
        if filter.isActive {
            items = items.filter { filter.matches($0, dimensions: dimensions) }
        }
        if searchText.isEmpty { return items }
        return items.filter { SearchHelpers.componentMatches($0, query: searchText) }
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
                            Label("\(filteredComponents.count)", systemImage: "cpu")
                                .foregroundStyle(.primary)
                            Spacer()
                            ListFilterMenu(filter: $filter, options: filterOptions)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    itemToDelete = component
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string("delete"), systemImage: "trash")
                                }
                            }
                        }
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
                .alert(
                    itemToDelete.map { L10n.string("delete_item_confirm_title", $0.decodedName) } ?? L10n.string("delete"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(L10n.string("cancel"), role: .cancel) { itemToDelete = nil }
                    Button(L10n.string("delete"), role: .destructive) {
                        guard let item = itemToDelete else { return }
                        Task {
                            isDeleting = true
                            let ok = await apiClient.deleteComponent(componentId: item.id)
                            isDeleting = false
                            if !ok {
                                deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
                                showDeleteError = true
                            }
                            itemToDelete = nil
                        }
                    }
                } message: {
                    if let item = itemToDelete {
                        let remaining = item.remaining ?? item.qty ?? 0
                        let qty = item.qty ?? remaining
                        Text(
                            remaining < qty
                                ? L10n.string("delete_component_confirm_message_with_checkin", item.decodedName)
                                : L10n.string("delete_item_confirm_message", item.decodedName)
                        )
                    }
                }
                .alert(L10n.string("delete_failed"), isPresented: $showDeleteError) {
                    Button(L10n.string("ok"), role: .cancel) {}
                } message: {
                    Text(deleteErrorMessage)
                }
                .overlay {
                    if isDeleting {
                        ProgressView(L10n.string("deleting"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    @State private var filter = ListFilter()
    @State private var itemToDelete: Accessory?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    private var dimensions: [FilterDimension<Accessory>] {
        [
            FilterDimension(title: L10n.string("category")) { $0.decodedCategoryName },
            FilterDimension(title: L10n.string("manufacturer")) { $0.decodedManufacturerName },
            FilterDimension(title: L10n.string("location")) { $0.decodedLocationName }
        ]
    }

    private var filterOptions: [(title: String, values: [String])] {
        [
            (
                L10n.string("category"),
                listFilterValues(
                    catalog: apiClient.categories(for: "accessory").map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.accessories.map(\.decodedCategoryName)
                )
            ),
            (
                L10n.string("manufacturer"),
                listFilterValues(
                    catalog: apiClient.manufacturers.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.accessories.map(\.decodedManufacturerName)
                )
            ),
            (
                L10n.string("location"),
                listFilterValues(
                    catalog: apiClient.locations.map(\.decodedName),
                    itemValues: apiClient.accessories.map(\.decodedLocationName)
                )
            )
        ]
    }

    var filteredAccessories: [Accessory] {
        var items = apiClient.accessories
        if filter.isActive {
            items = items.filter { filter.matches($0, dimensions: dimensions) }
        }
        if searchText.isEmpty { return items }
        return items.filter { SearchHelpers.accessoryMatches($0, query: searchText) }
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
                            Label("\(filteredAccessories.count)", systemImage: "mediastick")
                                .foregroundStyle(.primary)
                            Spacer()
                            ListFilterMenu(filter: $filter, options: filterOptions)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    itemToDelete = accessory
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string("delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .browseListBackground()
                .listSectionSpacing(.compact)
                .listSectionSeparator(.hidden)
                .moduleEmptyOverlay(
                    isVisible: filteredAccessories.isEmpty && apiClient.isConfigured && !apiClient.isLoading,
                    title: L10n.string("no_accessories"),
                    systemImage: "mediastick"
                )
                .alert(
                    itemToDelete.map { L10n.string("delete_item_confirm_title", $0.decodedName) } ?? L10n.string("delete"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(L10n.string("cancel"), role: .cancel) { itemToDelete = nil }
                    Button(L10n.string("delete"), role: .destructive) {
                        guard let item = itemToDelete else { return }
                        Task {
                            isDeleting = true
                            let ok = await apiClient.deleteAccessory(accessoryId: item.id)
                            isDeleting = false
                            if !ok {
                                deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
                                showDeleteError = true
                            }
                            itemToDelete = nil
                        }
                    }
                } message: {
                    if let item = itemToDelete {
                        Text(
                            (item.checkoutsCount ?? 0) > 0
                                ? L10n.string("delete_item_confirm_message_with_checkin", item.decodedName)
                                : L10n.string("delete_item_confirm_message", item.decodedName)
                        )
                    }
                }
                .alert(L10n.string("delete_failed"), isPresented: $showDeleteError) {
                    Button(L10n.string("ok"), role: .cancel) {}
                } message: {
                    Text(deleteErrorMessage)
                }
                .overlay {
                    if isDeleting {
                        ProgressView(L10n.string("deleting"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
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
                        await apiClient.fetchListFilterCatalogs()
                    case .locations:
                        await apiClient.fetchLocations()
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isRefreshing = false
                }
            }
            .appNavigationDestinations(apiClient: apiClient, navigationPath: $navigationPath, isDetailViewActive: $isDetailViewActive)
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .syncTabBarWithNavigationPath(navigationPath)
    }
}

private struct UsersContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

    @State private var filter = ListFilter()
    @State private var itemToDelete: User?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    private var dimensions: [FilterDimension<User>] {
        [
            FilterDimension(title: L10n.string("company")) { $0.decodedCompanyName },
            FilterDimension(title: L10n.string("location")) { $0.decodedLocationName },
            FilterDimension(title: L10n.string("job_title")) { $0.decodedJobtitle }
        ]
    }

    private var filterOptions: [(title: String, values: [String])] {
        [
            (
                L10n.string("company"),
                listFilterValues(
                    catalog: apiClient.companies.map { HTMLDecoder.decode($0.name) },
                    itemValues: apiClient.users.map(\.decodedCompanyName)
                )
            ),
            (
                L10n.string("location"),
                listFilterValues(
                    catalog: apiClient.locations.map(\.decodedName),
                    itemValues: apiClient.users.map(\.decodedLocationName)
                )
            ),
            (
                L10n.string("job_title"),
                distinctSortedFilterValues(apiClient.users.map(\.decodedJobtitle))
            )
        ]
    }

    var filteredUsers: [User] {
        var items = apiClient.users
        if filter.isActive {
            items = items.filter { filter.matches($0, dimensions: dimensions) }
        }
        if searchText.isEmpty { return items }
        return items.filter { SearchHelpers.userMatches($0, query: searchText) }
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
                            Label("\(filteredUsers.count)", systemImage: "person.2")
                                .foregroundStyle(.primary)
                            Spacer()
                            ListFilterMenu(filter: $filter, options: filterOptions)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    itemToDelete = user
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string("delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .browseListBackground()
                .listSectionSpacing(.compact)
                .listSectionSeparator(.hidden)
                .moduleEmptyOverlay(
                    isVisible: filteredUsers.isEmpty && apiClient.isConfigured && !apiClient.isLoading,
                    title: L10n.string("no_users"),
                    systemImage: "person.2"
                )
                .alert(
                    itemToDelete.map { L10n.string("delete_item_confirm_title", $0.decodedName) } ?? L10n.string("delete"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(L10n.string("cancel"), role: .cancel) { itemToDelete = nil }
                    Button(L10n.string("delete"), role: .destructive) {
                        guard let item = itemToDelete else { return }
                        Task {
                            isDeleting = true
                            let ok = await apiClient.deleteUser(userId: item.id)
                            isDeleting = false
                            if !ok {
                                deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
                                showDeleteError = true
                            }
                            itemToDelete = nil
                        }
                    }
                } message: {
                    if let item = itemToDelete {
                        Text(L10n.string("delete_user_confirm_message", item.decodedName))
                    }
                }
                .alert(L10n.string("delete_failed"), isPresented: $showDeleteError) {
                    Button(L10n.string("ok"), role: .cancel) {}
                } message: {
                    Text(deleteErrorMessage)
                }
                .overlay {
                    if isDeleting {
                        ProgressView(L10n.string("deleting"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

private struct LocationsContent: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var searchText: String
    @Binding var isRefreshing: Bool
    @Binding var navigationPath: NavigationPath

    @State private var itemToDelete: Location?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""

    var filteredLocations: [Location] {
        if searchText.isEmpty { return apiClient.locations }
        return apiClient.locations.filter { SearchHelpers.locationMatches($0, query: searchText) }
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    itemToDelete = location
                                    showDeleteConfirm = true
                                } label: {
                                    Label(L10n.string("delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .browseListBackground()
                .listSectionSpacing(.compact)
                .listSectionSeparator(.hidden)
                .moduleEmptyOverlay(
                    isVisible: filteredLocations.isEmpty && apiClient.isConfigured && !apiClient.isLoading,
                    title: L10n.string("no_locations"),
                    systemImage: "mappin.and.ellipse"
                )
                .alert(
                    itemToDelete.map { L10n.string("delete_item_confirm_title", $0.decodedName) } ?? L10n.string("delete"),
                    isPresented: $showDeleteConfirm
                ) {
                    Button(L10n.string("cancel"), role: .cancel) { itemToDelete = nil }
                    Button(L10n.string("delete"), role: .destructive) {
                        guard let item = itemToDelete else { return }
                        Task {
                            isDeleting = true
                            let ok = await apiClient.deleteLocation(locationId: item.id)
                            isDeleting = false
                            if !ok {
                                deleteErrorMessage = apiClient.lastApiMessage ?? L10n.string("delete_failed")
                                showDeleteError = true
                            }
                            itemToDelete = nil
                        }
                    }
                } message: {
                    if let item = itemToDelete {
                        Text(L10n.string("delete_location_confirm_message", item.decodedName))
                    }
                }
                .alert(L10n.string("delete_failed"), isPresented: $showDeleteError) {
                    Button(L10n.string("ok"), role: .cancel) {}
                } message: {
                    Text(deleteErrorMessage)
                }
                .overlay {
                    if isDeleting {
                        ProgressView(L10n.string("deleting"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

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
