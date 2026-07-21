import Foundation
import SwiftUI

#if !DEBUG
private func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

@MainActor
class SnipeITAPIClient: ObservableObject {
    @Published var assets: [Asset] = [] { didSet { scheduleCacheSave() } }
    @Published var users: [User] = [] { didSet { scheduleCacheSave() } }
    @Published var currentUser: User? { didSet { scheduleCacheSave() } }
    @Published var accessories: [Accessory] = [] { didSet { scheduleCacheSave() } }
    @Published var licenses: [License] = [] { didSet { scheduleCacheSave() } }
    @Published var consumables: [Consumable] = [] { didSet { scheduleCacheSave() } }
    @Published var components: [Component] = [] { didSet { scheduleCacheSave() } }
    @Published var locations: [Location] = [] { didSet { scheduleCacheSave() } }
    @Published var companies: [Company] = [] { didSet { scheduleCacheSave() } }
    @Published var groups: [UserGroup] = []
    @Published var manufacturers: [Manufacturer] = [] { didSet { scheduleCacheSave() } }
    @Published var suppliers: [Supplier] = [] { didSet { scheduleCacheSave() } }
    @Published var depreciations: [DepreciationRow] = []
    @Published var maintenances: [AssetMaintenance] = [] { didSet { scheduleCacheSave() } }
    @Published var maintenanceTypes: [MaintenanceType] = []
    /// `.legacy` = pre–maintenance-types API; `.typeIds` = Snipe-IT 8.x requires `maintenance_type_id`.
    enum MaintenanceTypesMode: Equatable {
        case unknown
        case legacy
        case typeIds
    }
    @Published private(set) var maintenanceTypesMode: MaintenanceTypesMode = .unknown
    @Published var errorMessage: String?
    @Published var lastApiMessage: String?
    @Published var isConfigured: Bool {
        didSet {
            UserDefaults.standard.set(isConfigured, forKey: "isConfigured")
        }
    }
    @Published var isLoading: Bool = false
    // True after the cache loads or the first sync finishes; gates the empty state.
    @Published var hasCompletedInitialLoad: Bool = false
    // Transient notice for a failed refresh (maintenance / unreachable). Cached data stays.
    @Published var refreshErrorMessage: String?
    @Published var statusLabels: [StatusLabel] = [] { didSet { scheduleCacheSave() } }

    /// Asset ids to re-fetch by id after bulk list sync (avoids stale status/assignment).
    private var assetsPendingDetailRefresh: Set<Int> = []

    /// Progress of an ongoing paginated fetch. `total` is -1 if unknown.
    @Published var loadingProgress: (current: Int, total: Int)? = nil

    var baseURL: String {
        normalizeBaseURL(UserDefaults.standard.string(forKey: "baseURL") ?? "")
    }
    private var apiToken: String {
        KeychainSecretStore.string(for: .apiToken)
    }

    private var fetchAssetsTask: Task<Void, Never>? = nil
    private var fetchAssetsGeneration: Int = 0

    // MARK: - Local disk cache

    // Debounced write so a burst of list mutations only hits disk once.
    private var cacheSaveTask: Task<Void, Never>? = nil
    // Set while reading from disk so the didSet hooks don't re-save what we just read.
    private var isApplyingCache: Bool = false

    private var cacheKey: String {
        LocalCacheStore.key(forBaseURL: baseURL)
    }

