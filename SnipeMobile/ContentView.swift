import SwiftUI
import AVFoundation
import Foundation

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
        // "Komende N dagen" als: morgen tot en met (N-1) dagen later.
        // Met dueSoonDays=7: morgen..vandaag+6.
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
    @State private var userDetailTab: Int = 0
    @State private var locationDetailTab: Int = 0
    @State private var accessoryDetailTab: Int = 0
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
    @State private var returnToTab: MainTab?
    @State private var hardwarePath = NavigationPath()
    @State private var usersPath = NavigationPath()
    @State private var locationsPath = NavigationPath()
    @State private var accessoriesPath = NavigationPath()
    /// Detail on stack. Tab bar stays visible.
    @State private var isDetailViewActive = false
    @State private var showScanErrorAlert = false
    @State private var scanErrorMessage: String?
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true
    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = true
    @State private var awaitingAuditNavigationResolution = false
    @State private var auditNotificationNavResolved = false

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
                auditListFilter: $auditListFilter,
                hardwareSubtab: $hardwareSubtab,
                showTodayOnlyOverride: $showTodayOnlyOverride,
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
            case .users: usersPath = NavigationPath()
            case .locations: locationsPath = NavigationPath()
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

            // Cold boot: `pendingRequest` kan al gezet zijn vóórdat `onChange` afvuurt.
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
                    // Ensure navigation can find the asset in `apiClient.assets`.
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

            // Try QR handling first when the scanned payload parses as a URL.
            if let url = URL(string: scannedValue) {
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
                        // Fallback: when label content is (mis)configured, treat the extracted numeric
                        // segment as an `asset_tag` instead of an internal asset `id`.
                        // Only do this for non-QR scans.
                        if scanResult.type != .qr {
                            Task { await openHardwareForScannedValueByTag(String(id)) }
                        } else {
                            scannedAssetId = nil
                            scanErrorMessage = L10n.string("asset_not_found_id", String(id))
                            showScanErrorAlert = true
                        }
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
                                    scanErrorMessage = L10n.string("asset_not_found_serial", serial)
                                    showScanErrorAlert = true
                                }
                            }
                        }
                    } else {
                        scannedAssetId = nil
                        scanErrorMessage = L10n.string("asset_not_found_serial", serial)
                        showScanErrorAlert = true
                    }
                    return
                }

                // bytag URL: https://.../hardware/bytag?assetTag=XYZ
                if let assetTag = extractAssetTagFromByTagURL(from: url) {
                    Task {
                        let asset = await apiClient.fetchHardwareByTag(assetTag: assetTag)
                        await MainActor.run {
                            if let asset {
                                // Ensure navigation can find the asset in `apiClient.assets`.
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

    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = true
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
            warranty_months: nil
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
                await apiClient.fetchPrimaryThenBackground()
                try? await Task.sleep(nanoseconds: 300_000_000)
                isRefreshing = false
            }
        }
        .navigationDestination(for: Asset.self) { asset in
            AssetDetailView(asset: asset, apiClient: apiClient, selectedTab: $assetDetailTab, isDetailViewActive: $isDetailViewActive, returnToTab: returnToTab, onBackToPrevious: onBackToPreviousTab, onOpenUser: onOpenUser, onOpenLocation: onOpenLocation)
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
                    } else {
                        Section {
                            Text(L10n.string("no_assets"))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 16)
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
                    } else {
                        Section {
                            Text(L10n.string("no_assets"))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 16)
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
                if assetsToShow.isEmpty {
                    Section {
                        Text(L10n.string("no_assets"))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 16)
                    }
                } else {
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
        // Extra bottom padding so the tab bar doesn't overlap the content.
        .padding(.bottom, 12)
        .overlay {
            if showLoadingPlaceholder {
                ProgressView(L10n.string("loading_assets"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        return apiClient.locations.filter { $0.decodedName.lowercased().contains(searchText.lowercased()) }
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
