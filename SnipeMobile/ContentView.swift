import SwiftUI
import AVFoundation
import CodeScanner

struct ContentView: View {
    @StateObject private var apiClient = SnipeITAPIClient()
    @State private var showingScanner = false
    @State private var scannedAssetId: Int?
    @State private var selectedCategory: String = "Hardware"
    @State private var showingSettings = false
    @State private var searchText: String = ""
    @State private var navigationPath = NavigationPath()
    @State private var isRefreshing: Bool = false
    @State private var hasLoadedInitialAssets: Bool = false

    let categories = ["Hardware", "Accessories", "Users", "Locations"]

    var filteredAssets: [Asset] {
        if searchText.isEmpty {
            return apiClient.assets
        } else {
            return apiClient.assets.filter { asset in
                asset.decodedName.lowercased().contains(searchText.lowercased()) ||
                asset.decodedModelName.lowercased().contains(searchText.lowercased()) ||
                asset.decodedAssetTag.lowercased().contains(searchText.lowercased()) ||
                asset.decodedLocationName.lowercased().contains(searchText.lowercased()) ||
                asset.decodedAssignedToName.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var filteredUsers: [User] {
        if searchText.isEmpty {
            return apiClient.users
        } else {
            return apiClient.users.filter { user in
                user.decodedName.lowercased().contains(searchText.lowercased()) ||
                user.decodedFirstName.lowercased().contains(searchText.lowercased()) ||
                user.decodedEmail.lowercased().contains(searchText.lowercased()) ||
                user.decodedLocationName.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var filteredAccessories: [Accessory] {
        if searchText.isEmpty {
            return apiClient.accessories
        } else {
            return apiClient.accessories.filter { accessory in
                accessory.decodedName.lowercased().contains(searchText.lowercased()) ||
                accessory.decodedAssetTag.lowercased().contains(searchText.lowercased()) ||
                accessory.decodedLocationName.lowercased().contains(searchText.lowercased()) ||
                accessory.decodedAssignedToName.lowercased().contains(searchText.lowercased()) ||
                accessory.decodedManufacturerName.lowercased().contains(searchText.lowercased()) ||
                accessory.decodedCategoryName.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var filteredLocations: [Location] {
        if searchText.isEmpty {
            return apiClient.locations
        } else {
            return apiClient.locations.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
    }

    var body: some View {
        if apiClient.isConfigured {
            NavigationStack(path: $navigationPath) {
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        categoryNavigationBar
                        statisticsView
                        searchBar
                        assetListView
                        scanQRButton
                    }
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("SnipeMobile")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .padding(.top, 20)
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingSettings = true
                            }) {
                                Image(systemName: "gearshape")
                                    .foregroundColor(.primary)
                                    .padding(.top, 20)
                            }
                        }
                    }
                    .navigationDestination(for: Asset.self) { asset in
                        AssetDetailView(asset: asset, apiClient: apiClient)
                    }
                    .navigationDestination(for: User.self) { user in
                        UserDetailView(user: user, apiClient: apiClient)
                    }
                    .navigationDestination(for: Location.self) { location in
                        LocationDetailView(location: location, apiClient: apiClient)
                    }
                    .navigationDestination(for: Accessory.self) { accessory in
                        AccessoryDetailView(accessory: accessory, apiClient: apiClient)
                    }
                }
                .onChange(of: selectedCategory) {
                    searchText = ""
                }
            }
            .sheet(isPresented: $showingScanner) {
                CodeScannerView(codeTypes: [.qr], completion: { result in
                    showingScanner = false
                    switch result {
                    case .success(let scanResult):
                        print("QR code scanned: \(scanResult.string)")
                        if let url = URL(string: scanResult.string),
                           let id = extractAssetId(from: url) {
                            scannedAssetId = id
                            apiClient.errorMessage = nil
                            print("Extracted asset ID: \(id)")
                            if let asset = apiClient.assets.first(where: { $0.id == id }) {
                                print("Navigating to asset with ID: \(asset.id)")
                                navigationPath.append(asset)
                                selectedCategory = "Hardware"
                            } else {
                                apiClient.errorMessage = "Asset with ID \(id) not found."
                                print("Asset not found for ID: \(id)")
                            }
                        } else {
                            apiClient.errorMessage = "Invalid QR code: no valid asset ID"
                            print("Invalid QR code format")
                        }
                    case .failure(let error):
                        apiClient.errorMessage = "Scan failed: \(error.localizedDescription)"
                        print("Scan error: \(error.localizedDescription)")
                    }
                })
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(apiClient: apiClient)
            }
            .onAppear {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    Task { @MainActor in
                        if !granted {
                            apiClient.errorMessage = "Camera access is required for QR scanning."
                        }
                    }
                }
                if !hasLoadedInitialAssets {
                    Task {
                        await apiClient.fetchPrimaryThenBackground()
                        hasLoadedInitialAssets = true
                    }
                }
            }
        } else {
            ConfigView(apiClient: apiClient)
        }
    }

    private var categoryNavigationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.self) { category in
                    Button(action: {
                        selectedCategory = category
                    }) {
                        Text(category)
                            .font(.caption)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(selectedCategory == category ? Color.blue : Color(.systemGray4))
                            .foregroundColor(selectedCategory == category ? .white : .primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
        .background(Color(.systemBackground))
    }

    private var statisticsView: some View {
        Group {
            if selectedCategory == "Hardware" {
                HStack {
                    Text("\(apiClient.assets.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("total assets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(apiClient.assets.filter { $0.assignedTo != nil }.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("assigned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .frame(maxWidth: .infinity)
            } else if selectedCategory == "Users" {
                HStack {
                    Text("\(apiClient.users.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("total users")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .frame(maxWidth: .infinity)
            } else if selectedCategory == "Accessories" {
                HStack {
                    Text("\(apiClient.accessories.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("total accessories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .frame(maxWidth: .infinity)
            } else if selectedCategory == "Locations" {
                HStack {
                    Text("\(apiClient.locations.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("total locations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var searchBar: some View {
        TextField("Search", text: $searchText)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding(.horizontal)
            .padding(.vertical, 5)
            .foregroundColor(.primary)
            .background(Color(.systemBackground))
    }

    private var assetListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if apiClient.isLoading && !isRefreshing {
                    if selectedCategory == "Hardware" {
                        ProgressView("Loading assets...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedCategory == "Users" {
                        ProgressView("Loading users...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedCategory == "Accessories" {
                        ProgressView("Loading accessories...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if selectedCategory == "Locations" {
                        ProgressView("Loading locations...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if let error = apiClient.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else if selectedCategory == "Hardware" {
                    ForEach(filteredAssets) { asset in
                        NavigationLink(value: asset) {
                            AssetCardView(asset: asset)
                        }
                    }
                } else if selectedCategory == "Users" {
                    ForEach(filteredUsers) { user in
                        NavigationLink(value: user) {
                            UserCardView(user: user)
                        }
                    }
                } else if selectedCategory == "Accessories" {
                    ForEach(filteredAccessories) { accessory in
                        NavigationLink(value: accessory) {
                            AccessoryCardView(accessory: accessory)
                        }
                    }
                } else if selectedCategory == "Locations" {
                    ForEach(filteredLocations) { location in
                        NavigationLink(value: location) {
                            LocationCardView(location: location)
                        }
                    }
                }
            }
        }
        .refreshable {
            isRefreshing = true
            await apiClient.fetchPrimaryThenBackground()
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s delay voor UI sync
            isRefreshing = false
        }
    }

    private var scanQRButton: some View {
        Button(action: { showingScanner = true }) {
            HStack {
                Image(systemName: "qrcode.viewfinder")
                Text("Scan QR Code")
            }
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
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