    private func scheduleCacheSave() {
        guard !isApplyingCache, isConfigured, !baseURL.isEmpty else { return }
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            await self?.persistCacheNow()
        }
    }

    // Write the current lists to disk; encoding runs off the main thread.
    private func persistCacheNow() async {
        guard isConfigured, !baseURL.isEmpty else { return }
        let snapshot = SnipeDataCacheSnapshot(
            assets: assets,
            users: users,
            currentUser: currentUser,
            accessories: accessories,
            licenses: licenses,
            consumables: consumables,
            components: components,
            locations: locations,
            companies: companies,
            manufacturers: manufacturers,
            suppliers: suppliers,
            statusLabels: statusLabels,
            maintenances: maintenances
        )
        let key = cacheKey
        await Task.detached(priority: .utility) {
            LocalCacheStore.save(snapshot, key: key)
        }.value
        WidgetSnapshotBuilder.update(from: snapshot, baseURL: baseURL, isConfigured: isConfigured)
        WidgetBackgroundRefreshService.scheduleNextRefresh()
    }

    // Fill empty lists from disk so the UI renders instantly on launch.
    func loadCachedDataIfAvailable() {
        guard isConfigured, !baseURL.isEmpty else { return }
        guard let snapshot = LocalCacheStore.load(key: cacheKey) else { return }
        isApplyingCache = true
        defer { isApplyingCache = false }
        if !snapshot.assets.isEmpty { hasCompletedInitialLoad = true }
        if assets.isEmpty { assets = snapshot.assets }
        if users.isEmpty { users = snapshot.users }
        if currentUser == nil, let cached = snapshot.currentUser {
            currentUser = snapshot.users.first(where: { $0.id == cached.id }) ?? cached
        }
        if accessories.isEmpty { accessories = snapshot.accessories }
        if licenses.isEmpty { licenses = snapshot.licenses }
        if consumables.isEmpty { consumables = snapshot.consumables }
        if components.isEmpty { components = snapshot.components }
        if locations.isEmpty { locations = snapshot.locations }
        if companies.isEmpty { companies = snapshot.companies }
        if manufacturers.isEmpty { manufacturers = snapshot.manufacturers }
        if suppliers.isEmpty { suppliers = snapshot.suppliers }
        if statusLabels.isEmpty { statusLabels = snapshot.statusLabels }
        if maintenances.isEmpty { maintenances = snapshot.maintenances }
        WidgetSnapshotBuilder.update(from: snapshot, baseURL: baseURL, isConfigured: isConfigured)
    }

    // MARK: - Pagination

    // Server hard-caps responses at MAX_RESULTS (default 500).
    private static let apiPageSize: Int = 500
    // Small gap between page requests; well under the 120 req/min throttle.
    private static let pageDelayNanos: UInt64 = 60_000_000

    private struct PagedRows<T: Decodable>: Decodable {
        let total: Int?
        let rows: [T]?
    }

    /// Fetches all pages from a Snipe-IT list endpoint. Returns nil on error or cancellation.
    private func fetchAllPaginated<T: Decodable>(
        path: String,
        as type: T.Type,
        extraQueryItems: [URLQueryItem] = [],
        reportProgress: Bool = false,
        reportConnectionError: Bool = false,
        isCancelled: @escaping () -> Bool = { false }
    ) async throws -> [T]? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }

        var collected: [T] = []
        var offset = 0
        let limit = Self.apiPageSize
        var serverTotal: Int? = nil

        if reportProgress {
            await MainActor.run { self.loadingProgress = (current: 0, total: -1) }
        }

        defer {
            if reportProgress {
                Task { @MainActor in self.loadingProgress = nil }
            }
        }

        while true {
            if isCancelled() { return nil }

            var components = URLComponents(string: "\(baseURL)\(path)")
            var query: [URLQueryItem] = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            query.append(contentsOf: extraQueryItems)
            components?.queryItems = query

            guard let url = components?.url else { return nil }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await urlSession.data(for: request)
            } catch {
                // Server unreachable / timeout / certificate failure.
                // Keep cached data, surface a notice.
                if reportConnectionError {
                    self.refreshErrorMessage = Self.isTLSCertificateError(error)
                        ? L10n.string("refresh_failed_certificate")
                        : L10n.string("refresh_failed_unreachable")
                    return nil
                }
                throw error
            }

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 {
                    // Throttled: back off and retry the same page.
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    continue
                }
                guard (200...299).contains(http.statusCode) else {
                    #if DEBUG
                    let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<non-UTF8>"
                    print("[SnipeMobile] paginated GET \(path) status=\(http.statusCode) body=\(preview)")
                    #endif
                    if reportConnectionError {
                        self.refreshErrorMessage = http.statusCode == 503
                            ? L10n.string("refresh_failed_maintenance")
                            : L10n.string("refresh_failed_unreachable")
                    }
                    return nil
                }
            }

            let page = try JSONDecoder().decode(PagedRows<T>.self, from: data)
            let rows = page.rows ?? []
            collected.append(contentsOf: rows)

            if let total = page.total { serverTotal = total }

            if reportProgress {
                let progress = (current: collected.count, total: serverTotal ?? -1)
                await MainActor.run { self.loadingProgress = progress }
            }

            if rows.count < limit { break }
            if let total = serverTotal, collected.count >= total { break }
            if rows.isEmpty { break }

            offset += limit
            try? await Task.sleep(nanoseconds: Self.pageDelayNanos)
        }

        return collected
    }

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // TLS/SSL cert failure (not just unreachable).
    static func isTLSCertificateError(_ error: Error) -> Bool {
        let codes: Set<URLError.Code> = [
            .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired
        ]
        if let urlError = error as? URLError, codes.contains(urlError.code) {
            return true
        }
        // NSError fallback.
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let certCodes: Set<Int> = [
                NSURLErrorSecureConnectionFailed,
                NSURLErrorServerCertificateHasBadDate,
                NSURLErrorServerCertificateUntrusted,
                NSURLErrorServerCertificateHasUnknownRoot,
                NSURLErrorServerCertificateNotYetValid,
                NSURLErrorClientCertificateRejected,
                NSURLErrorClientCertificateRequired
            ]
            return certCodes.contains(nsError.code)
        }
        return false
    }

    private var fetchCurrentUserTask: Task<Void, Never>? = nil

    init() {
        self.isConfigured = UserDefaults.standard.bool(forKey: "isConfigured")
        loadCachedDataIfAvailable()
        if isConfigured, !baseURL.isEmpty {
            Task { await self.fetchCurrentUser() }
        }
        NotificationCenter.default.addObserver(forName: .cloudSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let newValue = UserDefaults.standard.bool(forKey: "isConfigured")
                if self.isConfigured != newValue {
                    self.isConfigured = newValue
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .appDataDidWipe, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cacheSaveTask?.cancel()
                LocalCacheStore.clearAll()
                self.hasCompletedInitialLoad = false
                self.isConfigured = false
                self.assets = []
                self.users = []
                self.currentUser = nil
                self.accessories = []
                self.licenses = []
                self.consumables = []
                self.components = []
                self.locations = []
                self.companies = []
                self.manufacturers = []
                self.suppliers = []
                self.statusLabels = []
                self.maintenances = []
                self.maintenanceTypes = []
                self.maintenanceTypesMode = .unknown
                WidgetSnapshotBuilder.clear()
            }
        }
    }

    func saveConfiguration(baseURL: String, apiToken: String) {
        let normalizedBaseURL = normalizeBaseURL(baseURL)
        let isDifferentServer = normalizedBaseURL != self.baseURL
        if isDifferentServer {
            cacheSaveTask?.cancel()
            LocalCacheStore.clearAll()
            currentUser = nil
            assetTagSettings = nil
            maintenanceTypes = []
            maintenanceTypesMode = .unknown
        }
        UserDefaults.standard.set(normalizedBaseURL, forKey: "baseURL")
        KeychainSecretStore.set(apiToken, for: .apiToken)
        UserDefaults.standard.removeObject(forKey: "apiToken")
        self.isConfigured = true
        CloudSettingsStore.shared.writeAPIConfiguration(baseURL: normalizedBaseURL, apiToken: apiToken, isConfigured: true)

        Task {
            await fetchPrimaryThenBackground()
        }
    }

    private func normalizeBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    // Reused so overlapping callers (e.g. two onAppear triggers) await the same
    // sync instead of starting a second one that cancels the first mid-flight.
    private var primaryFetchTask: Task<Void, Never>? = nil

    func fetchPrimaryThenBackground() async {
        if let existing = primaryFetchTask {
            await existing.value
            return
        }

        let task = Task { await self.performPrimaryThenBackground() }
        primaryFetchTask = task
        await task.value
        primaryFetchTask = nil
    }

    private func performPrimaryThenBackground() async {
        isLoading = true
        errorMessage = nil
        refreshErrorMessage = nil

        await fetchCurrentUser()
        await fetchAssets()
        await fetchUsers()
        reconcileCurrentUserWithUsersList()
        await fetchAccessories()
        await fetchLicenses()
        await fetchConsumables()
        await fetchComponents()
        await fetchLocations()
        _ = await fetchAllMaintenances()

        isLoading = false
        hasCompletedInitialLoad = true

        Task(priority: .background) {
            await self.fetchCompanies()
            await self.fetchStatusLabels()
            await self.fetchAssetTagSettings()
        }
    }

    // MARK: - Immediate cache refresh after check-in/out

    /// Full list sync in the background — does not block the UI.
    func syncAllInBackground() {
        Task { await fetchPrimaryThenBackground() }
    }

    /// Updates the shared widget snapshot from the API.
    func syncWidgetDataFromServer() async {
        guard isConfigured, !baseURL.isEmpty else { return }
        cacheSaveTask?.cancel()
        await fetchAssets()
        await fetchAccessories()
        await fetchConsumables()
        await fetchComponents()
        _ = await fetchAllMaintenances()
        await persistCacheNow()
    }

    func applyUpdatedAsset(_ asset: Asset) {
        if let idx = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[idx] = asset
        } else {
            assets.insert(asset, at: 0)
        }
    }

    func applyUpdatedAccessory(_ accessory: Accessory) {
        if let idx = accessories.firstIndex(where: { $0.id == accessory.id }) {
            accessories[idx] = accessory
        } else {
            accessories.insert(accessory, at: 0)
        }
    }

    func applyUpdatedComponent(_ component: Component) {
        if let idx = components.firstIndex(where: { $0.id == component.id }) {
            components[idx] = component
        } else {
            components.insert(component, at: 0)
        }
    }

    func applyUpdatedConsumable(_ consumable: Consumable) {
        if let idx = consumables.firstIndex(where: { $0.id == consumable.id }) {
            consumables[idx] = consumable
        } else {
            consumables.insert(consumable, at: 0)
        }
    }

    func applyUpdatedLicense(_ license: License) {
        if let idx = licenses.firstIndex(where: { $0.id == license.id }) {
            licenses[idx] = license
        } else {
            licenses.insert(license, at: 0)
        }
    }

    func refreshAssetInCache(assetId: Int, responseJSON: [String: Any]? = nil) async {
        assetsPendingDetailRefresh.insert(assetId)
        if let json = responseJSON {
            mergeAssetFromResponseJSON(json)
        }
        if let details = await fetchHardwareDetails(assetId: assetId) {
            applyUpdatedAsset(details)
        }
    }

    /// Re-apply per-asset detail after bulk `/hardware` list sync overwrote checkout state.
    private func reconcilePendingAssetDetails() async {
        let ids = assetsPendingDetailRefresh
        guard !ids.isEmpty else { return }
        for id in ids {
            if let details = await fetchHardwareDetails(assetId: id) {
                applyUpdatedAsset(details)
            }
        }
        assetsPendingDetailRefresh.subtract(ids)
    }

    /// Deployed status id for checkout when the UI does not expose a status picker.
    private func deployedStatusIdForCheckout() async -> Int? {
        if statusLabels.isEmpty {
            await fetchStatusLabels()
        }
        return statusLabels.first(where: { $0.statusMeta?.lowercased() == "deployed" })?.id
    }

    func refreshAccessoryInCache(accessoryId: Int) async {
        if let details = await fetchAccessoryDetails(accessoryId: accessoryId) {
            applyUpdatedAccessory(details)
        }
    }

    func refreshComponentInCache(componentId: Int) async {
        if let details = await fetchComponentDetails(componentId: componentId) {
            applyUpdatedComponent(details)
        }
    }

    func refreshConsumableInCache(consumableId: Int) async {
        if let details = await fetchConsumableDetails(consumableId: consumableId) {
            applyUpdatedConsumable(details)
        }
    }

    func refreshLicenseInCache(licenseId: Int) async {
        if let details = await fetchLicenseDetails(licenseId: licenseId) {
            applyUpdatedLicense(details)
        }
    }

    func fetchAssets() async {
        refreshErrorMessage = nil
        fetchAssetsGeneration += 1
        let myGen = fetchAssetsGeneration

        fetchAssetsTask = Task {
            guard !baseURL.isEmpty, !apiToken.isEmpty else {
                await MainActor.run { errorMessage = "Configure the API settings first." }
                return
            }

            do {
                let result = try await fetchAllPaginated(
                    path: "/api/v1/hardware",
                    as: Asset.self,
                    reportProgress: true,
                    reportConnectionError: true,
                    isCancelled: {
                        myGen != self.fetchAssetsGeneration
                    }
                )
                guard let assets = result else { return }
                await MainActor.run {
                    if myGen == self.fetchAssetsGeneration {
                        // Keep fresher per-asset detail while background list sync can lag.
                        var merged = assets
                        for id in self.assetsPendingDetailRefresh {
                            if let existing = self.assets.first(where: { $0.id == id }),
                               let idx = merged.firstIndex(where: { $0.id == id }) {
                                merged[idx] = existing
                            }
                        }
                        self.assets = merged
                    }
                }
                if myGen == fetchAssetsGeneration {
                    await reconcilePendingAssetDetails()
                }
            } catch {
                await MainActor.run {
                    if myGen == self.fetchAssetsGeneration {
                        self.errorMessage = "Error fetching assets: \(error.localizedDescription)"
                    }
                }
            }
        }
        await fetchAssetsTask?.value
    }

    func fetchHardwareByTag(assetTag: String) async -> Asset? {
        let trimmed = assetTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !apiToken.isEmpty, !trimmed.isEmpty else { return nil }

        let pathEscaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let queryEscaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let candidates: [URL] = [
            URL(string: "\(baseURL)/api/v1/hardware/bytag/\(pathEscaped)") ,
            URL(string: "\(baseURL)/api/v1/hardware/bytag?asset_tag=\(queryEscaped)"),
            URL(string: "\(baseURL)/api/v1/hardware/bytag?assetTag=\(queryEscaped)")
        ]
            .compactMap { $0 }

        for url in candidates {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else { continue }

                // Most common cases:
                // - response is an Asset-like object
                // - response is wrapped with { payload: {...} }
                // - response is wrapped with { rows: [ {...} ] }
                if let asset = try? JSONDecoder().decode(Asset.self, from: data) {
                    return asset
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                if let payload = json["payload"] as? [String: Any] {
                    let payloadData = try? JSONSerialization.data(withJSONObject: payload)
                    if let payloadData,
                       let asset = try? JSONDecoder().decode(Asset.self, from: payloadData) {
                        return asset
                    }
                }

                if let rows = json["rows"] as? [[String: Any]],
                   let first = rows.first {
                    let rowData = try? JSONSerialization.data(withJSONObject: first)
                    if let rowData,
                       let asset = try? JSONDecoder().decode(Asset.self, from: rowData) {
                        return asset
                    }
                }
            } catch {
                // Try next candidate URL.
                continue
            }
        }

        return nil
    }

    func fetchHardwareDetails(assetId: Int) async -> Asset? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            if let asset = try? JSONDecoder().decode(Asset.self, from: data) {
                return asset
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let payload = json["payload"] as? [String: Any],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let asset = try? JSONDecoder().decode(Asset.self, from: payloadData) {
                return asset
            }

            return nil
        } catch {
            return nil
        }
    }

    func fetchUsers() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            await MainActor.run { errorMessage = "Configure the API settings first." }
            return
        }

        refreshErrorMessage = nil
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/users",
                as: User.self,
                reportConnectionError: true
            ) else { return }
            await MainActor.run {
                self.users = rows.sorted { $0.name < $1.name }
                self.reconcileCurrentUserWithUsersList()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching users: \(error.localizedDescription)"
                #if DEBUG
                print("Error details: \(error)")
                #endif
            }
        }
    }

    func ensureCheckoutUserReady() async {
        await fetchCurrentUser()
        reconcileCurrentUserWithUsersList()
    }

    func fetchCurrentUser() async {
        if let existing = fetchCurrentUserTask {
            await existing.value
            return
        }

        let task = Task { await self.performFetchCurrentUser() }
        fetchCurrentUserTask = task
        await task.value
        fetchCurrentUserTask = nil
    }

    private func performFetchCurrentUser() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/users/me") else { return }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return }

            guard let user = Self.decodeUser(from: data) else { return }
            currentUser = user
            reconcileCurrentUserWithUsersList()
        } catch {
            #if DEBUG
            print("Error fetching current user: \(error)")
            #endif
        }
    }

    private func reconcileCurrentUserWithUsersList() {
        guard let id = currentUser?.id,
              let match = users.first(where: { $0.id == id }) else { return }
        currentUser = match
    }

    var defaultCheckoutUser: User? {
        guard let currentUser else { return nil }
        return users.first(where: { $0.id == currentUser.id }) ?? currentUser
    }

    func filteredCheckoutUsers(searchText: String) -> [User] {
        let pinnedId = defaultCheckoutUser?.id
        var filtered = users.filter {
            searchText.isEmpty ||
            $0.decodedName.localizedCaseInsensitiveContains(searchText) ||
            $0.decodedEmail.localizedCaseInsensitiveContains(searchText)
        }

        if let pinned = defaultCheckoutUser {
            let matchesSearch = searchText.isEmpty ||
                pinned.decodedName.localizedCaseInsensitiveContains(searchText) ||
                pinned.decodedEmail.localizedCaseInsensitiveContains(searchText)
            if matchesSearch, !filtered.contains(where: { $0.id == pinned.id }) {
                filtered.insert(pinned, at: 0)
            }
        }

        return filtered.sorted { lhs, rhs in
            if let pinnedId {
                if lhs.id == pinnedId { return true }
                if rhs.id == pinnedId { return false }
            }
            return lhs.decodedName.localizedCaseInsensitiveCompare(rhs.decodedName) == .orderedAscending
        }
    }

    func fetchUserDetails(userId: Int) async -> User? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/users/\(userId)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }
            return Self.decodeUser(from: data)
        } catch {
            return nil
        }
    }

    private static func decodeUser(from data: Data) -> User? {
        if let user = try? JSONDecoder().decode(User.self, from: data) {
            return user
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let payload = json["payload"] as? [String: Any],
           let payloadData = try? JSONSerialization.data(withJSONObject: payload),
           let user = try? JSONDecoder().decode(User.self, from: payloadData) {
            return user
        }

        return nil
    }

    func fetchAccessories() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            await MainActor.run { errorMessage = "Configure the API settings first." }
            return
        }

        refreshErrorMessage = nil
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/accessories",
                as: Accessory.self,
                reportConnectionError: true
            ) else { return }
            await MainActor.run {
                self.accessories = rows
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching accessories: \(error.localizedDescription)"
                #if DEBUG
                print("Error details: \(error)")
                #endif
            }
        }
    }

    func fetchLicenses() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            await MainActor.run { errorMessage = "Configure the API settings first." }
            return
        }

        refreshErrorMessage = nil
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/licenses",
                as: License.self,
                reportConnectionError: true
            ) else { return }
            await MainActor.run {
                self.licenses = rows
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching licenses: \(error.localizedDescription)"
                #if DEBUG
                print("Error details: \(error)")
                #endif
            }
        }
    }

    func fetchConsumables() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            await MainActor.run { errorMessage = "Configure the API settings first." }
            return
        }

        refreshErrorMessage = nil
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/consumables",
                as: Consumable.self,
                reportConnectionError: true
            ) else { return }
            await MainActor.run {
                self.consumables = rows
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching consumables: \(error.localizedDescription)"
                #if DEBUG
                print("Error details: \(error)")
                #endif
            }
        }
    }

    func fetchConsumableDetails(consumableId: Int) async -> Consumable? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/consumables/\(consumableId)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            if let consumable = try? JSONDecoder().decode(Consumable.self, from: data) {
                return consumable
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if let payload = json["payload"] as? [String: Any],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let consumable = try? JSONDecoder().decode(Consumable.self, from: payloadData) {
                return consumable
            }
            return nil
        } catch {
            return nil
        }
    }

    struct ConsumableUserRow: Decodable, Identifiable, Hashable {
        let id = UUID()
        let userId: Int?
        let name: String?
        let email: String?
        let note: String?

        private struct NestedUser: Decodable {
            let id: Int?
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case user, note
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let user = try? container.decodeIfPresent(NestedUser.self, forKey: .user)
            self.userId = user?.id
            self.name = user?.name
            self.email = nil
            self.note = try? container.decodeIfPresent(String.self, forKey: .note)
        }
    }

    /// Checked-out users (`GET /api/v1/consumables/{id}/users`).
    func fetchConsumableCheckedOutList(consumableId: Int) async -> [ConsumableUserRow] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            let rows = try await fetchAllPaginated(
                path: "/api/v1/consumables/\(consumableId)/users",
                as: ConsumableUserRow.self
            )
            return rows ?? []
        } catch {
            #if DEBUG
            print("fetchConsumableCheckedOutList error: \(error)")
            #endif
            return []
        }
    }

    func createConsumable(
        name: String,
        categoryId: Int,
        quantity: Int,
        minAmt: Int?,
        itemNo: String?,
        modelNumber: String?,
        orderNumber: String?,
        purchaseCost: String?,
        purchaseDate: String?,
        companyId: Int?,
        locationId: Int?,
        manufacturerId: Int?,
        supplierId: Int?,
        notes: String?
    ) async -> (success: Bool, id: Int?) {
        guard let url = URL(string: "\(baseURL)/api/v1/consumables") else { return (false, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "name": name,
            "category_id": categoryId,
            "qty": quantity
        ]
        if let minAmt, minAmt > 0 { body["min_amt"] = minAmt }
        if let v = itemNo, !v.isEmpty { body["item_no"] = v }
        if let v = modelNumber, !v.isEmpty { body["model_number"] = v }
        if let v = orderNumber, !v.isEmpty { body["order_number"] = v }
        if let v = purchaseCost, !v.isEmpty, let normalized = NumberFormatHelpers.normalizeDecimalForAPI(v) {
            body["purchase_cost"] = normalized
        }
        if let v = purchaseDate, !v.isEmpty { body["purchase_date"] = v }
        if let v = companyId, v > 0 { body["company_id"] = v }
        if let v = locationId, v > 0 { body["location_id"] = v }
        if let v = manufacturerId, v > 0 { body["manufacturer_id"] = v }
        if let v = supplierId, v > 0 { body["supplier_id"] = v }
        if let v = notes, !v.isEmpty { body["notes"] = v }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return (false, nil) }
            if Self.isHTMLResponse(data) {
                await MainActor.run { self.lastApiMessage = L10n.string("api_invalid_response") }
                return (false, nil)
            }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            #if DEBUG
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<non-UTF8>"
            print("[SnipeMobile] POST /consumables status=\(httpResponse.statusCode) body=\(preview)")
            #endif
            let isError = Self.isSnipeApiErrorResponse(json)
            let newId = Self.idFromApiPayload(json?["payload"])
            let httpOK = Self.isSnipeApiHttpSuccess(httpResponse.statusCode)
            let success = httpOK && !isError && newId != nil
            let msg = Self.extractApiErrorMessage(from: json ?? [:])
                ?? (success ? L10n.string("consumable_created") : L10n.string("create_failed"))
            await MainActor.run { self.lastApiMessage = msg }
            if success, let newId {
                Task { await self.fetchConsumables() }
                return (true, newId)
            }
            return (false, nil)
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return (false, nil)
        }
    }

    func updateConsumable(
        consumableId: Int,
        name: String,
        categoryId: Int,
        quantity: Int,
        minAmt: Int?,
        itemNo: String?,
        modelNumber: String?,
        orderNumber: String?,
        purchaseCost: String?,
        purchaseDate: String?,
        companyId: Int?,
        locationId: Int?,
        manufacturerId: Int?,
        supplierId: Int?,
        notes: String?
    ) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/consumables/\(consumableId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "name": name,
            "category_id": categoryId,
            "qty": quantity
        ]
        if let minAmt, minAmt > 0 { body["min_amt"] = minAmt }
        if let v = itemNo, !v.isEmpty { body["item_no"] = v }
        if let v = modelNumber, !v.isEmpty { body["model_number"] = v }
        if let v = orderNumber, !v.isEmpty { body["order_number"] = v }
        if let v = purchaseCost, !v.isEmpty, let normalized = NumberFormatHelpers.normalizeDecimalForAPI(v) {
            body["purchase_cost"] = normalized
        } else {
            body["purchase_cost"] = NSNull()
        }
        if let v = purchaseDate, !v.isEmpty {
            body["purchase_date"] = v
        } else {
            body["purchase_date"] = NSNull()
        }
        if let v = companyId, v > 0 { body["company_id"] = v }
        if let v = locationId, v > 0 { body["location_id"] = v }
        if let v = manufacturerId, v > 0 { body["manufacturer_id"] = v }
        if let v = supplierId, v > 0 { body["supplier_id"] = v }
        if let v = notes { body["notes"] = v }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if Self.isHTMLResponse(data) {
                    await MainActor.run { self.lastApiMessage = L10n.string("api_invalid_response") }
                    return false
                }
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let isError = Self.isSnipeApiErrorResponse(json)
                let msg = Self.extractApiErrorMessage(from: json ?? [:])
                    ?? (httpResponse.statusCode == 200 && !isError ? L10n.string("saved") : L10n.string("create_failed"))
                await MainActor.run { self.lastApiMessage = msg }
                if Self.isSnipeApiHttpSuccess(httpResponse.statusCode), !isError {
                    if let updated: Consumable = decodedPatchPayload(from: data) {
                        await MainActor.run { replaceCachedItem(updated, in: &self.consumables, id: \.id) }
                    }
                    Task { await self.fetchConsumables() }
                    return true
                }
                return false
            }
            return false
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    func checkoutConsumable(consumableId: Int, userId: Int, note: String?) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/consumables/\(consumableId)/checkout") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["assigned_to": userId]
        if let note, !note.isEmpty { body["note"] = note }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Check-out successful.",
                defaultFailureMessage: "Check-out failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshConsumableInCache(consumableId: consumableId)
            syncAllInBackground()
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error checking out consumable: \(error.localizedDescription)" }
            return false
        }
    }

    // MARK: - Components

    func fetchComponents() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        refreshErrorMessage = nil
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/components",
                as: Component.self,
                reportConnectionError: true
            ) else { return }
            await MainActor.run {
                self.components = rows
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching components: \(error.localizedDescription)"
                #if DEBUG
                print("Error details: \(error)")
                #endif
            }
        }
    }

    func fetchComponentDetails(componentId: Int) async -> Component? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/components/\(componentId)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            if let component = try? JSONDecoder().decode(Component.self, from: data) {
                return component
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if let payload = json["payload"] as? [String: Any],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let component = try? JSONDecoder().decode(Component.self, from: payloadData) {
                return component
            }
            return nil
        } catch {
            return nil
        }
    }

    struct ComponentAssetRow: Decodable, Identifiable, Hashable {
        let id = UUID()
        let assignedPivotId: Int?
        let assetId: Int?
        let assetName: String?
        let assetTag: String?
        let assignedQty: Int?
        let note: String?

        private struct NestedAsset: Decodable {
            let id: Int?
            let name: String?
            let assetTag: String?
            enum CodingKeys: String, CodingKey {
                case id, name
                case assetTag = "asset_tag"
            }
        }

        enum CodingKeys: String, CodingKey {
            case assignedPivotId = "assigned_pivot_id"
            case name, note
            case assignedQty = "assigned_qty"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.assignedPivotId = try? container.decodeIfPresent(Int.self, forKey: .assignedPivotId)
            self.assignedQty = try? container.decodeIfPresent(Int.self, forKey: .assignedQty)
            self.note = try? container.decodeIfPresent(String.self, forKey: .note)
            let asset = try? container.decodeIfPresent(NestedAsset.self, forKey: .name)
            self.assetId = asset?.id
            self.assetName = asset?.name
            self.assetTag = asset?.assetTag
        }
    }

    /// Assets a component has been checked out to (`GET /api/v1/components/{id}/assets`).
    func fetchComponentAssetsList(componentId: Int) async -> [ComponentAssetRow] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            let rows = try await fetchAllPaginated(
                path: "/api/v1/components/\(componentId)/assets",
                as: ComponentAssetRow.self
            )
            return rows ?? []
        } catch {
            #if DEBUG
            print("fetchComponentAssetsList error: \(error)")
            #endif
            return []
        }
    }

    func createComponent(
        name: String,
        categoryId: Int,
        quantity: Int,
        minAmt: Int?,
        serial: String?,
        modelNumber: String?,
        orderNumber: String?,
        purchaseCost: String?,
        purchaseDate: String?,
        companyId: Int?,
        locationId: Int?,
        manufacturerId: Int?,
        supplierId: Int?,
        notes: String?
    ) async -> (success: Bool, id: Int?) {
        guard let url = URL(string: "\(baseURL)/api/v1/components") else { return (false, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "name": name,
            "category_id": categoryId,
            "qty": quantity
        ]
        if let minAmt, minAmt > 0 { body["min_amt"] = minAmt }
        if let v = serial, !v.isEmpty { body["serial"] = v }
        if let v = modelNumber, !v.isEmpty { body["model_number"] = v }
        if let v = orderNumber, !v.isEmpty { body["order_number"] = v }
        if let v = purchaseCost, !v.isEmpty, let normalized = NumberFormatHelpers.normalizeDecimalForAPI(v) {
            body["purchase_cost"] = normalized
        }
        if let v = purchaseDate, !v.isEmpty { body["purchase_date"] = v }
        if let v = companyId, v > 0 { body["company_id"] = v }
        if let v = locationId, v > 0 { body["location_id"] = v }
        if let v = manufacturerId, v > 0 { body["manufacturer_id"] = v }
        if let v = supplierId, v > 0 { body["supplier_id"] = v }
        if let v = notes, !v.isEmpty { body["notes"] = v }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return (false, nil) }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let hasNewId = (json?["payload"] as? [String: Any])?["id"] as? Int != nil
            let base = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Component created!",
                defaultFailureMessage: "Create failed."
            )
            let success = base.success && hasNewId
            let msg = success ? base.message : (Self.extractApiErrorMessage(from: json ?? [:]) ?? base.message)
            await MainActor.run { self.lastApiMessage = msg }
            if success, let newId = (json?["payload"] as? [String: Any])?["id"] as? Int {
                Task { await self.fetchComponents() }
                return (true, newId)
            }
            return (false, nil)
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return (false, nil)
        }
    }

    func updateComponent(
        componentId: Int,
        name: String,
        categoryId: Int,
        quantity: Int,
        minAmt: Int?,
        serial: String?,
        modelNumber: String?,
        orderNumber: String?,
        purchaseCost: String?,
        purchaseDate: String?,
        companyId: Int?,
        locationId: Int?,
        manufacturerId: Int?,
        supplierId: Int?,
        notes: String?
    ) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/components/\(componentId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "name": name,
            "category_id": categoryId,
            "qty": quantity
        ]
        if let minAmt, minAmt > 0 { body["min_amt"] = minAmt }
        if let v = serial, !v.isEmpty { body["serial"] = v }
        if let v = modelNumber, !v.isEmpty { body["model_number"] = v }
        if let v = orderNumber, !v.isEmpty { body["order_number"] = v }
        if let v = purchaseCost, !v.isEmpty, let normalized = NumberFormatHelpers.normalizeDecimalForAPI(v) {
            body["purchase_cost"] = normalized
        } else {
            body["purchase_cost"] = NSNull()
        }
        if let v = purchaseDate, !v.isEmpty {
            body["purchase_date"] = v
        } else {
            body["purchase_date"] = NSNull()
        }
        if let v = companyId, v > 0 { body["company_id"] = v }
        if let v = locationId, v > 0 { body["location_id"] = v }
        if let v = manufacturerId, v > 0 { body["manufacturer_id"] = v }
        if let v = supplierId, v > 0 { body["supplier_id"] = v }
        if let v = notes { body["notes"] = v }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Saved.",
                defaultFailureMessage: "Save failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshComponentInCache(componentId: componentId)
            Task { await self.fetchComponents() }
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    func checkoutComponent(componentId: Int, assetId: Int, quantity: Int, note: String?) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/components/\(componentId)/checkout") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "assigned_to": assetId,
            "assigned_qty": max(1, quantity)
        ]
        if let note, !note.isEmpty { body["note"] = note }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Check-out successful.",
                defaultFailureMessage: "Check-out failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshComponentInCache(componentId: componentId)
            syncAllInBackground()
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error checking out component: \(error.localizedDescription)" }
            return false
        }
    }

    /// Checks a component back in from an asset. `componentAssetId` is the pivot id
    /// (`assigned_pivot_id`) from `GET /components/{id}/assets`, not the component id.
    /// Returns nil on success, otherwise an error message.
    func checkinComponent(componentId: Int, componentAssetId: Int, quantity: Int) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "API not configured." }
        guard let url = URL(string: "\(baseURL)/api/v1/components/\(componentAssetId)/checkin") else {
            return "Invalid URL."
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["checkin_qty": max(1, quantity)]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response." }
            guard Self.isSnipeApiHttpSuccess(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode): \(preview)"
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               Self.isSnipeApiErrorResponse(json) {
                return Self.extractApiErrorMessage(from: json) ?? "Check-in failed."
            }
            await refreshComponentInCache(componentId: componentId)
            syncAllInBackground()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Licenses assigned to a user. Returns full License objects (same shape as /api/v1/licenses rows).
    func fetchUserLicenses(userId: Int) async -> [License] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            return try await fetchAllPaginated(
                path: "/api/v1/users/\(userId)/licenses",
                as: License.self
            ) ?? []
        } catch {
            return []
        }
    }

    /// Assets assigned to a user (`GET /api/v1/users/{id}/assets`).
    func fetchUserAssets(userId: Int) async -> [Asset] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            return try await fetchAllPaginated(
                path: "/api/v1/users/\(userId)/assets",
                as: Asset.self
            ) ?? []
        } catch {
            return []
        }
    }

    /// Accessories checked out to a user (`GET /api/v1/users/{id}/accessories`).
    func fetchUserAccessories(userId: Int) async -> [Accessory] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            return try await fetchAllPaginated(
                path: "/api/v1/users/\(userId)/accessories",
                as: Accessory.self
            ) ?? []
        } catch {
            return []
        }
    }


    func fetchUserConsumables(userId: Int) async -> [Consumable] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        if consumables.isEmpty {
            await fetchConsumables()
        }

        let candidates = consumables.filter { consumable in
            guard let qty = consumable.qty, let remaining = consumable.remaining else { return false }
            return remaining < qty
        }

        var results: [Consumable] = []
        for consumable in candidates {
            let rows = await fetchConsumableCheckedOutList(consumableId: consumable.id)
            if rows.contains(where: { $0.userId == userId }) {
                results.append(consumable)
            }
        }

        return results.sorted {
            $0.decodedName.localizedCaseInsensitiveCompare($1.decodedName) == .orderedAscending
        }
    }

    /// Accessories checked out to a hardware asset (`GET /hardware/{id}/assigned/accessories`).
    func fetchAssetAccessories(assetId: Int) async -> [Accessory] {
        await fetchAssignedAccessories(path: "/api/v1/hardware/\(assetId)/assigned/accessories")
    }

    /// Accessories checked out to a location (`GET /locations/{id}/assigned/accessories`).
    func fetchLocationAccessories(locationId: Int) async -> [Accessory] {
        await fetchAssignedAccessories(path: "/api/v1/locations/\(locationId)/assigned/accessories")
    }

    /// Assets checked out to a location (`GET /api/v1/locations/{id}/assets`).
    func fetchLocationAssets(locationId: Int) async -> [Asset] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            return try await fetchAllPaginated(
                path: "/api/v1/locations/\(locationId)/assets",
                as: Asset.self
            ) ?? []
        } catch {
            return []
        }
    }

    private func fetchAssignedAccessories(path: String) async -> [Accessory] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)\(path)") else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["rows"] as? [[String: Any]] else { return [] }

            var ids: [Int] = []
            var seen = Set<Int>()
            for row in rows {
                guard let accessoryDict = row["accessory"] as? [String: Any],
                      let id = accessoryDict["id"] as? Int else { continue }
                if seen.insert(id).inserted { ids.append(id) }
            }

            var results: [Accessory] = []
            for id in ids {
                if let cached = self.accessories.first(where: { $0.id == id }) {
                    results.append(cached)
                } else if let fetched = await self.fetchAccessoryDetails(accessoryId: id) {
                    results.append(fetched)
                }
            }
            return results
        } catch {
            return []
        }
    }

    /// Licenses on a hardware asset. Seat rows reference the parent license id;
    /// we resolve against the cached list (fetch by id as fallback).
    func fetchAssetLicenses(assetId: Int) async -> [License] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/licenses") else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["rows"] as? [[String: Any]] else { return [] }

            var ids: [Int] = []
            var seen = Set<Int>()
            for row in rows {
                guard let licenseDict = row["license"] as? [String: Any],
                      let id = licenseDict["id"] as? Int else { continue }
                if seen.insert(id).inserted { ids.append(id) }
            }

            var results: [License] = []
            for id in ids {
                if let cached = self.licenses.first(where: { $0.id == id }) {
                    results.append(cached)
                } else if let fetched = await self.fetchLicenseDetails(licenseId: id) {
                    results.append(fetched)
                }
            }
            return results
        } catch {
            return []
        }
    }

    /// Hardware assets checked out to this asset (`GET /hardware/{id}/assigned/assets`).
    func fetchAssetAssignedAssets(assetId: Int) async -> [Asset] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }

        var results: [Asset] = []
        var seen = Set<Int>()

        func appendUnique(_ assets: [Asset]) {
            for asset in assets where seen.insert(asset.id).inserted {
                results.append(asset)
            }
        }

        do {
            if let fromEndpoint = try await fetchAllPaginated(
                path: "/api/v1/hardware/\(assetId)/assigned/assets",
                as: Asset.self
            ) {
                appendUnique(fromEndpoint)
            }
        } catch {
            #if DEBUG
            print("fetchAssetAssignedAssets endpoint error: \(error)")
            #endif
        }
        if let fromQuery = await fetchAllAssignedAssets(toAssetId: assetId) {
            appendUnique(fromQuery)
        }

        let cached = assets.filter { $0.assignedTo?.isAsset == true && $0.assignedTo?.id == assetId }
        appendUnique(cached)

        return results.sorted {
            $0.decodedAssetTag.localizedCaseInsensitiveCompare($1.decodedAssetTag) == .orderedAscending
        }
    }

    private func fetchAllAssignedAssets(toAssetId assetId: Int) async -> [Asset]? {
        do {
            return try await fetchAllPaginated(
                path: "/api/v1/hardware",
                as: Asset.self,
                extraQueryItems: [
                    URLQueryItem(name: "assigned_to", value: "\(assetId)"),
                    URLQueryItem(name: "assigned_type", value: "App\\Models\\Asset")
                ]
            )
        } catch {
            return nil
        }
    }

    private func fetchHardwareAssetList(path: String) async -> [Asset]? {
        guard let url = URL(string: "\(baseURL)\(path)") else { return nil }
        return await fetchHardwareAssetList(url: url, treatNotFoundAsMissing: true)
    }

    private func fetchHardwareAssetList(query: [URLQueryItem]) async -> [Asset]? {
        guard var components = URLComponents(string: "\(baseURL)/api/v1/hardware") else { return nil }
        components.queryItems = query
        guard let url = components.url else { return nil }
        return await fetchHardwareAssetList(url: url, treatNotFoundAsMissing: false)
    }

    private func fetchHardwareAssetList(url: URL, treatNotFoundAsMissing: Bool) async -> [Asset]? {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if treatNotFoundAsMissing, http.statusCode == 404 { return nil }
            guard (200...299).contains(http.statusCode) else { return [] }
            if let decoded = try? JSONDecoder().decode(AssetResponse.self, from: data) {
                return decoded.rows
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["rows"] as? [[String: Any]] else { return [] }
            return rows.compactMap { row in
                guard let rowData = try? JSONSerialization.data(withJSONObject: row) else { return nil }
                return try? JSONDecoder().decode(Asset.self, from: rowData)
            }
        } catch {
            #if DEBUG
            print("fetchHardwareAssetList error: \(error)")
            #endif
            return treatNotFoundAsMissing ? nil : []
        }
    }

    struct AssetAssignedComponent: Identifiable, Hashable {
        let component: Component
        let assignedQty: Int

        var id: Int { component.id }
    }

    /// Components checked out to a hardware asset (`GET /hardware/{id}/assigned/components`).
    func fetchAssetComponents(assetId: Int) async -> [AssetAssignedComponent] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/assigned/components") else { return [] }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json["rows"] as? [[String: Any]] else { return [] }

            // Same component can appear on multiple pivot rows; sum assigned_qty per component.
            var aggregated: [Int: (component: Component, assignedQty: Int)] = [:]
            for row in rows {
                let qty = row["assigned_qty"] as? Int ?? 1
                let component: Component?
                if let componentDict = row["component"] as? [String: Any],
                   let componentData = try? JSONSerialization.data(withJSONObject: componentDict) {
                    component = try? JSONDecoder().decode(Component.self, from: componentData)
                } else if let componentDict = row["name"] as? [String: Any],
                          let componentData = try? JSONSerialization.data(withJSONObject: componentDict) {
                    component = try? JSONDecoder().decode(Component.self, from: componentData)
                } else if let componentId = row["id"] as? Int {
                    component = components.first(where: { $0.id == componentId })
                } else {
                    component = nil
                }
                guard let component else { continue }
                if var existing = aggregated[component.id] {
                    existing.assignedQty += qty
                    aggregated[component.id] = existing
                } else {
                    aggregated[component.id] = (component, qty)
                }
            }
            return aggregated.values.map { AssetAssignedComponent(component: $0.component, assignedQty: $0.assignedQty) }
        } catch {
            #if DEBUG
            print("fetchAssetComponents error: \(error)")
            #endif
            return []
        }
    }

    func fetchLicenseDetails(licenseId: Int) async -> License? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/licenses/\(licenseId)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            if let license = try? JSONDecoder().decode(License.self, from: data) {
                return license
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let payload = json["payload"] as? [String: Any],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let license = try? JSONDecoder().decode(License.self, from: payloadData) {
                return license
            }

            return nil
        } catch {
            return nil
        }
    }

    struct LicenseSeatAsset: Codable, Hashable {
        let id: Int
        let name: String?
    }

    struct LicenseSeatAssignee {
        let user: User?
        let name: String
        let email: String
        let company: String
    }

    struct LicenseSeatRow: Codable, Identifiable {
        let id: Int
        let licenseId: Int?
        let assignedUser: AssignedTo?
        let assignedAsset: LicenseSeatAsset?
        let location: Location?
        let userCanCheckin: Bool?
        let userCanCheckout: Bool?
        let reassignable: Bool?
        /// True when the seat is permanently used (unreassignable_seat) or the license is inactive.
        let disabled: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case licenseId = "license_id"
            case assignedUser = "assigned_user"
            case assignedAsset = "assigned_asset"
            case location
            case userCanCheckin = "user_can_checkin"
            case userCanCheckout = "user_can_checkout"
            case reassignable
            case disabled
        }

        // Fall back to the asset's checkout user when assigned_user is missing.
        func resolvedAssignee(assets: [Asset], users: [User]) -> LicenseSeatAssignee? {
            guard assignedAsset != nil else { return nil }

            if let seatUser = assignedUser {
                let cached = users.first(where: { $0.id == seatUser.id })
                return LicenseSeatAssignee(
                    user: cached,
                    name: cached?.decodedName ?? HTMLDecoder.decode(seatUser.name),
                    email: cached?.decodedEmail ?? HTMLDecoder.decode(seatUser.email ?? ""),
                    company: cached?.decodedCompanyName ?? ""
                )
            }

            guard let assetId = assignedAsset?.id,
                  let asset = assets.first(where: { $0.id == assetId }),
                  asset.assignedTo?.isUser == true else {
                return nil
            }

            if let userId = asset.assignedTo?.id,
               let user = users.first(where: { $0.id == userId }) {
                return LicenseSeatAssignee(
                    user: user,
                    name: user.decodedName,
                    email: user.decodedEmail,
                    company: user.decodedCompanyName
                )
            }

            let name = asset.decodedAssignedToName
            guard !name.isEmpty else { return nil }
            return LicenseSeatAssignee(user: nil, name: name, email: "", company: "")
        }
    }

    func fetchLicenseSeats(licenseId: Int) async -> [LicenseSeatRow] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            let rows = try await fetchAllPaginated(
                path: "/api/v1/licenses/\(licenseId)/seats",
                as: LicenseSeatRow.self
            )
            return rows ?? []
        } catch {
            #if DEBUG
            // Silently ignore cancellations (happen when navigating away).
            let nsError = error as NSError
            let isCancelled = nsError.code == NSURLErrorCancelled || error is CancellationError
            if !isCancelled {
                print("fetchLicenseSeats error: \(error)")
            }
            #endif
            return []
        }
    }

    /// Assigns a license seat to a user (`assigned_to`) or asset (`asset_id`).
    /// Returns nil on success, otherwise a user-facing error message.
    func checkoutLicenseSeat(licenseId: Int, seatId: Int, userId: Int?, assetId: Int?, note: String?) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "API not configured." }

        if let userId {
            var body: [String: Any] = ["assigned_to": userId]
            if let note, !note.isEmpty { body["note"] = note }
            if let error = await putLicenseSeatUpdate(licenseId: licenseId, seatId: seatId, body: body, label: "checkout-user") {
                return error
            }
        } else if let assetId {
            // The API `prohibits` rule allows only one of assigned_to / asset_id per request.
            var assetBody: [String: Any] = ["asset_id": assetId]
            if let note, !note.isEmpty { assetBody["note"] = note }
            if let error = await putLicenseSeatUpdate(licenseId: licenseId, seatId: seatId, body: assetBody, label: "checkout-asset") {
                return error
            }

            // Mirror Snipe-IT web checkout: copy the asset's assigned user onto the seat.
            var asset = assets.first(where: { $0.id == assetId })
            if asset == nil {
                asset = await fetchHardwareDetails(assetId: assetId)
            }
            if let asset,
               asset.assignedTo?.isUser == true,
               let checkoutUserId = asset.assignedTo?.id {
                let userBody: [String: Any] = ["assigned_to": checkoutUserId]
                if let error = await putLicenseSeatUpdate(licenseId: licenseId, seatId: seatId, body: userBody, label: "checkout-asset-user") {
                    return error
                }
            }
        } else {
            return "No assignee selected."
        }

        await refreshLicenseInCache(licenseId: licenseId)
        if let assetId {
            await refreshAssetInCache(assetId: assetId)
        }
        syncAllInBackground()
        return nil
    }

    private func putLicenseSeatUpdate(
        licenseId: Int,
        seatId: Int,
        body: [String: Any],
        label: String
    ) async -> String? {
        guard let url = URL(string: "\(baseURL)/api/v1/licenses/\(licenseId)/seats/\(seatId)") else {
            return "Invalid URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response." }

            #if DEBUG
            let bodyPreview = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let resPreview = String(data: data.prefix(600), encoding: .utf8) ?? ""
            print("[SnipeMobile] PUT /licenses/\(licenseId)/seats/\(seatId) (\(label)) sent=\(bodyPreview) status=\(http.statusCode) body=\(resPreview)")
            #endif

            guard Self.isSnipeApiHttpSuccess(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode): \(preview)"
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               Self.isSnipeApiErrorResponse(json) {
                return Self.extractApiErrorMessage(from: json) ?? "Check-out failed."
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Creates a new license. Returns the new id on success, otherwise an error message via `lastApiMessage`.
    func createLicense(body: [String: Any]) async -> (success: Bool, id: Int?, message: String?) {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return (false, nil, "API not configured.") }
        guard let url = URL(string: "\(baseURL)/api/v1/licenses") else {
            return (false, nil, "Invalid URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, nil, "No response.") }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard Self.isSnipeApiHttpSuccess(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return (false, nil, "HTTP \(http.statusCode): \(preview)")
            }
            if let json, Self.isSnipeApiErrorResponse(json) {
                return (false, nil, Self.extractApiErrorMessage(from: json) ?? "Create failed.")
            }
            let newId = (json?["payload"] as? [String: Any])?["id"] as? Int
            Task { await self.fetchLicenses() }
            return (true, newId, nil)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    /// Updates the editable fields of a license. Returns nil on success, otherwise an error message.
    func updateLicense(licenseId: Int, body: [String: Any]) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "API not configured." }
        guard let url = URL(string: "\(baseURL)/api/v1/licenses/\(licenseId)") else {
            return "Invalid URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response." }
            guard Self.isSnipeApiHttpSuccess(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode): \(preview)"
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               Self.isSnipeApiErrorResponse(json) {
                return Self.extractApiErrorMessage(from: json) ?? "Save failed."
            }
            if let updated: License = decodedPatchPayload(from: data) {
                await MainActor.run { replaceCachedItem(updated, in: &self.licenses, id: \.id) }
            }
            Task { await self.fetchLicenses() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Creates a new user. Returns the new id on success, otherwise an error message.
    func createUser(body: [String: Any]) async -> (success: Bool, id: Int?, message: String?) {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return (false, nil, "API not configured.") }
        guard let url = URL(string: "\(baseURL)/api/v1/users") else {
            return (false, nil, "Invalid URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, nil, "No response.") }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard (200...299).contains(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return (false, nil, "HTTP \(http.statusCode): \(preview)")
            }
            if let json, Self.isSnipeApiErrorResponse(json) {
                return (false, nil, Self.extractApiErrorMessage(from: json) ?? "Create failed.")
            }
            let newId = (json?["payload"] as? [String: Any])?["id"] as? Int
            Task { await self.fetchUsers() }
            return (true, newId, nil)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    /// Updates the editable fields of a user. Returns nil on success, otherwise an error message.
    func updateUser(userId: Int, body: [String: Any]) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "API not configured." }
        guard let url = URL(string: "\(baseURL)/api/v1/users/\(userId)") else {
            return "Invalid URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response." }
            guard (200...299).contains(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode): \(preview)"
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               Self.isSnipeApiErrorResponse(json) {
                return Self.extractApiErrorMessage(from: json) ?? "Save failed."
            }
            if let updated: User = decodedPatchPayload(from: data) {
                await MainActor.run { replaceCachedItem(updated, in: &self.users, id: \.id) }
            }
            Task { await self.fetchUsers() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Creates a new location. Returns the new id on success, otherwise an error message.
    func createLocation(body: [String: Any]) async -> (success: Bool, id: Int?, message: String?) {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return (false, nil, "API not configured.") }
        guard let url = URL(string: "\(baseURL)/api/v1/locations") else {
            return (false, nil, "Invalid URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, nil, "No response.") }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard (200...299).contains(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return (false, nil, "HTTP \(http.statusCode): \(preview)")
            }
            if let json, Self.isSnipeApiErrorResponse(json) {
                return (false, nil, Self.extractApiErrorMessage(from: json) ?? "Create failed.")
            }
            let newId = (json?["payload"] as? [String: Any])?["id"] as? Int
            Task { await self.fetchLocations() }
            return (true, newId, nil)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    /// Updates the editable fields of a location. Returns nil on success, otherwise an error message.
    func updateLocation(locationId: Int, body: [String: Any]) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "API not configured." }
        guard let url = URL(string: "\(baseURL)/api/v1/locations/\(locationId)") else {
            return "Invalid URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response." }
            guard (200...299).contains(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode): \(preview)"
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               Self.isSnipeApiErrorResponse(json) {
                return Self.extractApiErrorMessage(from: json) ?? "Save failed."
            }
            if let updated: Location = decodedPatchPayload(from: data) {
                await MainActor.run { replaceCachedItem(updated, in: &self.locations, id: \.id) }
            }
            Task { await self.fetchLocations() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Frees a license seat. Returns nil on success, otherwise an error message.
    func checkinLicenseSeat(licenseId: Int, seatId: Int) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "API not configured." }
        guard let url = URL(string: "\(baseURL)/api/v1/licenses/\(licenseId)/seats/\(seatId)") else {
            return "Invalid URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = ["assigned_to": NSNull(), "asset_id": NSNull()]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "No response." }

            #if DEBUG
            if !(200...299).contains(http.statusCode) {
                let preview = String(data: data.prefix(600), encoding: .utf8) ?? ""
                print("[SnipeMobile] PUT /licenses/\(licenseId)/seats/\(seatId) status=\(http.statusCode) body=\(preview)")
            }
            #endif

            guard (200...299).contains(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return "HTTP \(http.statusCode): \(preview)"
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               Self.isSnipeApiErrorResponse(json) {
                return Self.extractApiErrorMessage(from: json) ?? "Check-in failed."
            }
            await refreshLicenseInCache(licenseId: licenseId)
            syncAllInBackground()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Decodes the updated record from a Snipe-IT PATCH/PUT response (`payload` or root).
    private func decodedPatchPayload<T: Decodable>(from data: Data) -> T? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return try? JSONDecoder().decode(T.self, from: data)
        }
        if Self.isSnipeApiErrorResponse(json) { return nil }
        guard let payload = json["payload"], !(payload is NSNull),
              let payloadDict = payload as? [String: Any],
              let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict),
              let decoded = try? JSONDecoder().decode(T.self, from: payloadData) else {
            return nil
        }
        return decoded
    }

    private func hardwareFormFields(from bodyObject: [String: Any]) -> [String: String] {
        var fields: [String: String] = [:]
        for (key, value) in bodyObject {
            switch value {
            case is NSNull:
                continue
            case let string as String:
                fields[key] = string
            case let number as Int:
                fields[key] = "\(number)"
            case let number as Double:
                fields[key] = "\(number)"
            case let flag as Bool:
                fields[key] = flag ? "1" : "0"
            default:
                continue
            }
        }
        return fields
    }

    private func buildMultipartBody(
        boundary: String,
        fields: [String: String],
        imageData: Data?,
        fileName: String = "image.jpg"
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) { body.append(data) }
        }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        if let imageData {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileName)\"\r\n")
            append("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }

    private func sendHardwareMultipart(
        url: URL,
        method: String,
        fields: [String: String],
        imageData: Data
    ) async throws -> (Data, HTTPURLResponse) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var fieldsWithMethod = fields
        var httpMethod = method
        if method == "PUT" {
            // Laravel needs POST + _method for multipart file uploads.
            fieldsWithMethod["_method"] = "PUT"
            httpMethod = "POST"
        } else if method == "PATCH" {
            fieldsWithMethod["_method"] = "PATCH"
            httpMethod = "POST"
        }
        let body = buildMultipartBody(boundary: boundary, fields: fieldsWithMethod, imageData: imageData)
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func prepareMaintenanceImagePayload(_ image: UIImage?) -> (jpeg: Data?, imageSource: String?) {
        guard let image else { return (nil, nil) }
        return (image.snipeJPEGUploadData(), image.snipeBase64ImageSource())
    }

    private func makeMaintenanceJSONRequest(url: URL, method: String, bodyData: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData
        return request
    }

    @MainActor
    private func replaceCachedItem<T>(_ item: T, in list: inout [T], id: KeyPath<T, Int>) {
        if let idx = list.firstIndex(where: { $0[keyPath: id] == item[keyPath: id] }) {
            list[idx] = item
        }
    }

    static func extractApiErrorMessage(from json: [String: Any], joinAll: Bool = false) -> String? {
        if let str = json["message"] as? String, !str.isEmpty { return str }
        var messages: [String] = []
        messages.append(contentsOf: stringsFromFieldDictionary(json["messages"]))
        messages.append(contentsOf: stringsFromFieldDictionary(json["errors"]))
        if !messages.isEmpty {
            return joinAll ? messages.joined(separator: "\n") : messages[0]
        }
        if let str = json["error"] as? String, !str.isEmpty { return str }
        return nil
    }

    private static func stringsFromFieldValue(_ value: Any) -> [String] {
        if let str = value as? String, !str.isEmpty { return [str] }
        if let arr = value as? [Any] {
            return arr.compactMap { item in
                guard let s = item as? String, !s.isEmpty else { return nil }
                return s
            }
        }
        return []
    }

    private static func stringsFromFieldDictionary(_ value: Any?) -> [String] {
        if let str = value as? String, !str.isEmpty { return [str] }
        guard let dict = value as? [String: Any] else { return [] }
        return dict.values.flatMap { stringsFromFieldValue($0) }
    }

    private static func isSnipeApiErrorResponse(_ json: [String: Any]?) -> Bool {
        guard let json else { return false }
        if (json["status"] as? String)?.lowercased() == "error" { return true }
        if json["errors"] is [String: Any] {
            let status = (json["status"] as? String)?.lowercased()
            if status == nil || status == "error" { return true }
        }
        return false
    }

    private static func isSnipeApiHttpSuccess(_ statusCode: Int) -> Bool {
        (200...299).contains(statusCode)
    }

    private static func decodeBase64Pdf(_ base64: String) -> Data? {
        var cleaned = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("data:"), let comma = cleaned.firstIndex(of: ",") {
            cleaned = String(cleaned[cleaned.index(after: comma)...])
        }
        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters), !data.isEmpty else {
            return nil
        }
        return data
    }

    // JSON payload.pdf or raw PDF bytes.
    private static func extractLabelPdfData(from data: Data, json: [String: Any]?, http: HTTPURLResponse) -> Data? {
        if data.starts(with: Data("%PDF".utf8)) { return data }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("application/pdf") { return data }

        if let payload = json?["payload"] as? [String: Any],
           let pdfBase64 = payload["pdf"] as? String,
           let pdfData = decodeBase64Pdf(pdfBase64) {
            return pdfData
        }

        if let pdfBase64 = json?["pdf"] as? String,
           let pdfData = decodeBase64Pdf(pdfBase64) {
            return pdfData
        }

        return nil
    }

    static func evaluateWriteResponse(
        json: [String: Any]?,
        httpStatus: Int,
        defaultSuccessMessage: String,
        defaultFailureMessage: String
    ) -> (success: Bool, message: String) {
        let httpOK = isSnipeApiHttpSuccess(httpStatus)
        let isError = isSnipeApiErrorResponse(json)
        let success = httpOK && !isError
        let message = extractApiErrorMessage(from: json ?? [:])
            ?? (success ? defaultSuccessMessage : defaultFailureMessage)
        return (success, message)
    }

    private static func isHTMLResponse(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(128), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return false }
        return prefix.hasPrefix("<!doctype") || prefix.hasPrefix("<html")
    }

    private static func idFromApiPayload(_ payload: Any?) -> Int? {
        if let id = payload as? Int { return id }
        if let str = payload as? String { return Int(str) }
        guard let dict = payload as? [String: Any] else { return nil }
        if let id = dict["id"] as? Int { return id }
        if let str = dict["id"] as? String { return Int(str) }
        return nil
    }

    func categories(for type: String) -> [CategoryRow] {
        let typed = categories.filter { ($0.categoryType ?? "").lowercased() == type.lowercased() }
        return typed.isEmpty ? categories : typed
    }

    func fetchLocations() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            // No error message needed for background fetch
            return
        }

        refreshErrorMessage = nil
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/locations",
                as: Location.self,
                reportConnectionError: true
            ) else { return }
            await MainActor.run {
                self.locations = rows.sorted {
                    $0.decodedName.lowercased() < $1.decodedName.lowercased()
                }
            }
        } catch {
            print("Error fetching locations: \(error.localizedDescription)")
        }
    }

    func fetchCompanies() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/companies",
                as: Company.self
            ) else { return }
            await MainActor.run {
                self.companies = rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching companies: \(error.localizedDescription)")
        }
    }

    func fetchGroups() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/groups",
                as: UserGroup.self
            ) else { return }
            await MainActor.run {
                self.groups = rows.sorted {
                    $0.decodedName.lowercased() < $1.decodedName.lowercased()
                }
            }
        } catch {
            print("Error fetching groups: \(error.localizedDescription)")
        }
    }

    func fetchManufacturers() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/manufacturers",
                as: Manufacturer.self
            ) else { return }
            await MainActor.run {
                self.manufacturers = rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching manufacturers: \(error.localizedDescription)")
        }
    }

    func fetchSuppliers() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/suppliers",
                as: Supplier.self
            ) else { return }
            await MainActor.run {
                self.suppliers = rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching suppliers: \(error.localizedDescription)")
        }
    }

    func fetchDepreciations() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/depreciations",
                as: DepreciationRow.self
            ) else { return }
            await MainActor.run {
                self.depreciations = rows.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        } catch {
            print("Error fetching depreciations: \(error.localizedDescription)")
        }
    }

    // Probes `/maintenance-types` first so 8.x servers always use IDs; 404 keeps legacy string mode.
    func fetchMaintenanceTypes() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let probeURL = URL(string: "\(baseURL)/api/v1/maintenance-types?limit=1&offset=0") else { return }

        var request = URLRequest(url: probeURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 404 {
                await MainActor.run {
                    self.maintenanceTypesMode = .legacy
                    self.maintenanceTypes = []
                }
                return
            }

            guard (200...299).contains(http.statusCode) else {
                #if DEBUG
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<non-UTF8>"
                print("[SnipeMobile] GET /maintenance-types status=\(http.statusCode) body=\(preview)")
                #endif
                return
            }

            await MainActor.run { self.maintenanceTypesMode = .typeIds }

            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/maintenance-types",
                as: MaintenanceType.self
            ) else { return }
            await MainActor.run {
                self.maintenanceTypes = rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching maintenance types: \(error.localizedDescription)")
        }
    }

    func fetchUsersForAccessory(accessoryId: Int) async -> [User] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            let rows = try await fetchAllPaginated(
                path: "/api/v1/accessories/\(accessoryId)/checkedout",
                as: User.self
            )
            return rows ?? []
        } catch {
            print("Error fetching users for accessory \(accessoryId): \(error.localizedDescription)")
            return []
        }
    }

    func checkoutAsset(assetId: Int, userId: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/checkout") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["assigned_user": userId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard httpResponse.statusCode == 200, !Self.isSnipeApiErrorResponse(json) else { return false }
                await refreshAssetInCache(assetId: assetId, responseJSON: json)
                syncAllInBackground()
                return true
            }
            return false
        } catch {
            await MainActor.run {
                errorMessage = "Error checking out: \(error.localizedDescription)"
            }
            return false
        }
    }

    func checkoutAssetCustom(assetId: Int, body: [String: Any]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/checkout") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var checkoutBody = body
        if checkoutBody["status_id"] == nil, let statusId = await deployedStatusIdForCheckout() {
            checkoutBody["status_id"] = statusId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: checkoutBody)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Check-out successful!",
                defaultFailureMessage: "Check-out failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshAssetInCache(assetId: assetId, responseJSON: json)
            if let parentId = body["assigned_asset"] as? Int {
                await refreshAssetInCache(assetId: parentId)
            }
            syncAllInBackground()
            return true
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error checking out: \(error.localizedDescription)"
            }
            return false
        }
    }

    func fetchActivityReport() async -> [Activity] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        let limit = Self.apiPageSize
        var allActivities: [Activity] = []
        var offset = 0
        while true {
            guard let url = URL(string: "\(baseURL)/api/v1/reports/activity?limit=\(limit)&offset=\(offset)") else {
                print("Invalid URL for activity report")
                break
            }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, _) = try await urlSession.data(for: request)
                let response = try JSONDecoder().decode(ActivityResponse.self, from: data)
                allActivities.append(contentsOf: response.rows)
                if response.rows.count < limit {
                    break
                }
                offset += limit
                try? await Task.sleep(nanoseconds: Self.pageDelayNanos)
            } catch {
                print("Error fetching activity report: \(error.localizedDescription)")
                break
            }
        }
        return allActivities
    }

    func fetchActivityForItem(itemType: String, itemId: Int, limit: Int = 50, offset: Int = 0, order: String = "desc") async -> [Activity] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/api/v1/reports/activity?limit=\(limit)&offset=\(offset)&item_type=\(itemType)&item_id=\(itemId)&order=\(order)") else {
            print("Invalid URL for filtered activity report")
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(ActivityResponse.self, from: data)
            return response.rows
        } catch {
            print("Error fetching filtered activity report: \(error.localizedDescription)")
            return []
        }
    }

    // one page of the global activity log; nil on failure
    func fetchActivityPage(limit: Int, offset: Int, order: String = "desc") async -> [Activity]? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/reports/activity?limit=\(limit)&offset=\(offset)&order=\(order)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(ActivityResponse.self, from: data)
            return response.rows
        } catch {
            print("Error fetching activity page: \(error.localizedDescription)")
            return nil
        }
    }

    func downloadFile(from url: String, preferredFilename: String? = nil) async -> URL? {
        guard !apiToken.isEmpty else { return nil }
        let resolved: URL?
        if let absolute = URL(string: url), absolute.scheme != nil {
            resolved = absolute
        } else if url.hasPrefix("/") {
            resolved = URL(string: "\(baseURL)\(url)")
        } else {
            resolved = URL(string: "\(baseURL)/\(url)")
        }
        guard let fileUrl = resolved else { return nil }

        var request = URLRequest(url: fileUrl)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Download failed: status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            guard Self.isBinaryFilePayload(data) else {
                if let message = Self.apiErrorMessage(from: data) {
                    await MainActor.run { self.lastApiMessage = message }
                }
                return nil
            }
            let rawName = preferredFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preferred = (rawName?.isEmpty == false ? rawName! : fileUrl.lastPathComponent)
            let fileName = Self.sanitizedDownloadFilename(preferred, fileId: 0, data: data)
            let localUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)_\(fileName)")
            try data.write(to: localUrl)
            return localUrl
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            print("Error downloading file: \(error)")
            return nil
        }
    }

    func fetchUserEULAs(userId: Int) async -> [ActivityFile] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/api/v1/users/\(userId)/eulas") else {
            print("Invalid URL for user EULAs")
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = json["rows"] as? [[String: Any]] {
                return rows.compactMap { row in
                    if let file = row["file"] as? [String: Any] {
                        let url = file["url"] as? String
                        let filename = file["filename"] as? String
                        return ActivityFile(url: url, filename: filename)
                    }
                    return nil
                }
            }
            // Fallback array of ActivityFile
            if let files = try? JSONDecoder().decode([ActivityFile].self, from: data) {
                return files
            }
        } catch {
            print("Error fetching user EULAs: \(error)")
        }
        return []
    }

    // MARK: - Asset Update
    struct AssetUpdateRequest: Encodable {
        struct CustomFieldValue: Encodable {
            let value: String
        }

        /// Codable wrapper to encode an explicit JSON `null`.
        /// When `String?` is `nil`, the key is typically omitted, so the server keeps the old value.
        enum NullableString: Encodable {
            case value(String)
            case null

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .value(let value):
                    try container.encode(value)
                case .null:
                    try container.encodeNil()
                }
            }
        }

        enum NullableInt: Encodable {
            case value(Int)
            case null

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .value(let value):
                    try container.encode(value)
                case .null:
                    try container.encodeNil()
                }
            }
        }

        let name: String?
        let asset_tag: String?
        let serial: NullableString?
        let model_id: Int?
        let status_id: Int?
        let category_id: Int?
        let manufacturer_id: Int?
        let supplier_id: Int?
        let notes: String?
        let order_number: String?
        let rtd_location_id: NullableInt?
        let purchase_cost: NullableString?
        let book_value: NullableString?
        let custom_fields: [String: CustomFieldValue]?
        let purchase_date: NullableString?
        let next_audit_date: NullableString?
        let expected_checkin: NullableString?
        let eol_date: NullableString?
        let warranty_months: NullableString?
        // Set to 1 to delete the current image.
        let image_delete: Int?
    }

    // MARK: - Models
    struct ModelRow: Codable, Identifiable {
        let id: Int
        let name: String
        let requireSerial: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name
            case requireSerial = "require_serial"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            // API may send bool, int (0/1) or null
            if let b = try? c.decode(Bool.self, forKey: .requireSerial) {
                requireSerial = b
            } else if let i = try? c.decode(Int.self, forKey: .requireSerial) {
                requireSerial = i == 1
            } else {
                requireSerial = nil
            }
        }
    }
    struct ModelsResponse: Codable {
        let rows: [ModelRow]
    }
    @Published var models: [ModelRow] = []

    func fetchModels() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/models",
                as: ModelRow.self
            ) else { return }
            await MainActor.run { self.models = rows }
        } catch {
            print("Error fetching models: \(error)")
        }
    }

    // MARK: - Fieldsets
    func fetchFieldsets() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/fieldsets") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = json["rows"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                let fieldsetData = try JSONSerialization.data(withJSONObject: rows)
                let fs = try decoder.decode([Fieldset].self, from: fieldsetData)
                await MainActor.run { self.fieldsets = fs }
            }
        } catch {
            print("Error fetching fieldsets: \(error)")
        }
    }

    private static func parseValidationError(json: [String: Any]?, statusCode: Int) -> (String, Bool) {
        typealias Dict = [String: Any]
        func hasSerialOrAssetTagError(_ dict: Dict?) -> Bool {
            guard let dict = dict else { return false }
            return dict["serial"] != nil || dict["asset_tag"] != nil
        }
        let errors = json?["errors"] as? Dict
        let messagesDict = json?["messages"] as? Dict
        let combined = extractApiErrorMessage(from: json ?? [:], joinAll: true)
            ?? (isSnipeApiHttpSuccess(statusCode) ? "Asset created!" : "Create failed.")
        let isDuplicate = hasSerialOrAssetTagError(errors) || hasSerialOrAssetTagError(messagesDict)
        return (combined, isDuplicate)
    }

    // MARK: - Create Asset
    struct AssetCreateRequest: Codable {
        let name: String
        let asset_tag: String
        let model_id: Int
        let status_id: Int
        let serial: String?
        let location_id: Int?
        let notes: String?
        let order_number: String?
        let purchase_cost: String?
        let book_value: String?
        let custom_fields: [String: String]?
        let purchase_date: String?
        let next_audit_date: String?
        let expected_checkin: String?
        let eol_date: String?
        let category_id: Int?
        let manufacturer_id: Int?
        let supplier_id: Int?
        let company_id: Int?
        let warranty_months: String?
        let warranty_expires: String?
        let byod: Bool?
    }

    func createAsset(_ body: AssetCreateRequest, image: UIImage? = nil) async -> (success: Bool, assetId: Int?) {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware") else { return (false, nil) }
        do {
            let encoded = try JSONEncoder().encode(body)
            var bodyObject = (try JSONSerialization.jsonObject(with: encoded) as? [String: Any]) ?? [:]
            if let customFields = body.custom_fields {
                // Some Snipe-IT versions expect custom fields as top-level _snipeit_* keys.
                for (dbKey, value) in customFields {
                    bodyObject[dbKey] = value
                }
            }

            let responseData: Data
            let httpResponse: HTTPURLResponse

            if let image, let jpeg = image.snipeJPEGUploadData() {
                #if DEBUG
                print("createAsset: POST multipart \(url.absoluteString)")
                #endif
                let result = try await sendHardwareMultipart(
                    url: url,
                    method: "POST",
                    fields: hardwareFormFields(from: bodyObject),
                    imageData: jpeg
                )
                responseData = result.0
                httpResponse = result.1
            } else {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let data = try JSONSerialization.data(withJSONObject: bodyObject)
                request.httpBody = data
                #if DEBUG
                print("createAsset: POST \(url.absoluteString)")
                #endif
                let pair = try await urlSession.data(for: request)
                responseData = pair.0
                guard let http = pair.1 as? HTTPURLResponse else {
                    await MainActor.run { self.lastApiMessage = "Geen geldige HTTP-response." }
                    return (false, nil)
                }
                httpResponse = http
            }

            #if DEBUG
            let bodyPreview = String(data: responseData.prefix(500), encoding: .utf8) ?? "<non-UTF8>"
            print("createAsset: status=\(httpResponse.statusCode) bodyPreview=\(bodyPreview)")
            #endif

            var dataToParse = responseData
            if dataToParse.count >= 3, dataToParse[0] == 0xEF, dataToParse[1] == 0xBB, dataToParse[2] == 0xBF {
                dataToParse = Data(dataToParse.dropFirst(3))
            }
            var json = (try? JSONSerialization.jsonObject(with: dataToParse)) as? [String: Any]
            if json == nil, let first = String(data: responseData.prefix(1), encoding: .utf8), first == "{" {
                json = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
            }

            // HTML body = login page or redirect, not API JSON.
            let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let isHtmlContentType = contentType.contains("text/html")
            let firstBytes = String(data: responseData.prefix(800), encoding: .utf8) ?? ""
            let firstBytesLower = firstBytes.lowercased()
            let looksLikeHTML = isHtmlContentType
                || firstBytesLower.contains("<!doctype")
                || firstBytesLower.contains("<html")
                || firstBytesLower.contains("login.microsoftonline.com")
                || firstBytesLower.contains("microsoft")
                || firstBytesLower.contains("aanmelden")

            if json == nil && httpResponse.statusCode == 200 && looksLikeHTML {
                let loginPageMsg = (firstBytesLower.contains("microsoft") || firstBytesLower.contains("aanmelden"))
                    ? L10n.string("create_response_login_page")
                    : L10n.string("create_response_not_json")
                await MainActor.run { self.lastApiMessage = loginPageMsg }
                return (false, nil)
            }

            let (parsedMsg, isDuplicateSerialOrTag) = Self.parseValidationError(json: json, statusCode: httpResponse.statusCode)
            let msg: String
            if !parsedMsg.isEmpty && parsedMsg != "Create failed." && parsedMsg != "Asset created!" {
                msg = parsedMsg
            } else if isDuplicateSerialOrTag {
                msg = L10n.string("serial_or_asset_tag_exists")
            } else {
                msg = parsedMsg
            }
            await MainActor.run { self.lastApiMessage = msg }

            if httpResponse.statusCode == 200 {
                let isSnipeError = Self.isSnipeApiErrorResponse(json)
                let isSnipeSuccess = (json?["status"] as? String)?.lowercased() == "success"
                let hasPayload = (json?["payload"] as? [String: Any])?["id"] != nil

                if !isSnipeError && (isSnipeSuccess || hasPayload) {
                    var newAssetId: Int?
                    if let json = json,
                       let payload = json["payload"], !(payload is NSNull),
                       let payloadDict = payload as? [String: Any] {
                        newAssetId = payloadDict["id"] as? Int

                        let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict)
                        if let payloadData,
                           let newAsset = try? JSONDecoder().decode(Asset.self, from: payloadData) {
                            newAssetId = newAsset.id
                            await MainActor.run { self.assets.insert(newAsset, at: 0) }
                        } else if let newAssetId,
                                  let details = await fetchHardwareDetails(assetId: newAssetId) {
                            await MainActor.run { self.assets.insert(details, at: 0) }
                        } else {
                            await self.fetchAssets()
                            if newAssetId == nil {
                                let tagSent = body.asset_tag.trimmingCharacters(in: .whitespaces)
                                newAssetId = await MainActor.run {
                                    self.assets.first(where: {
                                        $0.decodedAssetTag.caseInsensitiveCompare(tagSent) == .orderedSame
                                    })?.id
                                }
                            }
                        }
                    } else {
                        await self.fetchAssets()
                    }
                    if image != nil, let newAssetId,
                       let details = await fetchHardwareDetails(assetId: newAssetId) {
                        await MainActor.run { applyUpdatedAsset(details) }
                    }
                    if let messages = json?["messages"] as? String, !messages.isEmpty {
                        await MainActor.run { self.lastApiMessage = messages }
                    }
                    return (true, newAssetId)
                }
            }

            return (false, nil)
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return (false, nil)
        }
    }

    // MARK: - Categories
    struct CategoryRow: Codable, Identifiable {
        let id: Int
        let name: String
        let categoryType: String?
        enum CodingKeys: String, CodingKey { case id, name; case categoryType = "category_type" }
    }
    struct CategoriesResponse: Codable {
        let rows: [CategoryRow]
    }
    @Published var categories: [CategoryRow] = []

    func fetchCategories() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/categories",
                as: CategoryRow.self
            ) else { return }
            await MainActor.run { self.categories = rows }
        } catch {
            print("Error fetching categories: \(error)")
        }
    }

    // MARK: - Create Accessory
    func createAccessory(
        name: String,
        categoryId: Int,
        quantity: Int,
        minAmt: Int?,
        orderNumber: String?,
        purchaseCost: String?,
        purchaseDate: String?,
        modelNumber: String?,
        companyId: Int?,
        locationId: Int?,
        manufacturerId: Int?,
        supplierId: Int?,
        customFields: [String: String]?
    ) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/accessories") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "name": name,
            "category_id": categoryId,
            "qty": quantity
        ]
        if let minAmt, minAmt > 0 { body["min_amt"] = minAmt }
        if let v = orderNumber, !v.isEmpty {
            body["order_number"] = v
        }
        if let v = purchaseCost, !v.isEmpty, let normalized = NumberFormatHelpers.normalizeDecimalForAPI(v) {
            body["purchase_cost"] = normalized
        }
        if let v = purchaseDate, !v.isEmpty {
            body["purchase_date"] = v
        }
        if let v = modelNumber, !v.isEmpty {
            body["model_number"] = v
        }
        if let v = companyId, v > 0 {
            body["company_id"] = v
        }
        if let v = locationId, v > 0 {
            body["location_id"] = v
        }
        if let v = manufacturerId, v > 0 {
            body["manufacturer_id"] = v
        }
        if let v = supplierId, v > 0 {
            body["supplier_id"] = v
        }
        if let cf = customFields, !cf.isEmpty {
            body["custom_fields"] = cf
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let hasNewId = (json?["payload"] as? [String: Any])?["id"] != nil
            let base = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Accessory created!",
                defaultFailureMessage: "Create failed."
            )
            let success = base.success && hasNewId
            let msg = success ? base.message : (Self.extractApiErrorMessage(from: json ?? [:]) ?? base.message)
            await MainActor.run { self.lastApiMessage = msg }
            guard success else { return false }
            Task { await self.fetchAccessories() }
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    // MARK: - Update Accessory
    func updateAccessory(
        accessoryId: Int,
        name: String,
        categoryId: Int,
        quantity: Int,
        minAmt: Int?,
        orderNumber: String?,
        purchaseCost: String?,
        purchaseDate: String?,
        modelNumber: String?,
        companyId: Int?,
        locationId: Int?,
        manufacturerId: Int?,
        supplierId: Int?
    ) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/accessories/\(accessoryId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "name": name,
            "category_id": categoryId,
            "qty": quantity
        ]
        if let minAmt, minAmt > 0 { body["min_amt"] = minAmt }
        if let v = orderNumber, !v.isEmpty {
            body["order_number"] = v
        }
        if let v = purchaseCost, !v.isEmpty, let normalized = NumberFormatHelpers.normalizeDecimalForAPI(v) {
            body["purchase_cost"] = normalized
        } else {
            body["purchase_cost"] = NSNull()
        }
        if let v = purchaseDate, !v.isEmpty {
            body["purchase_date"] = v
        } else {
            body["purchase_date"] = NSNull()
        }
        if let v = modelNumber, !v.isEmpty {
            body["model_number"] = v
        }
        if let v = companyId, v > 0 {
            body["company_id"] = v
        }
        if let v = locationId, v > 0 {
            body["location_id"] = v
        }
        if let v = manufacturerId, v > 0 {
            body["manufacturer_id"] = v
        }
        if let v = supplierId, v > 0 {
            body["supplier_id"] = v
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Saved.",
                defaultFailureMessage: "Save failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshAccessoryInCache(accessoryId: accessoryId)
            Task { await self.fetchAccessories() }
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    /// DELETE asset. 405 → retry with method override.
    func deleteAsset(assetId: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            #if DEBUG
            print("[SnipeMobile] DELETE /hardware/\(assetId) — request started")
            #endif
            var (data, response) = try await urlSession.data(for: request)
            var httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 405 {
                #if DEBUG
                print("[SnipeMobile] DELETE /hardware/\(assetId) — 405 ontvangen, retry met POST + _method=DELETE (Laravel method spoofing)")
                #endif
                var postRequest = URLRequest(url: url)
                postRequest.httpMethod = "POST"
                postRequest.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                postRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                postRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                postRequest.httpBody = "_method=DELETE".data(using: .utf8)
                (data, response) = try await urlSession.data(for: postRequest)
                httpResponse = response as? HTTPURLResponse
            }

            guard let httpResponse = httpResponse else {
                #if DEBUG
                print("[SnipeMobile] DELETE /hardware/\(assetId) — geen HTTP-response")
                #endif
                await MainActor.run { self.lastApiMessage = "Geen geldige HTTP-response." }
                return false
            }
            #if DEBUG
            let responseStr = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[SnipeMobile] DELETE /hardware/\(assetId) status=\(httpResponse.statusCode) response=\(responseStr.prefix(400))")
            #endif
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Asset verwijderd.",
                defaultFailureMessage: "Verwijderen mislukt."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await MainActor.run {
                self.assets.removeAll { $0.id == assetId }
            }
            #if DEBUG
            print("[SnipeMobile] DELETE /hardware/\(assetId) — succes, uit cache verwijderd")
            #endif
            return true
        } catch {
            #if DEBUG
            print("[SnipeMobile] DELETE /hardware/\(assetId) error: \(error)")
            #endif
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    func updateAsset(assetId: Int, update: AssetUpdateRequest, image: UIImage? = nil) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)") else { return false }
        do {
            let encodedBody = try JSONEncoder().encode(update)
            var bodyObject = (try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any]) ?? [:]
            if let customFields = update.custom_fields {
                for (dbKey, wrappedValue) in customFields {
                    bodyObject[dbKey] = wrappedValue.value
                }
                bodyObject.removeValue(forKey: "custom_fields")
            }

            let data: Data
            let httpResponse: HTTPURLResponse

            if let image, let jpeg = image.snipeJPEGUploadData() {
                #if DEBUG
                print("[SnipeMobile] PUT /hardware/\(assetId) multipart (image upload)")
                #endif
                let result = try await sendHardwareMultipart(
                    url: url,
                    method: "PUT",
                    fields: hardwareFormFields(from: bodyObject),
                    imageData: jpeg
                )
                data = result.0
                httpResponse = result.1
            } else {
                let body = try JSONSerialization.data(withJSONObject: bodyObject)

                func makeRequest(method: String, bodyData: Data) -> URLRequest {
                    var request = URLRequest(url: url)
                    request.httpMethod = method
                    request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.httpBody = bodyData
                    return request
                }

                #if DEBUG
                Self.debugLogHardwareUpdate(assetId: assetId, method: "PUT", bodyObject: bodyObject)
                #endif

                var (responseData, response) = try await urlSession.data(for: makeRequest(method: "PUT", bodyData: body))
                var http = response as? HTTPURLResponse

                if http?.statusCode == 405 {
                    #if DEBUG
                    print("[SnipeMobile] PUT /hardware/\(assetId) — 405, retry POST + _method=PUT")
                    #endif
                    var spoofed = bodyObject
                    spoofed["_method"] = "PUT"
                    let spoofedBody = try JSONSerialization.data(withJSONObject: spoofed)
                    (responseData, response) = try await urlSession.data(for: makeRequest(method: "POST", bodyData: spoofedBody))
                    http = response as? HTTPURLResponse
                }

                guard let http else { return false }
                data = responseData
                httpResponse = http
            }

            #if DEBUG
            let responseStr = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[SnipeMobile] PUT /hardware/\(assetId) status: \(httpResponse.statusCode) response: \(responseStr.prefix(500))")
            #endif

            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Changes saved!",
                defaultFailureMessage: "Save failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            if let updated: Asset = decodedPatchPayload(from: data) {
                await MainActor.run { replaceCachedItem(updated, in: &self.assets, id: \.id) }
            }
            // PATCH may omit image URL.
            if image != nil || update.image_delete == 1 {
                if let details = await fetchHardwareDetails(assetId: assetId) {
                    await MainActor.run { applyUpdatedAsset(details) }
                }
            }
            return true
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error updating asset: \(error.localizedDescription)"
            }
            return false
        }
    }

    // POST /hardware/labels.
    @discardableResult
    func generateAssetLabels(assetTags: [String]) async -> Data? {
        let tags = assetTags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            await MainActor.run { self.lastApiMessage = L10n.string("labels_generate_failed") }
            return nil
        }
        guard !tags.isEmpty else {
            await MainActor.run { self.lastApiMessage = L10n.string("labels_no_asset_tags") }
            return nil
        }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/labels") else {
            await MainActor.run { self.lastApiMessage = L10n.string("labels_generate_failed") }
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["asset_tags": tags])
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { self.lastApiMessage = L10n.string("labels_generate_failed") }
                return nil
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            #if DEBUG
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "?"
            if data.starts(with: Data("%PDF".utf8)) {
                print("[SnipeMobile] POST /hardware/labels (\(tags.count) tags) status: \(http.statusCode) response: <raw PDF, \(data.count) bytes>")
            } else if let preview = String(data: data.prefix(240), encoding: .utf8) {
                print("[SnipeMobile] POST /hardware/labels (\(tags.count) tags) status: \(http.statusCode) content-type: \(contentType) response: \(preview)…")
            } else {
                print("[SnipeMobile] POST /hardware/labels (\(tags.count) tags) status: \(http.statusCode) content-type: \(contentType) response: <binary \(data.count) bytes>")
            }
            #endif

            if !Self.isSnipeApiHttpSuccess(http.statusCode) || Self.isSnipeApiErrorResponse(json) {
                let message: String
                if let payload = json?["payload"] as? [String: Any],
                   let detail = payload["error_message"] as? String, !detail.isEmpty {
                    message = detail
                } else {
                    message = Self.extractApiErrorMessage(from: json ?? [:]) ?? L10n.string("labels_generate_failed")
                }
                await MainActor.run { self.lastApiMessage = message }
                return nil
            }

            if let pdfData = Self.extractLabelPdfData(from: data, json: json, http: http) {
                return pdfData
            }

            await MainActor.run { self.lastApiMessage = L10n.string("labels_generate_failed") }
            return nil
        } catch {
            await MainActor.run { self.lastApiMessage = error.localizedDescription }
            return nil
        }
    }

    // Audits an asset via POST /hardware/audit (same as the web bulk audit).
    func auditAsset(
        assetTag: String,
        assetId: Int? = nil,
        locationId: Int? = nil,
        updateLocation: Bool = false,
        nextAuditDate: String? = nil,
        note: String? = nil
    ) async -> Bool {
        let trimmedTag = assetTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, !apiToken.isEmpty, !trimmedTag.isEmpty else { return false }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/audit") else { return false }

        let cleanNextAudit = nextAuditDate?.trimmingCharacters(in: .whitespacesAndNewlines)

        var body: [String: Any] = ["asset_tag": trimmedTag]
        if let locationId, locationId != 0 { body["location_id"] = locationId }
        if updateLocation { body["update_location"] = true }
        if let cleanNextAudit, !cleanNextAudit.isEmpty { body["next_audit_date"] = cleanNextAudit }
        if let note {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNote.isEmpty { body["note"] = trimmedNote }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            #if DEBUG
            let responseStr = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("[SnipeMobile] POST /hardware/audit (\(trimmedTag)) status: \(http.statusCode) response: \(responseStr.prefix(300))")
            #endif

            if !Self.isSnipeApiHttpSuccess(http.statusCode) {
                await MainActor.run { self.lastApiMessage = Self.extractApiErrorMessage(from: json ?? [:]) ?? "Audit failed." }
                return false
            }
            if Self.isSnipeApiErrorResponse(json) {
                await MainActor.run { self.lastApiMessage = Self.extractApiErrorMessage(from: json ?? [:]) ?? "Audit failed." }
                return false
            }

            // Some servers wipe next_audit_date on audit, so set it again. (#8456)
            if let assetId, let cleanNextAudit, !cleanNextAudit.isEmpty {
                let update = AssetUpdateRequest(
                    name: nil, asset_tag: nil, serial: nil, model_id: nil,
                    status_id: nil, category_id: nil, manufacturer_id: nil,
                    supplier_id: nil, notes: nil, order_number: nil, rtd_location_id: nil,
                    purchase_cost: nil, book_value: nil, custom_fields: nil,
                    purchase_date: nil, next_audit_date: .value(cleanNextAudit),
                    expected_checkin: nil, eol_date: nil, warranty_months: nil,
                    image_delete: nil
                )
                _ = await updateAsset(assetId: assetId, update: update)
            }
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    #if DEBUG
    private static func debugLogHardwareUpdate(assetId: Int, method: String, bodyObject: [String: Any]) {
        var logged = bodyObject
        if let image = logged["image"] as? String, image.count > 80 {
            logged["image"] = String(image.prefix(60)) + "…(\(image.count) chars)"
        }
        print("[SnipeMobile] \(method) /hardware/\(assetId) body: \(logged)")
    }
    #endif

    // MARK: - Asset tag generation (Snipe-IT prefix / auto-increment)

    struct AssetTagGenerationSettings: Equatable {
        let autoIncrementAssets: Bool
        let prefix: String
        let zerofillCount: Int
        let nextAutoTagBase: Int
    }

    @Published private(set) var assetTagSettings: AssetTagGenerationSettings?

    /// Fetches Snipe-IT asset-tag settings (prefix, zerofill, next number). Requires superuser API access; silently no-ops otherwise.
    func fetchAssetTagSettings() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/settings/1") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let settings = Self.parseAssetTagSettings(from: json) else { return }
            await MainActor.run { self.assetTagSettings = settings }
        } catch {
            #if DEBUG
            print("fetchAssetTagSettings: \(error)")
            #endif
        }
    }

    /// Next asset tag respecting Snipe-IT prefix/zerofill when available, otherwise inferred from existing tags.
    func nextAvailableAssetTag() -> String {
        let tags = assets
            .map { $0.assetTag.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let settings = assetTagSettings, settings.autoIncrementAssets || !settings.prefix.isEmpty {
            return Self.formatNextAssetTag(tags: tags, settings: settings)
        }
        return Self.inferNextAssetTag(from: tags)
    }

    static func initialCustomFieldValue(existing: String?, defaultValue: String?) -> String {
        if let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        return defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func parseAssetTagSettings(from json: [String: Any]) -> AssetTagGenerationSettings? {
        let dict = (json["payload"] as? [String: Any]) ?? json
        let hasKeys = dict["auto_increment_prefix"] != nil
            || dict["next_auto_tag_base"] != nil
            || dict["auto_increment_assets"] != nil
            || dict["zerofill_count"] != nil
        guard hasKeys else { return nil }
        return AssetTagGenerationSettings(
            autoIncrementAssets: parseSnipeBool(dict["auto_increment_assets"]),
            prefix: (dict["auto_increment_prefix"] as? String) ?? "",
            zerofillCount: parseSnipeInt(dict["zerofill_count"]) ?? 0,
            nextAutoTagBase: parseSnipeInt(dict["next_auto_tag_base"]) ?? 1
        )
    }

    private static func parseSnipeBool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let i as Int: return i != 0
        case let s as String: return s == "1" || s.lowercased() == "true"
        default: return false
        }
    }

    private static func parseSnipeInt(_ value: Any?) -> Int? {
        switch value {
        case let i as Int: return i
        case let s as String: return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
        case let d as Double: return Int(d)
        default: return nil
        }
    }

    private static let taggedNumberRegex = try? NSRegularExpression(pattern: "^(.*?)(\\d+)$")

    private static func parseTaggedNumber(_ tag: String) -> (prefix: String, number: Int, width: Int)? {
        guard let regex = taggedNumberRegex else { return nil }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = regex.firstMatch(in: tag, range: range),
              match.numberOfRanges == 3,
              let prefixRange = Range(match.range(at: 1), in: tag),
              let numRange = Range(match.range(at: 2), in: tag),
              let number = Int(tag[numRange]) else { return nil }
        return (String(tag[prefixRange]), number, tag[numRange].count)
    }

    private static func formatNextAssetTag(tags: [String], settings: AssetTagGenerationSettings) -> String {
        let prefix = settings.prefix
        let relevantTags = prefix.isEmpty ? tags : tags.filter { $0.hasPrefix(prefix) }
        var suffixNumbers: [(num: Int, width: Int)] = []
        for tag in relevantTags {
            let suffix = prefix.isEmpty ? tag : String(tag.dropFirst(prefix.count))
            let digits = suffix.filter(\.isNumber)
            if !digits.isEmpty, let num = Int(digits) {
                suffixNumbers.append((num, digits.count))
            } else if let parsed = parseTaggedNumber(tag) {
                suffixNumbers.append((parsed.number, parsed.width))
            }
        }
        let maxFromTags = suffixNumbers.map(\.num).max() ?? 0
        let nextNum = max(settings.nextAutoTagBase, maxFromTags + 1)
        let widthFromTags = suffixNumbers.map(\.width).max() ?? 0
        let numeric: String
        if settings.zerofillCount > 0 {
            numeric = String(format: "%0*d", settings.zerofillCount, nextNum)
        } else if widthFromTags > 0 {
            numeric = String(format: "%0*d", widthFromTags, nextNum)
        } else {
            numeric = "\(nextNum)"
        }
        return prefix + numeric
    }

    private static func inferNextAssetTag(from tags: [String]) -> String {
        var byPrefix: [String: [(num: Int, width: Int)]] = [:]
        for tag in tags {
            guard let parsed = parseTaggedNumber(tag) else { continue }
            byPrefix[parsed.prefix, default: []].append((parsed.number, parsed.width))
        }
        if let best = byPrefix.max(by: { $0.value.count < $1.value.count }), !best.value.isEmpty {
            let nextNum = (best.value.map(\.num).max() ?? 0) + 1
            let width = max(best.value.map(\.width).max() ?? 0, String(nextNum).count)
            let numeric = String(format: "%0*d", width, nextNum)
            return best.key + numeric
        }

        let numbers = tags.compactMap { tag -> Int? in
            let digits = tag.filter(\.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }
        let nextNum = (numbers.max() ?? 0) + 1
        let digitLengths = tags.compactMap { tag -> Int? in
            let digits = tag.filter(\.isNumber)
            return digits.isEmpty ? nil : digits.count
        }
        let width = digitLengths.max() ?? 5
        return String(format: "%0*d", width, nextNum)
    }

    // MARK: - Field defs
    struct FieldDefinition: Codable, Identifiable, Equatable {
        let id: Int
        let name: String
        let type: String?
        let field_values_array: [String]?
        let db_column_name: String?
        let db_column: String?
        let db_field: String?
        let field: String?
        let default_value: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case type
            case field_values_array
            case db_column_name
            case db_column
            case db_field
            case field
            case default_value
        }
    }

    @MainActor
    @Published var fieldDefinitions: [FieldDefinition] = []

    func fetchFieldDefinitions() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/fields") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = json["rows"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                let fieldData = try JSONSerialization.data(withJSONObject: rows)
                let fields = try decoder.decode([FieldDefinition].self, from: fieldData)
                await MainActor.run {
                    self.fieldDefinitions = fields
                }
            }
        } catch {
            print("Error fetching field definitions: \(error)")
        }
    }

    @MainActor
    @Published var modelFieldDefinitions: [FieldDefinition]? = nil

    func fetchModelFieldDefinitions(modelId: Int) async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/models/\(modelId)/fields") else { return }
        await MainActor.run { self.modelFieldDefinitions = nil }
        if fieldsets == nil {
            await fetchFieldsets()
        }
        if let fieldsetId = fieldsetId(forModelId: modelId),
           let withDefaults = await fetchFieldsetFieldsWithDefaults(fieldsetId: fieldsetId, modelId: modelId),
           !withDefaults.isEmpty {
            await MainActor.run { self.modelFieldDefinitions = withDefaults }
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let fields: [FieldDefinition]
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let decoder = JSONDecoder()
                if let rows = json["rows"] as? [[String: Any]],
                   let fieldData = try? JSONSerialization.data(withJSONObject: rows) {
                    fields = (try? decoder.decode([FieldDefinition].self, from: fieldData)) ?? []
                } else if let arr = json["fields"] as? [[String: Any]],
                          let fieldData = try? JSONSerialization.data(withJSONObject: arr) {
                    fields = (try? decoder.decode([FieldDefinition].self, from: fieldData)) ?? []
                } else {
                    fields = (try? decoder.decode([FieldDefinition].self, from: data)) ?? []
                }
            } else {
                fields = (try? JSONDecoder().decode([FieldDefinition].self, from: data)) ?? []
            }
            if fields.isEmpty, self.fieldsets == nil {
                await self.fetchFieldsets()
            }
            await MainActor.run {
                let fallback = self.modelFieldDefinitionsFromFieldsets(modelId: modelId)
                self.modelFieldDefinitions = fields.isEmpty ? fallback : fields
            }
        } catch {
            print("Error fetching model field definitions: \(error)")
            if self.fieldsets == nil { await self.fetchFieldsets() }
            await MainActor.run {
                self.modelFieldDefinitions = self.modelFieldDefinitionsFromFieldsets(modelId: modelId)
            }
        }
    }

    private func fieldsetId(forModelId modelId: Int) -> Int? {
        fieldsets?.first(where: { $0.modelIds.contains(modelId) })?.id
    }

    private func fetchFieldsetFieldsWithDefaults(fieldsetId: Int, modelId: Int) async -> [FieldDefinition]? {
        guard let url = URL(string: "\(baseURL)/api/v1/fieldsets/\(fieldsetId)/fields/\(modelId)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return decodeFieldDefinitionRows(from: data)
        } catch {
            return nil
        }
    }

    private func decodeFieldDefinitionRows(from data: Data) -> [FieldDefinition]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let decoder = JSONDecoder()
        if let rows = json["rows"] as? [[String: Any]],
           let fieldData = try? JSONSerialization.data(withJSONObject: rows) {
            return try? decoder.decode([FieldDefinition].self, from: fieldData)
        }
        return try? decoder.decode([FieldDefinition].self, from: data)
    }

    struct StatusLabelResponse: Codable {
        let rows: [StatusLabel]
    }

    func fetchStatusLabels() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/statuslabels",
                as: StatusLabel.self
            ) else { return }
            await MainActor.run {
                self.statusLabels = rows
            }
        } catch {
            print("Error fetching status labels: \(error)")
        }
    }

    // MARK: - Fieldsets
    struct Fieldset: Codable, Identifiable {
        let id: Int
        let name: String
        let fields: FieldsetFields
        let models: FieldsetModels?
        /// Some Snipe versions: models as array.
        let modelsDirect: [FieldsetModelRow]?
        struct FieldsetFields: Codable {
            let rows: [FieldsetField]
        }
        struct FieldsetModels: Codable {
            let rows: [FieldsetModelRow]
        }
        struct FieldsetModelRow: Codable {
            let id: Int
            let name: String
        }
        enum CodingKeys: String, CodingKey {
            case id, name, fields, models
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            fields = try c.decode(FieldsetFields.self, forKey: .fields)
            models = try? c.decode(FieldsetModels.self, forKey: .models)
            modelsDirect = try? c.decode([FieldsetModelRow].self, forKey: .models)
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(fields, forKey: .fields)
            try c.encodeIfPresent(models, forKey: .models)
        }
        var modelIds: [Int] {
            if let rows = models?.rows { return rows.map(\.id) }
            if let arr = modelsDirect { return arr.map(\.id) }
            return []
        }
    }

    struct FieldsetField: Codable, Identifiable {
        let id: Int
        let name: String
        let type: String
        let field_values_array: [String]?
        // Extend as needed
    }

    @MainActor
    @Published var fieldsets: [Fieldset]? = nil

    func modelFieldDefinitionsFromFieldsets(modelId: Int) -> [FieldDefinition] {
        guard let fieldsets = fieldsets else { return [] }
        guard let fieldset = fieldsets.first(where: { fs in
            fs.modelIds.contains(modelId)
        }) else { return [] }
        return fieldset.fields.rows.map { f in
            FieldDefinition(
                id: f.id,
                name: f.name,
                type: f.type,
                field_values_array: f.field_values_array,
                db_column_name: nil,
                db_column: nil,
                db_field: nil,
                field: nil,
                default_value: nil
            )
        }
    }

    func checkinAsset(assetId: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/checkin") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard httpResponse.statusCode == 200, !Self.isSnipeApiErrorResponse(json) else { return false }
                await refreshAssetInCache(assetId: assetId, responseJSON: json)
                syncAllInBackground()
                return true
            }
            return false
        } catch {
            await MainActor.run {
                errorMessage = "Error checking in: \(error.localizedDescription)"
            }
            return false
        }
    }

    func checkinAssetCustom(assetId: Int, body: [String: Any]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/checkin") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Check-in successful!",
                defaultFailureMessage: "Check-in failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshAssetInCache(assetId: assetId, responseJSON: json)
            syncAllInBackground()
            return true
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error checking in: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - Asset files (`/hardware/{id}/files`)

    func fetchAssetFiles(assetId: Int) async -> [AssetFile] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/files?limit=500&offset=0&sort=created_at&order=desc") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            if let decoded = try? JSONDecoder().decode(AssetFileResponse.self, from: data) {
                return decoded.rows
            }
            return []
        } catch {
            #if DEBUG
            print("fetchAssetFiles error: \(error)")
            #endif
            return []
        }
    }

    /// POST /hardware/{id}/files (`file[]` multipart).
    func uploadAssetFiles(
        assetId: Int,
        files: [(filename: String, mimeType: String, data: Data)],
        notes: String? = nil
    ) async -> Bool {
        guard !files.isEmpty else { return true }
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return false }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/files") else { return false }

        var fields: [String: String] = [:]
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["notes"] = notes
        }

        do {
            let boundary = "Boundary-\(UUID().uuidString)"
            let body = buildMultipartFileBody(boundary: boundary, fields: fields, files: files)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = body

            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: http.statusCode,
                defaultSuccessMessage: L10n.string("file_upload_success"),
                defaultFailureMessage: L10n.string("file_upload_failed")
            )
            await MainActor.run { self.lastApiMessage = result.message }
            return result.success
        } catch {
            await MainActor.run {
                self.lastApiMessage = "\(L10n.string("file_upload_failed")): \(error.localizedDescription)"
            }
            return false
        }
    }

    /// Upload UIImages as JPEGs.
    func uploadAssetFiles(assetId: Int, images: [UIImage], notes: String? = nil) async -> Bool {
        guard !images.isEmpty else { return true }
        var files: [(filename: String, mimeType: String, data: Data)] = []
        for (index, image) in images.enumerated() {
            guard let data = image.snipeJPEGUploadData() else { continue }
            files.append((filename: "photo-\(index + 1).jpg", mimeType: "image/jpeg", data: data))
        }
        guard !files.isEmpty else {
            await MainActor.run { lastApiMessage = L10n.string("photo_upload_failed") }
            return false
        }
        return await uploadAssetFiles(assetId: assetId, files: files, notes: notes)
    }

    func downloadAssetFile(assetId: Int, fileId: Int, preferredFilename: String) async -> URL? {
        await downloadObjectFile(
            objectType: "hardware",
            objectId: assetId,
            fileId: fileId,
            preferredFilename: preferredFilename
        )
    }

    /// GET …/files/{fileId} (Bearer).
    func downloadObjectFile(
        objectType: String,
        objectId: Int,
        fileId: Int,
        preferredFilename: String
    ) async -> URL? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        let type = Self.apiFilesObjectType(objectType)
        guard let url = URL(string: "\(baseURL)/api/v1/\(type)/\(objectId)/files/\(fileId)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                #if DEBUG
                print("downloadObjectFile failed: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                return nil
            }
            guard Self.isBinaryFilePayload(data) else {
                if let message = Self.apiErrorMessage(from: data) {
                    await MainActor.run { self.lastApiMessage = message }
                }
                return nil
            }
            let filename = Self.sanitizedDownloadFilename(preferredFilename, fileId: fileId, data: data)
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(filename)")
            try data.write(to: localURL, options: .atomic)
            return localURL
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            #if DEBUG
            print("downloadObjectFile error: \(error)")
            #endif
            return nil
        }
    }

    static func isBinaryFilePayload(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        // JSON error bodies (often HTTP 200 from Snipe-IT).
        if data.first == UInt8(ascii: "{") || data.first == UInt8(ascii: "[") {
            return false
        }
        if let head = String(data: data.prefix(200), encoding: .utf8)?.lowercased(),
           head.contains("<!doctype html") || head.contains("<html") {
            return false
        }
        return true
    }

    static func apiErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let messages = json["messages"] as? String, !messages.isEmpty { return messages }
        if let messages = json["messages"] as? [String], let first = messages.first { return first }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        return nil
    }

    static func sanitizedDownloadFilename(_ preferred: String, fileId: Int, data: Data) -> String {
        var name = preferred
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = fileId > 0 ? "file-\(fileId)" : "file" }
        let ext = (name as NSString).pathExtension.lowercased()
        if data.starts(with: Data("%PDF".utf8)), ext != "pdf" {
            name += ".pdf"
        }
        return name
    }

    /// Map item type → API object_type.
    static func apiFilesObjectType(_ itemType: String) -> String {
        switch itemType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "asset", "assets", "hardware": return "hardware"
        case "accessory", "accessories": return "accessories"
        case "component", "components": return "components"
        case "consumable", "consumables": return "consumables"
        case "license", "licenses": return "licenses"
        case "user", "users": return "users"
        case "location", "locations": return "locations"
        case "model", "models", "asset_models": return "models"
        case "maintenance", "maintenances": return "maintenances"
        default: return itemType
        }
    }

    func deleteAssetFile(assetId: Int, fileId: Int) async -> Bool {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return false }
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/files/\(fileId)/delete") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: http.statusCode,
                defaultSuccessMessage: L10n.string("file_delete_success"),
                defaultFailureMessage: L10n.string("file_delete_failed")
            )
            await MainActor.run { self.lastApiMessage = result.message }
            return result.success
        } catch {
            await MainActor.run {
                self.lastApiMessage = "\(L10n.string("file_delete_failed")): \(error.localizedDescription)"
            }
            return false
        }
    }

    private func buildMultipartFileBody(
        boundary: String,
        fields: [String: String],
        files: [(filename: String, mimeType: String, data: Data)]
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) { body.append(data) }
        }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        for file in files {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"file[]\"; filename=\"\(file.filename)\"\r\n")
            append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        return body
    }

    func checkoutAccessoryCustom(accessoryId: Int, body: [String: Any]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/accessories/\(accessoryId)/checkout") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            #if DEBUG
            let preview = String(data: data.prefix(600), encoding: .utf8) ?? ""
            print("[SnipeMobile] POST /accessories/\(accessoryId)/checkout status=\(httpResponse.statusCode) body=\(preview)")
            #endif

            guard Self.isSnipeApiHttpSuccess(httpResponse.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                await MainActor.run {
                    self.lastApiMessage = Self.extractApiErrorMessage(from: json ?? [:])
                        ?? "HTTP \(httpResponse.statusCode): \(preview)"
                }
                return false
            }

            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Check-out successful.",
                defaultFailureMessage: "Check-out failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshAccessoryInCache(accessoryId: accessoryId)
            syncAllInBackground()
            return true
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error checking out accessory: \(error.localizedDescription)"
            }
            return false
        }
    }

    func checkinAccessory(accessoryId: Int, checkedoutId: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/accessories/\(accessoryId)/checkin") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["checkedout_id": checkedoutId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: httpResponse.statusCode,
                defaultSuccessMessage: "Check-in successful.",
                defaultFailureMessage: "Check-in failed."
            )
            await MainActor.run { self.lastApiMessage = result.message }
            guard result.success else { return false }
            await refreshAccessoryInCache(accessoryId: accessoryId)
            syncAllInBackground()
            return true
        } catch {
            return false
        }
    }

    private func mergeAssetFromResponseJSON(_ json: [String: Any]?) {
        guard let json else { return }

        func decodeAsset(from object: Any) -> Asset? {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) else {
                return nil
            }
            return try? JSONDecoder().decode(Asset.self, from: data)
        }

        let candidates: [Any?] = [
            json["payload"],
            (json["payload"] as? [String: Any])?["asset"]
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            if let updatedAsset = decodeAsset(from: candidate) {
                if let idx = assets.firstIndex(where: { $0.id == updatedAsset.id }) {
                    assets[idx] = updatedAsset
                } else {
                    assets.insert(updatedAsset, at: 0)
                }
                return
            }
        }
    }

    func validateApiCredentials() async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "Please enter both API URL and API Key." }
        guard let url = URL(string: "\(baseURL)/api/v1/users") else { return "Invalid URL format." }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return nil // OK
            } else {
                return "Invalid API credentials or URL."
            }
        } catch {
            if Self.isTLSCertificateError(error) {
                return L10n.string("refresh_failed_certificate")
            }
            return "Could not connect to Snipe-IT. Check your URL and API key."
        }
    }

    struct AccessoryCheckedOutRow: Codable, Identifiable, Hashable {
        let id: Int?
        let assignedTo: AssignedToCheckedOut?
        let note: String?
        let createdBy: CreatedByCheckedOut?
        let createdAt: DateInfoCheckedOut?
        let availableActions: AvailableActionsCheckedOut?

        enum CodingKeys: String, CodingKey {
            case id
            case assignedTo = "assigned_to"
            case note
            case createdBy = "created_by"
            case createdAt = "created_at"
            case availableActions = "available_actions"
        }
    }

    struct AssignedToCheckedOut: Codable, Hashable {
        let id: Int?
        let image: String?
        let type: String?
        let name: String?
        let firstName: String?
        let lastName: String?
        let username: String?
        let model: String?
        let assetTag: String?
        let serial: String?
        let createdBy: CreatedByCheckedOut?
        let createdAt: DateInfoCheckedOut?
        let deletedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, image, type, name
            case firstName = "first_name"
            case lastName = "last_name"
            case username
            case model
            case assetTag = "asset_tag"
            case serial
            case createdBy = "created_by"
            case createdAt = "created_at"
            case deletedAt = "deleted_at"
        }

        var decodedName: String { HTMLDecoder.decode(name ?? "") }
        var decodedModel: String { HTMLDecoder.decode(model ?? "") }
        var decodedAssetTag: String { HTMLDecoder.decode(assetTag ?? "") }

        var isUser: Bool { type?.lowercased() == "user" }
        var isLocation: Bool { type?.lowercased() == "location" }
        var isAsset: Bool { type?.lowercased() == "asset" }
    }

    struct CreatedByCheckedOut: Codable, Hashable {
        let id: Int?
        let name: String?
    }

    struct DateInfoCheckedOut: Codable, Hashable {
        let datetime: String?
        let formatted: String?
    }

    struct AvailableActionsCheckedOut: Codable, Hashable {
        let checkin: Bool?
    }

    struct AccessoryCheckedOutResponse: Codable {
        let total: Int?
        let rows: [AccessoryCheckedOutRow]
    }

    func fetchAccessoryCheckedOutList(accessoryId: Int) async -> [AccessoryCheckedOutRow] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            let rows = try await fetchAllPaginated(
                path: "/api/v1/accessories/\(accessoryId)/checkedout",
                as: AccessoryCheckedOutRow.self
            )
            return rows ?? []
        } catch {
            #if DEBUG
            print("fetchAccessoryCheckedOutList error: \(error)")
            #endif
            return []
        }
    }

    func fetchAccessoryDetails(accessoryId: Int) async -> Accessory? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/accessories/\(accessoryId)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return nil }

            if let accessory = try? JSONDecoder().decode(Accessory.self, from: data) {
                return accessory
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let payload = json["payload"] as? [String: Any],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let accessory = try? JSONDecoder().decode(Accessory.self, from: payloadData) {
                return accessory
            }

            return nil
        } catch {
            return nil
        }
    }

    static func extractDellServiceTag(from url: URL) -> String? {
        let components = url.path.components(separatedBy: "/")
        if let idx = components.firstIndex(where: { $0.lowercased() == "servicetag" }),
           components.indices.contains(components.index(after: idx)) {
            let tag = components[components.index(after: idx)]
            if !tag.isEmpty { return tag }
        }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            let keys = ["servicetag", "serviceTag", "st", "ST", "t", "T"]
            for key in keys {
                if let value = queryItems.first(where: { $0.name == key })?.value, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    func fetchMaintenances(assetId: Int) async -> [AssetMaintenance]? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        do {
            return try await fetchAllPaginated(
                path: "/api/v1/maintenances",
                as: AssetMaintenance.self,
                extraQueryItems: [URLQueryItem(name: "asset_id", value: String(assetId))]
            )
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return nil
        }
    }

    // every asset's maintenance, for the Hardware → Maintenance overview (cached for offline)
    @discardableResult
    func fetchAllMaintenances() async -> [AssetMaintenance]? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        do {
            guard let rows = try await fetchAllPaginated(
                path: "/api/v1/maintenances",
                as: AssetMaintenance.self,
                extraQueryItems: [
                    URLQueryItem(name: "sort", value: "start_date"),
                    URLQueryItem(name: "order", value: "desc")
                ]
            ) else { return nil }
            let sorted = rows.sorted { ($0.startDate?.date ?? "") > ($1.startDate?.date ?? "") }
            self.maintenances = sorted
            return sorted
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return nil
        }
    }

    func fetchMaintenance(id: Int) async -> AssetMaintenance? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/maintenances/\(id)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else { return nil }

            if let record = try? JSONDecoder().decode(AssetMaintenance.self, from: data) {
                return record
            }
            if let record: AssetMaintenance = decodedPatchPayload(from: data) {
                return record
            }
            return nil
        } catch {
            return nil
        }
    }

    func createMaintenance(_ body: MaintenanceCreateRequest, image: UIImage? = nil) async -> Bool {
        (await createMaintenanceReturningId(body, image: image)) != nil
    }

    /// Returns the new maintenance id from the create response payload.
    private func createMaintenanceReturningId(_ body: MaintenanceCreateRequest, image: UIImage? = nil) async -> Int? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/v1/maintenances") else { return nil }

        do {
            let encoded = try JSONEncoder().encode(body)
            var bodyObject = (try JSONSerialization.jsonObject(with: encoded) as? [String: Any]) ?? [:]
            let imagePayload = prepareMaintenanceImagePayload(image)
            var responseData: Data
            var http: HTTPURLResponse

            if let jpeg = imagePayload.jpeg {
                let result = try await sendHardwareMultipart(
                    url: url,
                    method: "POST",
                    fields: hardwareFormFields(from: bodyObject),
                    imageData: jpeg
                )
                let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]
                let multipartResult = Self.evaluateWriteResponse(
                    json: json,
                    httpStatus: result.1.statusCode,
                    defaultSuccessMessage: "Maintenance created.",
                    defaultFailureMessage: "Create failed."
                )
                if multipartResult.success {
                    return maintenanceIdFromResponse(result.0)
                }
                if let imageSource = imagePayload.imageSource {
                    bodyObject["image_source"] = imageSource
                } else {
                    await MainActor.run { self.lastApiMessage = multipartResult.message }
                    return nil
                }
            } else if let imageSource = imagePayload.imageSource {
                bodyObject["image_source"] = imageSource
            }

            let jsonBody = try JSONSerialization.data(withJSONObject: bodyObject)
            let pair = try await urlSession.data(for: makeMaintenanceJSONRequest(url: url, method: "POST", bodyData: jsonBody))
            guard let httpResponse = pair.1 as? HTTPURLResponse else { return nil }
            responseData = pair.0
            http = httpResponse

            let json = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: http.statusCode,
                defaultSuccessMessage: "Maintenance created.",
                defaultFailureMessage: "Create failed."
            )
            if !result.success {
                await MainActor.run { self.lastApiMessage = result.message }
                return nil
            }
            return maintenanceIdFromResponse(responseData)
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return nil
        }
    }

    private func maintenanceIdFromResponse(_ data: Data) -> Int? {
        if let record: AssetMaintenance = decodedPatchPayload(from: data) {
            return record.id
        }
        if let record = try? JSONDecoder().decode(AssetMaintenance.self, from: data) {
            return record.id
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let id = json["id"] as? Int { return id }
        if let payload = json["payload"] as? [String: Any], let id = payload["id"] as? Int { return id }
        return nil
    }

    /// Returns the maintenance id on success (may differ from `id` when the image was changed).
    func updateMaintenance(
        id: Int,
        assetId: Int,
        update: MaintenanceUpdateRequest,
        image: UIImage? = nil,
        wasCompleted: Bool = false
    ) async -> Int? {
        let wantsImageChange = image != nil || update.image_delete == 1
        if wantsImageChange {
            return await updateMaintenanceRecreatingForImage(
                id: id,
                assetId: assetId,
                update: update,
                image: image,
                wasCompleted: wasCompleted
            )
        }
        guard await updateMaintenanceFields(id: id, update: update) else { return nil }
        return id
    }

    /// Snipe-IT's REST update endpoint does not call `handleImages()`; recreate via store instead.
    private func updateMaintenanceRecreatingForImage(
        id: Int,
        assetId: Int,
        update: MaintenanceUpdateRequest,
        image: UIImage?,
        wasCompleted: Bool
    ) async -> Int? {
        guard let create = maintenanceCreateRequest(from: update, assetId: assetId) else {
            await MainActor.run { self.lastApiMessage = L10n.string("error") }
            return nil
        }
        let uploadImage = (update.image_delete == 1 && image == nil) ? nil : image
        guard let newId = await createMaintenanceReturningId(create, image: uploadImage) else { return nil }
        if wasCompleted {
            _ = await completeMaintenance(id: newId)
        }
        guard await deleteMaintenance(id: id) else { return nil }
        return newId
    }

    private func maintenanceCreateRequest(from update: MaintenanceUpdateRequest, assetId: Int) -> MaintenanceCreateRequest? {
        guard let name = update.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let startDate = update.start_date, !startDate.isEmpty else { return nil }
        return MaintenanceCreateRequest(
            asset_id: assetId,
            name: name,
            asset_maintenance_type: update.asset_maintenance_type,
            maintenance_type_id: update.maintenance_type_id,
            supplier_id: update.supplier_id,
            cost: update.cost,
            notes: update.notes,
            url: update.url,
            responsible_party_id: update.responsible_party_id,
            start_date: startDate,
            completion_date: update.completion_date,
            is_warranty: update.is_warranty ?? false
        )
    }

    private func updateMaintenanceFields(id: Int, update: MaintenanceUpdateRequest) async -> Bool {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return false }
        guard let url = URL(string: "\(baseURL)/api/v1/maintenances/\(id)") else { return false }

        do {
            let encodedBody = try JSONEncoder().encode(update)
            let bodyObject = (try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any]) ?? [:]
            let body = try JSONSerialization.data(withJSONObject: bodyObject)

            func makeRequest(method: String, bodyData: Data) -> URLRequest {
                makeMaintenanceJSONRequest(url: url, method: method, bodyData: bodyData)
            }

            var (responseData, response) = try await urlSession.data(for: makeRequest(method: "PUT", bodyData: body))
            var http = response as? HTTPURLResponse

            if http?.statusCode == 405 {
                var spoofed = bodyObject
                spoofed["_method"] = "PUT"
                let spoofedBody = try JSONSerialization.data(withJSONObject: spoofed)
                (responseData, response) = try await urlSession.data(for: makeRequest(method: "POST", bodyData: spoofedBody))
                http = response as? HTTPURLResponse
            }

            guard let http else { return false }

            let json = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: http.statusCode,
                defaultSuccessMessage: "Changes saved.",
                defaultFailureMessage: "Update failed."
            )
            if !result.success {
                await MainActor.run { self.lastApiMessage = result.message }
                return false
            }
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    func completeMaintenance(id: Int, note: String? = nil) async -> Bool {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return false }
        guard let url = URL(string: "\(baseURL)/api/v1/maintenances/\(id)/complete") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNote, !trimmedNote.isEmpty {
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["note": trimmedNote])
        }

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: http.statusCode,
                defaultSuccessMessage: "Complete failed.",
                defaultFailureMessage: "Complete failed."
            )
            if !result.success {
                await MainActor.run { self.lastApiMessage = result.message }
                return false
            }
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    func deleteMaintenance(id: Int) async -> Bool {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return false }
        guard let url = URL(string: "\(baseURL)/api/v1/maintenances/\(id)") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let result = Self.evaluateWriteResponse(
                json: json,
                httpStatus: http.statusCode,
                defaultSuccessMessage: "Delete failed.",
                defaultFailureMessage: "Delete failed."
            )
            if !result.success {
                await MainActor.run { self.lastApiMessage = result.message }
                return false
            }
            return true
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }
}

