import Foundation
import SwiftUI

@MainActor
class SnipeITAPIClient: ObservableObject {
    @Published var assets: [Asset] = []
    @Published var users: [User] = []
    @Published var accessories: [Accessory] = []
    @Published var locations: [Location] = []
    @Published var errorMessage: String?
    @Published var isConfigured: Bool {
        didSet {
            UserDefaults.standard.set(isConfigured, forKey: "isConfigured")
        }
    }
    @Published var isLoading: Bool = false
    @Published var statusLabels: [StatusLabel] = []

    var baseURL: String {
        UserDefaults.standard.string(forKey: "baseURL") ?? ""
    }
    private var apiToken: String {
        UserDefaults.standard.string(forKey: "apiToken") ?? ""
    }

    private var fetchAssetsTask: Task<Void, Never>? = nil

    init() {
        self.isConfigured = UserDefaults.standard.bool(forKey: "isConfigured")
    }

    func saveConfiguration(baseURL: String, apiToken: String) {
        UserDefaults.standard.set(baseURL, forKey: "baseURL")
        UserDefaults.standard.set(apiToken, forKey: "apiToken")
        self.isConfigured = true
        
        Task {
            await fetchPrimaryThenBackground()
        }
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
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Parse updated asset and update in self.assets
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
        } catch {
            await MainActor.run {
                self.errorMessage = "Error updating asset: \(error.localizedDescription)"
            }
            return false
        }
    }

    // MARK: - Field Definitions
    struct FieldDefinition: Codable, Identifiable {
        let id: Int
        let name: String
        let element: String?
        let options: [String]?
        
        enum CodingKeys: String, CodingKey {
            case id
            case name
            case element
            case options
            case choices
            case values
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            element = try? container.decodeIfPresent(String.self, forKey: .element)
            // Try all possible keys for options
            if let opts = try? container.decodeIfPresent([String].self, forKey: .options) {
                options = opts
            } else if let opts = try? container.decodeIfPresent([String].self, forKey: .choices) {
                options = opts
            } else if let opts = try? container.decodeIfPresent([String].self, forKey: .values) {
                options = opts
            } else {
                options = nil
            }
        }
        func encode(to encoder: Encoder) throws {}
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
                    self.modelFieldDefinitions = fields
                }
            }
        } catch {
            print("Error fetching model field definitions: \(error)")
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
        struct FieldsetFields: Codable {
            let rows: [FieldsetField]
        }
        struct FieldsetModels: Codable {
            let rows: [Model]
            struct Model: Codable {
                let id: Int
                let name: String
            }
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
} 