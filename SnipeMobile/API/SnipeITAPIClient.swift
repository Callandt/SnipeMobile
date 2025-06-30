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

    var baseURL: String {
        UserDefaults.standard.string(forKey: "baseURL") ?? ""
    }
    private var apiToken: String {
        UserDefaults.standard.string(forKey: "apiToken") ?? ""
    }

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
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AssetResponse.self, from: data)
            await MainActor.run {
                self.assets = response.rows
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error fetching assets: \(error.localizedDescription)"
                print("Error details: \(error)")
            }
        }
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
} 