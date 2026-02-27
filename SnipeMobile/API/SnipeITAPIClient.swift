import Foundation
import SwiftUI

@MainActor
class SnipeITAPIClient: ObservableObject {
    @Published var assets: [Asset] = []
    @Published var users: [User] = []
    @Published var accessories: [Accessory] = []
    @Published var locations: [Location] = []
    @Published var companies: [Company] = []
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

    init() {
        self.isConfigured = UserDefaults.standard.bool(forKey: "isConfigured")
    }

    func saveConfiguration(baseURL: String, apiToken: String) {
        let normalizedBaseURL = normalizeBaseURL(baseURL)
        UserDefaults.standard.set(normalizedBaseURL, forKey: "baseURL")
        UserDefaults.standard.set(apiToken, forKey: "apiToken")
        self.isConfigured = true
        
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

        await MainActor.run {
            isLoading = false
        }

        Task(priority: .background) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.fetchUsers() }
                group.addTask { await self.fetchAccessories() }
                group.addTask { await self.fetchLocations() }
                group.addTask { await self.fetchCompanies() }
                group.addTask { await self.fetchStatusLabels() }
            }
        }
    }

    func fetchAssets() async {
        // Annuleer een bestaande fetch
        fetchAssetsTask?.cancel()

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
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                print("START fetchAssets")
                let (data, _) = try await URLSession.shared.data(for: request)
                print("SUCCESS fetchAssets")
                let response = try JSONDecoder().decode(AssetResponse.self, from: data)
                await MainActor.run {
                    self.assets = response.rows
                }
            } catch {
                if (error as? URLError)?.code == .cancelled {
                    print("Fetch cancelled, no error shown to user.")
                } else {
                    await MainActor.run {
                        self.errorMessage = "Error fetching assets: \(error.localizedDescription)"
                        print("Error details: \(error)")
                    }
                }
            }
        }
        await fetchAssetsTask?.value
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
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(UserResponse.self, from: data)
            await MainActor.run {
                self.users = response.rows.sorted { $0.name < $1.name }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching users: \(error.localizedDescription)"
                print("Error details: \(error)")
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
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AccessoriesResponse.self, from: data)
            await MainActor.run {
                self.accessories = response.rows
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching accessories: \(error.localizedDescription)"
                print("Error details: \(error)")
            }
        }
    }

    func fetchLocations() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else {
            // No error message needed for background fetch
            return
        }

        guard let url = URL(string: "\(baseURL)/api/v1/locations") else {
            print("Invalid URL for locations")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(LocationsResponse.self, from: data)
            await MainActor.run {
                self.locations = response.rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
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
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(CompaniesResponse.self, from: data)
            await MainActor.run {
                self.companies = response.rows.sorted { $0.name.lowercased() < $1.name.lowercased() }
            }
        } catch {
            print("Error fetching companies: \(error.localizedDescription)")
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
            let (data, _) = try await URLSession.shared.data(for: request)
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
            let (_, response) = try await URLSession.shared.data(for: request)
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
            let (data, response) = try await URLSession.shared.data(for: request)
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
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(ActivityResponse.self, from: data)
                allActivities.append(contentsOf: response.rows)
                if response.rows.count < limit {
                    break // laatste batch
                }
                offset += limit
            } catch {
                print("Error fetching activity report: \(error.localizedDescription)")
                break
            }
        }
        return allActivities
    }

    /// Fetch activity for a specific item type (e.g., "asset", "accessory", "user") and item id using the filtered API endpoint
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
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ActivityResponse.self, from: data)
            return response.rows
        } catch {
            print("Error fetching filtered activity report: \(error.localizedDescription)")
            return []
        }
    }

    /// Download een bestand via een geauthenticeerde request en sla het tijdelijk op
    func downloadFile(from url: String) async -> URL? {
        guard let fileUrl = URL(string: url), !apiToken.isEmpty else { return nil }
        var request = URLRequest(url: fileUrl)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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

    /// Haal de geaccepteerde EULAs van een gebruiker op via de API
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
            let (data, _) = try await URLSession.shared.data(for: request)
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
            // Fallback: probeer te decoderen als array van ActivityFile
            if let files = try? JSONDecoder().decode([ActivityFile].self, from: data) {
                return files
            }
        } catch {
            print("Error fetching user EULAs: \(error)")
        }
        return []
    }

    // MARK: - Asset Update
    struct AssetUpdateRequest: Codable {
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
        let next_audit_date: String?
        let expected_checkin: String?
        let eol_date: String?
    }

    // MARK: - Models (voor Create Asset)
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
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
            await MainActor.run { self.models = response.rows }
        } catch {
            print("Error fetching models: \(error)")
        }
    }

    // MARK: - Fieldsets (model -> custom fields)
    func fetchFieldsets() async {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return }
        guard let url = URL(string: "\(baseURL)/api/v1/fieldsets") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
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

    // MARK: - Create Asset (POST /hardware)
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
        do {
            let data = try JSONEncoder().encode(body)
            request.httpBody = data
            let (responseData, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Asset created!" : "Create failed.")
                await MainActor.run { self.lastApiMessage = msg }
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                       let payload = json["payload"],
                       let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                       let newAsset = try? JSONDecoder().decode(Asset.self, from: payloadData) {
                        await MainActor.run { self.assets.insert(newAsset, at: 0) }
                    }
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

    // MARK: - Categories (voor Create Accessory)
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
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(CategoriesResponse.self, from: data)
            await MainActor.run { self.categories = response.rows }
        } catch {
            print("Error fetching categories: \(error)")
        }
    }

    // MARK: - Create Accessory (POST /accessories)
    func createAccessory(name: String, categoryId: Int, quantity: Int, customFields: [String: String]?) async -> Bool {
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
        if let cf = customFields, !cf.isEmpty {
            body["custom_fields"] = cf
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Accessory created!" : "Create failed.")
                await MainActor.run { self.lastApiMessage = msg }
                if httpResponse.statusCode == 200, let payload = json, let row = payload["payload"] as? [String: Any], row["id"] != nil {
                    // Eenvoudige accessory voor lijst: we herladen accessoires
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

    func updateAsset(assetId: Int, update: AssetUpdateRequest) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/hardware/\(assetId)") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let body = try JSONEncoder().encode(update)
            request.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let msg = (json?["messages"] as? [String: Any])?.values.first as? String
                    ?? json?["error"] as? String
                    ?? (httpResponse.statusCode == 200 ? "Changes saved!" : "Save failed.")
                await MainActor.run { self.lastApiMessage = msg }
                if httpResponse.statusCode == 200 {
                    if let updatedAsset = try? JSONDecoder().decode(Asset.self, from: data) {
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

    // MARK: - Field Definitions
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
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rows = json["rows"] as? [[String: Any]] {
                let decoder = JSONDecoder()
                let fieldData = try JSONSerialization.data(withJSONObject: rows)
                let fields = try decoder.decode([FieldDefinition].self, from: fieldData)
                await MainActor.run {
                    self.fieldDefinitions = fields
                    print("DEBUG: fetchFieldDefinitions count=\(fields.count)")
                    for f in fields {
                        print("DEBUG: FieldDef name=\(f.name), type=\(f.type ?? "") field_values_array=\(f.field_values_array?.joined(separator: ", ") ?? "")")
                    }
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
            let (data, _) = try await URLSession.shared.data(for: request)
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
            let (data, _) = try await URLSession.shared.data(for: request)
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
        /// Some Snipe IT versions return "models" as a direct array.
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
        // Voeg hier andere properties toe indien nodig
    }

    @MainActor
    @Published var fieldsets: [Fieldset]? = nil

    /// Returns custom field definitions for the given model from fieldsets (fallback when GET /models/:id/fields is empty or unavailable).
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
            let (_, response) = try await URLSession.shared.data(for: request)
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
            let (data, response) = try await URLSession.shared.data(for: request)
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

    func validateApiCredentials() async -> String? {
        guard !baseURL.isEmpty, !apiToken.isEmpty else { return "Please enter both API URL and API Key." }
        guard let url = URL(string: "\(baseURL)/api/v1/users") else { return "Invalid URL format." }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
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
            let (data, _) = try await URLSession.shared.data(for: request)
            print("DEBUG checkedout API response: ", String(data: data, encoding: .utf8) ?? "nil")
            do {
                let decoded = try JSONDecoder().decode(AccessoryCheckedOutResponse.self, from: data)
                print("DEBUG decoded checkedout rows: ", decoded.rows)
                return decoded.rows
            } catch {
                print("DECODE ERROR: \(error)")
            }
        } catch {
            print("Error fetching checked out list: \(error)")
        }
        return []
    }
} 