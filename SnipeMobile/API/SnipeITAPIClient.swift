import Foundation
import SwiftUI

#if !DEBUG
private func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

@MainActor
class SnipeITAPIClient: ObservableObject {
    @Published var assets: [Asset] = []
    @Published var users: [User] = []
    @Published var accessories: [Accessory] = []
    @Published var locations: [Location] = []
    @Published var companies: [Company] = []
    @Published var manufacturers: [Manufacturer] = []
    @Published var suppliers: [Supplier] = []
    @Published var errorMessage: String?
    @Published var lastApiMessage: String?
    @Published var isConfigured: Bool {
        didSet {
            UserDefaults.standard.set(isConfigured, forKey: "isConfigured")
        }
    }
    @Published var isLoading: Bool = false
    @Published var statusLabels: [StatusLabel] = []

    var baseURL: String {
        normalizeBaseURL(UserDefaults.standard.string(forKey: "baseURL") ?? "")
    }
    private var apiToken: String {
        UserDefaults.standard.string(forKey: "apiToken") ?? ""
    }

    private var fetchAssetsTask: Task<Void, Never>? = nil
    private var fetchAssetsGeneration: Int = 0

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    init() {
        self.isConfigured = UserDefaults.standard.bool(forKey: "isConfigured")
        NotificationCenter.default.addObserver(forName: .cloudSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let newValue = UserDefaults.standard.bool(forKey: "isConfigured")
                if self.isConfigured != newValue {
                    self.isConfigured = newValue
                }
            }
        }
    }

    func saveConfiguration(baseURL: String, apiToken: String) {
        let normalizedBaseURL = normalizeBaseURL(baseURL)
        UserDefaults.standard.set(normalizedBaseURL, forKey: "baseURL")
        UserDefaults.standard.set(apiToken, forKey: "apiToken")
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

    func fetchPrimaryThenBackground() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        await fetchAssets()
        await fetchUsers()
        await fetchAccessories()
        await fetchLocations()

        await MainActor.run {
            isLoading = false
        }

        Task(priority: .background) {
            await self.fetchCompanies()
            await self.fetchStatusLabels()
        }
    }

    func fetchAssets() async {
        fetchAssetsGeneration += 1
        let myGen = fetchAssetsGeneration

        fetchAssetsTask = Task {
            guard !baseURL.isEmpty, !apiToken.isEmpty else {
                await MainActor.run { errorMessage = "Configure the API settings first." }
                return
            }

            guard let url = URL(string: "\(baseURL)/api/v1/hardware?limit=500") else {
                await MainActor.run { errorMessage = "Invalid URL" }
                return
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, _) = try await urlSession.data(for: request)
                let response = try JSONDecoder().decode(AssetResponse.self, from: data)
                await MainActor.run {
                    if myGen == self.fetchAssetsGeneration {
                        self.assets = response.rows
                    }
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

    func fetchUsers() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            await MainActor.run { errorMessage = "Configure the API settings first." }
            return
        }

        guard let url = URL(string: "\(baseURL)/api/v1/users") else {
            await MainActor.run { errorMessage = "Invalid URL" }
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(UserResponse.self, from: data)
            await MainActor.run {
                self.users = response.rows.sorted { $0.name < $1.name }
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

    func fetchAccessories() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            await MainActor.run { errorMessage = "Configure the API settings first." }
            return
        }

        guard let url = URL(string: "\(baseURL)/api/v1/accessories") else {
            await MainActor.run { errorMessage = "Invalid URL" }
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(AccessoriesResponse.self, from: data)
            await MainActor.run {
                self.accessories = response.rows
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

    func fetchLocations() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            // No error message needed for background fetch
            return
        }

        guard let url = URL(string: "\(baseURL)/api/v1/locations") else {
            #if DEBUG
            print("Invalid URL for locations")
            #endif
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(LocationsResponse.self, from: data)
            await MainActor.run {
                self.locations = response.rows.sorted { $0.decodedName.lowercased() < $1.decodedName.lowercased() }
            }
        } catch {
            print("Error fetching locations: \(error.localizedDescription)")
        }
    }

    func fetchCompanies() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/companies?limit=500") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(CompaniesResponse.self, from: data)
            await MainActor.run {
                self.companies = response.rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching companies: \(error.localizedDescription)")
        }
    }

    func fetchManufacturers() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/manufacturers?limit=500") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(ManufacturersResponse.self, from: data)
            await MainActor.run {
                self.manufacturers = response.rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching manufacturers: \(error.localizedDescription)")
        }
    }

    func fetchSuppliers() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/suppliers?limit=500") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(SuppliersResponse.self, from: data)
            await MainActor.run {
                self.suppliers = response.rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching suppliers: \(error.localizedDescription)")
        }
    }

    func fetchUsersForAccessory(accessoryId: Int) async -> [User] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/api/v1/accessories/\(accessoryId)/checkedout") else {
            print("Invalid URL for accessory users")
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(UserResponse.self, from: data)
            return response.rows
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
            let (_, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Check-out successful!" : "Check-out failed.")
                await MainActor.run { self.lastApiMessage = msg }
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error checking out: \(error.localizedDescription)"
            }
            return false
        }
    }

    func fetchActivityReport() async -> [Activity] {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return [] }
        var allActivities: [Activity] = []
        var offset = 0
        let limit = 1000
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

    func downloadFile(from url: String) async -> URL? {
        guard let fileUrl = URL(string: url), !apiToken.isEmpty else { return nil }
        var request = URLRequest(url: fileUrl)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Download failed: status code \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return nil
            }
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = fileUrl.lastPathComponent
            let localUrl = tempDir.appendingPathComponent(UUID().uuidString + "_" + fileName)
            try data.write(to: localUrl)
            return localUrl
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

        let name: String?
        let asset_tag: String?
        let serial: String?
        let model_id: Int?
        let status_id: Int?
        let category_id: Int?
        let manufacturer_id: Int?
        let supplier_id: Int?
        let notes: String?
        let order_number: String?
        let location_id: Int?
        let purchase_cost: String?
        let book_value: String?
        let custom_fields: [String: String]?
        let purchase_date: String?
        let next_audit_date: NullableString?
        let expected_checkin: String?
        let eol_date: String?
    }

    // MARK: - Models
    struct ModelRow: Codable, Identifiable {
        let id: Int
        let name: String
    }
    struct ModelsResponse: Codable {
        let rows: [ModelRow]
    }
    @Published var models: [ModelRow] = []

    func fetchModels() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/models?limit=500") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
            await MainActor.run { self.models = response.rows }
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
        func allMessages(from dict: Dict?) -> [String] {
            guard let dict = dict else { return [] }
            var list: [String] = []
            for (_, val) in dict {
                if let arr = val as? [String] {
                    list.append(contentsOf: arr.filter { !$0.isEmpty })
                } else if let s = val as? String, !s.isEmpty {
                    list.append(s)
                }
            }
            return list
        }
        func hasSerialOrAssetTagError(_ dict: Dict?) -> Bool {
            guard let dict = dict else { return false }
            return dict["serial"] != nil || dict["asset_tag"] != nil
        }
        let errors = json?["errors"] as? Dict
        let messagesDict = json?["messages"] as? Dict
        let messagesList = allMessages(from: errors) + allMessages(from: messagesDict)
        let combined = messagesList.isEmpty
            ? (json?["error"] as? String ?? (statusCode == 200 ? "Asset created!" : "Create failed."))
            : messagesList.joined(separator: "\n")
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

    func createAsset(_ body: AssetCreateRequest) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let data = try JSONEncoder().encode(body)
            request.httpBody = data
            #if DEBUG
            print("createAsset: POST \(url.absoluteString)")
            #endif
            let (responseData, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run { self.lastApiMessage = "Geen geldige HTTP-response." }
                return false
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

            // HTML instead of JSON? Login page or redirect.
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
                return false
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
                let isSnipeSuccess = (json?["status"] as? String)?.lowercased() == "success"
                let hasPayload = (json?["payload"] as? [String: Any])?["id"] != nil

                if isSnipeSuccess || hasPayload {
                    // Decode payload into cache if possible
                    if let json = json,
                       let payload = json["payload"],
                       let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                       let newAsset = try? JSONDecoder().decode(Asset.self, from: payloadData) {
                        await MainActor.run { self.assets.insert(newAsset, at: 0) }
                    } else {
                        await self.fetchAssets()
                    }
                    if let messages = json?["messages"] as? String, !messages.isEmpty {
                        await MainActor.run { self.lastApiMessage = messages }
                    }
                    return true
                }
            }

            return false
        } catch {
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
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
        guard let url = URL(string: "\(baseURL)/api/v1/categories?limit=500") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(CategoriesResponse.self, from: data)
            await MainActor.run { self.categories = response.rows }
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
        if let min = minAmt, min > 0 {
            body["min_amt"] = min
        }
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
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Accessory created!" : "Create failed.")
                await MainActor.run { self.lastApiMessage = msg }
                if httpResponse.statusCode == 200, let payload = json, let row = payload["payload"] as? [String: Any], row["id"] != nil {
                    // Reload accessories
                    Task { await self.fetchAccessories() }
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
        var body: [String: Any] = [
            "name": name,
            "category_id": categoryId,
            "qty": quantity
        ]
        if let min = minAmt {
            body["min_amt"] = min
        }
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Saved." : "Save failed.")
                await MainActor.run { self.lastApiMessage = msg }
                if httpResponse.statusCode == 200 {
                    Task { await self.fetchAccessories() }
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
            let msg = (json?["messages"] as? String)
                ?? (json?["messages"] as? [String: Any]).flatMap { $0.values.first as? String }
                ?? json?["error"] as? String
                ?? (httpResponse.statusCode == 200 ? "Asset verwijderd." : "Verwijderen mislukt.")
            await MainActor.run { self.lastApiMessage = msg }
            if httpResponse.statusCode == 200 {
                await MainActor.run {
                    self.assets.removeAll { $0.id == assetId }
                }
                #if DEBUG
                print("[SnipeMobile] DELETE /hardware/\(assetId) — succes, uit cache verwijderd")
                #endif
                return true
            }
            return false
        } catch {
            #if DEBUG
            print("[SnipeMobile] DELETE /hardware/\(assetId) error: \(error)")
            #endif
            await MainActor.run { self.lastApiMessage = "Error: \(error.localizedDescription)" }
            return false
        }
    }

    func updateAsset(assetId: Int, update: AssetUpdateRequest) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let body = try JSONEncoder().encode(update)
            request.httpBody = body
            #if DEBUG
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                print("[SnipeMobile] PATCH /hardware/\(assetId) body: \(json)")
            } else if let raw = String(data: body, encoding: .utf8) {
                print("[SnipeMobile] PATCH /hardware/\(assetId) body (raw): \(raw)")
            }
            #endif
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                #if DEBUG
                let status = httpResponse.statusCode
                let responseStr = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
                print("[SnipeMobile] PATCH /hardware/\(assetId) status: \(status) response: \(responseStr.prefix(500))")
                #endif
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Changes saved!" : "Save failed.")
                await MainActor.run { self.lastApiMessage = msg }
                if httpResponse.statusCode == 200 {
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let payload = json?["payload"]
                    let payloadData = payload.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                    if let payloadData = payloadData,
                       let updatedAsset = try? JSONDecoder().decode(Asset.self, from: payloadData) {
                        await MainActor.run {
                            if let idx = self.assets.firstIndex(where: { $0.id == updatedAsset.id }) {
                                self.assets[idx] = updatedAsset
                            }
                        }
                    } else if let updatedAsset = try? JSONDecoder().decode(Asset.self, from: data) {
                        await MainActor.run {
                            if let idx = self.assets.firstIndex(where: { $0.id == updatedAsset.id }) {
                                self.assets[idx] = updatedAsset
                            }
                        }
                    }
                    return true
                }
                return false
            }
            return false
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error updating asset: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - Field defs
    struct FieldDefinition: Codable, Identifiable, Equatable {
        let id: Int
        let name: String
        let type: String?
        let field_values_array: [String]?
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case type
            case field_values_array
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

    struct StatusLabelResponse: Codable {
        let rows: [StatusLabel]
    }

    func fetchStatusLabels() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/statuslabels") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            let response = try JSONDecoder().decode(StatusLabelResponse.self, from: data)
            await MainActor.run {
                self.statusLabels = response.rows
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
            FieldDefinition(id: f.id, name: f.name, type: f.type, field_values_array: f.field_values_array)
        }
    }

    func checkinAsset(assetId: Int) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)/checkin") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
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
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Check-in successful!" : "Check-in failed.")
                await MainActor.run { self.lastApiMessage = msg }
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error checking in: \(error.localizedDescription)"
            }
            return false
        }
    }

    func checkoutAccessoryCustom(accessoryId: Int, body: [String: Any]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/accessories/\(accessoryId)/checkout") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Check-out successful." : "Check-out failed.")
                await MainActor.run { self.lastApiMessage = msg }
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            await MainActor.run {
                self.lastApiMessage = "Error checking out accessory: \(error.localizedDescription)"
            }
            return false
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
        let createdBy: CreatedByCheckedOut?
        let createdAt: DateInfoCheckedOut?
        let deletedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, image, type, name
            case firstName = "first_name"
            case lastName = "last_name"
            case username
            case createdBy = "created_by"
            case createdAt = "created_at"
            case deletedAt = "deleted_at"
        }
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
        guard let url = URL(string: "\(baseURL)/api/v1/accessories/\(accessoryId)/checkedout") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await urlSession.data(for: request)
            do {
                let decoded = try JSONDecoder().decode(AccessoryCheckedOutResponse.self, from: data)
                return decoded.rows
            } catch {
                #if DEBUG
                print("fetchAccessoryCheckedOutList decode error: \(error)")
                #endif
            }
        } catch {
            print("Error fetching checked out list: \(error)")
        }
        return []
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
} 