// MARK: - Management CRUD (Settings → Management)
extension SnipeITAPIClient {
    struct ManagementWriteResult {
        let success: Bool
        let message: String?
        let id: Int?
    }

    // paginated GET, returns raw rows
    func managementFetchRows(path: String) async -> (rows: [[String: Any]]?, error: String?) {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            return (nil, L10n.string("settings_not_configured"))
        }
        var all: [[String: Any]] = []
        var offset = 0
        let limit = 200
        while true {
            guard var comps = URLComponents(string: "\(baseURL)\(path)") else {
                return (nil, "Invalid URL.")
            }
            comps.queryItems = [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
            guard let url = comps.url else { return (nil, "Invalid URL.") }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let http = response as? HTTPURLResponse else { return (nil, "No response.") }
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                guard Self.isSnipeApiHttpSuccess(http.statusCode) else {
                    return (nil, Self.extractApiErrorMessage(from: json ?? [:]) ?? "HTTP \(http.statusCode)")
                }
                if Self.isSnipeApiErrorResponse(json) {
                    return (nil, Self.extractApiErrorMessage(from: json ?? [:]) ?? "Request failed.")
                }
                guard let json else {
                    return (nil, "Invalid response.")
                }
                let rows = (json["rows"] as? [[String: Any]]) ?? []
                all.append(contentsOf: rows)
                let total = json["total"] as? Int
                if rows.count < limit { break }
                if let total, all.count >= total { break }
                if rows.isEmpty { break }
                offset += limit
                try? await Task.sleep(nanoseconds: 60_000_000)
            } catch {
                return (nil, error.localizedDescription)
            }
        }
        return (all, nil)
    }

    /// GET a single management row (e.g. full status label including color).
    func managementFetchRow(path: String, id: Int) async -> [String: Any]? {
        guard !baseURL.isEmpty, !apiToken.isEmpty,
              let url = URL(string: "\(baseURL)\(path)/\(id)") else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            if let payload = json["payload"], !(payload is NSNull),
               let row = payload as? [String: Any] {
                return row
            }
            if json["id"] as? Int != nil { return json }
            return nil
        } catch {
            return nil
        }
    }

    func managementCreate(path: String, body: [String: Any]) async -> ManagementWriteResult {
        await managementWrite(urlString: "\(baseURL)\(path)", method: "POST", body: body)
    }

    func managementUpdate(path: String, id: Int, body: [String: Any]) async -> ManagementWriteResult {
        await managementWrite(urlString: "\(baseURL)\(path)/\(id)", method: "PATCH", body: body)
    }

    func managementDelete(path: String, id: Int) async -> ManagementWriteResult {
        await managementWrite(urlString: "\(baseURL)\(path)/\(id)", method: "DELETE", body: nil)
    }

    private func managementWrite(urlString: String, method: String, body: [String: Any]?) async -> ManagementWriteResult {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            return ManagementWriteResult(success: false, message: L10n.string("settings_not_configured"), id: nil)
        }
        guard let url = URL(string: urlString) else {
            return ManagementWriteResult(success: false, message: "Invalid URL.", id: nil)
        }

        func makeRequest(method: String, formMethodOverride: String? = nil) -> URLRequest {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let formMethodOverride {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = "_method=\(formMethodOverride)".data(using: .utf8)
            } else if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
            return request
        }

        do {
            var (data, response) = try await urlSession.data(for: makeRequest(method: method))
            var http = response as? HTTPURLResponse

            // Laravel method spoofing: some hosts reject raw DELETE with 405.
            if http?.statusCode == 405, method == "DELETE" {
                (data, response) = try await urlSession.data(for: makeRequest(method: "POST", formMethodOverride: "DELETE"))
                http = response as? HTTPURLResponse
            }

            guard let http else {
                return ManagementWriteResult(success: false, message: "No response.", id: nil)
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard Self.isSnipeApiHttpSuccess(http.statusCode) else {
                let preview = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return ManagementWriteResult(
                    success: false,
                    message: Self.extractApiErrorMessage(from: json ?? [:]) ?? "HTTP \(http.statusCode): \(preview)",
                    id: nil
                )
            }
            if Self.isSnipeApiErrorResponse(json) {
                return ManagementWriteResult(
                    success: false,
                    message: Self.extractApiErrorMessage(from: json ?? [:]) ?? "Request failed.",
                    id: nil
                )
            }
            let newId = (json?["payload"] as? [String: Any])?["id"] as? Int
            let message = Self.extractApiErrorMessage(from: json ?? [:])
            return ManagementWriteResult(success: true, message: message, id: newId)
        } catch {
            return ManagementWriteResult(success: false, message: error.localizedDescription, id: nil)
        }
    }

    // Linked fields for a fieldset; older Snipe-IT builds lack GET /fieldsets/:id/fields.
    func fetchFieldsetLinkedFields(fieldsetId: Int) async -> (rows: [[String: Any]]?, error: String?) {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            return (nil, L10n.string("settings_not_configured"))
        }

        func fieldRows(from json: [String: Any]) -> [[String: Any]]? {
            if let rows = json["rows"] as? [[String: Any]] { return rows }
            if let fields = json["fields"] as? [String: Any],
               let rows = fields["rows"] as? [[String: Any]] { return rows }
            if let payload = json["payload"] as? [String: Any] {
                if let rows = payload["rows"] as? [[String: Any]] { return rows }
                if let fields = payload["fields"] as? [String: Any],
                   let rows = fields["rows"] as? [[String: Any]] { return rows }
            }
            return nil
        }

        func requestJSON(path: String) async throws -> (HTTPURLResponse, [String: Any]) {
            guard let url = URL(string: "\(baseURL)\(path)") else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return (http, json)
        }

        do {
            let (http, json) = try await requestJSON(path: "/api/v1/fieldsets/\(fieldsetId)/fields")
            if (200...299).contains(http.statusCode), let rows = fieldRows(from: json) {
                return (await enrichFieldsetFieldRows(rows), nil)
            }
            if http.statusCode != 404 {
                return (nil, Self.extractApiErrorMessage(from: json) ?? "HTTP \(http.statusCode)")
            }
        } catch {
            return (nil, error.localizedDescription)
        }

        do {
            let (http, json) = try await requestJSON(path: "/api/v1/fieldsets/\(fieldsetId)")
            if (200...299).contains(http.statusCode), let rows = fieldRows(from: json) {
                return (await enrichFieldsetFieldRows(rows), nil)
            }
            if http.statusCode != 404 {
                return (nil, Self.extractApiErrorMessage(from: json) ?? "HTTP \(http.statusCode)")
            }
        } catch {
            return (nil, error.localizedDescription)
        }

        await fetchFieldsets()
        if let cached = fieldsets?.first(where: { $0.id == fieldsetId }) {
            let rows = cached.fields.rows.map { field -> [String: Any] in
                var row: [String: Any] = ["id": field.id, "name": field.name, "type": field.type]
                if let values = field.field_values_array { row["field_values_array"] = values }
                return row
            }
            return (rows, nil)
        }

        return (nil, L10n.string("mgmt_load_failed"))
    }

    func reorderFieldsetFields(fieldsetId: Int, fieldIds: [Int]) async -> ManagementWriteResult {
        await managementCreate(
            path: "/api/v1/fields/fieldsets/\(fieldsetId)/order",
            body: ["item": fieldIds]
        )
    }

    private func enrichFieldsetFieldRows(_ rows: [[String: Any]]) async -> [[String: Any]] {
        guard rows.contains(where: { $0["id"] == nil }) else { return rows }
        let allFields = await managementFetchRows(path: "/api/v1/fields")
        guard let catalog = allFields.rows else { return rows }

        func resolveId(for row: [String: Any]) -> Int? {
            if let id = row["id"] as? Int { return id }
            if let dbColumn = row["db_column_name"] as? String,
               let match = catalog.first(where: { ($0["db_column_name"] as? String) == dbColumn }) {
                return match["id"] as? Int
            }
            if let name = row["name"] as? String,
               let match = catalog.first(where: { ($0["name"] as? String) == name }) {
                return match["id"] as? Int
            }
            return nil
        }

        return rows.compactMap { row in
            guard let id = resolveId(for: row) else { return nil }
            var enriched = row
            enriched["id"] = id
            return enriched
        }
    }
}
