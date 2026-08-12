import Foundation

extension SnipeITAPIClient {
    struct AuthorizedProbeResult {
        let statusCode: Int
        let data: Data
        let ok: Bool
    }

    /// Authenticated GET probe.
    func authorizedProbe(path: String, queryItems: [URLQueryItem] = []) async -> AuthorizedProbeResult? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return nil }
        guard var components = URLComponents(string: "\(baseURL)\(path)") else { return nil }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            return AuthorizedProbeResult(
                statusCode: http.statusCode,
                data: data,
                ok: (200...299).contains(http.statusCode)
            )
        } catch {
            return nil
        }
    }

    /// Detect admin vs user; reports progress via `onProgress`.
    @discardableResult
    func detectAppMode(
        onProgress: (@MainActor (AppModeCheckProgress) -> Void)? = nil
    ) async -> AppModeCheckProgress {
        var progress = AppModeCheckProgress()

        func publish() async {
            let snapshot = progress
            if let onProgress {
                await MainActor.run { onProgress(snapshot) }
            }
        }

        // 1) Connection — current user
        progress.connection = .running
        await publish()

        guard let meProbe = await authorizedProbe(path: "/api/v1/users/me") else {
            progress.connection = .failure(L10n.string("api_validate_connect_failed"))
            await publish()
            return progress
        }

        guard meProbe.ok, let user = Self.decodeUser(from: meProbe.data) else {
            let message: String
            if meProbe.statusCode == 401 || meProbe.statusCode == 403 {
                message = Self.localizedHTTPFailureMessage(statusCode: meProbe.statusCode)
            } else {
                message = Self.localizedHTTPFailureMessage(statusCode: meProbe.statusCode)
            }
            progress.connection = .failure(message)
            await publish()
            return progress
        }

        await MainActor.run {
            self.currentUser = user
        }
        progress.connection = .success
        await publish()

        // 2) Rights — admin flags, else hardware probe
        progress.rights = .running
        await publish()

        let permissionHintsIsAdmin = Self.adminPermissionHints(from: meProbe.data)
        let hardwareProbe = await authorizedProbe(
            path: "/api/v1/hardware",
            queryItems: [URLQueryItem(name: "limit", value: "1")]
        )

        let isAdmin: Bool
        if permissionHintsIsAdmin {
            isAdmin = true
        } else if let hardwareProbe, hardwareProbe.ok {
            isAdmin = true
        } else {
            isAdmin = false
        }

        let mode: AppMode = isAdmin ? .admin : .user
        progress.detectedMode = mode
        progress.rights = .success
        await publish()

        // Requestable check happens later in user mode.
        await MainActor.run {
            AppModeStore.applyDetection(detectedMode: mode, canRequestAssets: AppModeStore.canRequestAssets)
        }

        return progress
    }

    /// Sync for the active app mode.
    func syncForCurrentAppMode() async {
        switch AppModeStore.current {
        case .user:
            await fetchUserModeData()
            WidgetSnapshotBuilder.publishAdminOnly(baseURL: baseURL, isConfigured: isConfigured)
        case .admin, .none:
            await fetchPrimaryThenBackground()
        }
    }

    /// Load current user and assigned items.
    func fetchUserModeData(clearRefreshError: Bool = false) async {
        isLoading = true
        errorMessage = nil
        if clearRefreshError {
            refreshErrorMessage = nil
        }

        await fetchCurrentUser(reportErrors: true)
        if refreshErrorMessage != nil || pendingUnauthorizedSessionWipe {
            isLoading = false
            hasCompletedInitialLoad = true
            return
        }

        if let id = currentUser?.id {
            async let mine = fetchUserAssets(userId: id, reportErrors: true)
            async let accessories = fetchUserAccessories(userId: id, reportErrors: false)
            async let licenses = fetchUserLicenses(userId: id, reportErrors: false)
            let (myAssets, myAccessories, myLicenses) = await (mine, accessories, licenses)
            await MainActor.run {
                self.assets = myAssets
                self.accessories = myAccessories
                self.licenses = myLicenses
            }
        } else if isConfigured {
            // Empty `/users/me` without error → connection failure.
            reportRefreshError(L10n.string("api_validate_connect_failed"))
        }

        isLoading = false
        hasCompletedInitialLoad = true
    }

    func fetchRequestableAssets(reportErrors: Bool = false) async -> [Asset] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            if reportErrors {
                reportRefreshError(L10n.string("api_validate_missing"))
            }
            return []
        }
        do {
            // Requestable hardware list.
            return try await fetchAllPaginated(
                path: "/api/v1/account/requestable/hardware",
                as: Asset.self,
                reportConnectionError: false
            ) ?? []
        } catch {
            if reportErrors {
                reportRefreshError(Self.localizedConnectionFailureMessage(from: error))
            }
            return []
        }
    }

    func fetchMyAssetRequests() async -> [Asset] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        do {
            return try await fetchAllPaginated(
                path: "/api/v1/account/requests",
                as: Asset.self
            ) ?? []
        } catch {
            return []
        }
    }

    /// Request an asset for the current user.
    func requestAsset(assetId: Int) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            return L10n.string("api_validate_missing")
        }
        guard let url = URL(string: "\(baseURL)/api/v1/account/request/\(assetId)") else {
            return L10n.string("api_validate_invalid_url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return L10n.string("api_validate_connect_failed")
            }
            if (200...299).contains(http.statusCode) {
                return nil
            }
            if let message = Self.parseSnipeErrorMessage(from: data) {
                return message
            }
            return Self.localizedHTTPFailureMessage(statusCode: http.statusCode)
        } catch {
            return Self.localizedConnectionFailureMessage(from: error)
        }
    }

    func cancelAssetRequest(assetId: Int) async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            return L10n.string("api_validate_missing")
        }
        guard let url = URL(string: "\(baseURL)/api/v1/account/request/\(assetId)/cancel") else {
            return L10n.string("api_validate_invalid_url")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return L10n.string("api_validate_connect_failed")
            }
            if (200...299).contains(http.statusCode) {
                return nil
            }
            if let message = Self.parseSnipeErrorMessage(from: data) {
                return message
            }
            return Self.localizedHTTPFailureMessage(statusCode: http.statusCode)
        } catch {
            return Self.localizedConnectionFailureMessage(from: error)
        }
    }

    private static func adminPermissionHints(from data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let root = (json["payload"] as? [String: Any]) ?? json
        let permissions = root["permissions"] as? [String: Any] ?? [:]

        func isGranted(_ key: String) -> Bool {
            guard let value = permissions[key] else { return false }
            if let number = value as? NSNumber { return number.intValue == 1 }
            if let string = value as? String { return string == "1" || string.lowercased() == "true" }
            if let bool = value as? Bool { return bool }
            return false
        }

        return isGranted("superuser") || isGranted("admin")
    }

    private static func parseSnipeErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let messages = json["messages"] as? String, !messages.isEmpty {
            return messages
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        return nil
    }
}
