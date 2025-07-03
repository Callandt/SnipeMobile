import SwiftUI

struct AssetCheckinSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    @Binding var isPresented: Bool

    @State private var notes: String = ""
    @State private var isSaving: Bool = false
    @State private var showResult: Bool = false
    @State private var resultMessage: String = ""
    @State private var selectedStatusId: Int? = nil
    @State private var name: String = ""
    @State private var selectedLocationId: Int? = nil

    var sortedLocations: [Location] {
        apiClient.locations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 28) {
                        Text("Check In Asset")
                            .font(.title2).bold()
                            .padding(.top, 24)
                        
                        VStack(alignment: .leading) {
                            Text("Asset details")
                                .font(.headline)
                                .foregroundColor(Color.primary)
                                .padding(.horizontal, 18)
                                .padding(.top, 12)
                            
                            VStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Status")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Picker("Status", selection: $selectedStatusId) {
                                        ForEach(apiClient.statusLabels.sorted(by: { ($0.statusMeta ?? "") < ($1.statusMeta ?? "") }), id: \.id) { status in
                                            Text(status.statusMeta ?? "").tag(Optional(status.id))
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .padding(.vertical, 8)
                                    .padding(.horizontal)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("Name (custom asset name)", text: $name)
                                        .padding(12)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(12)
                                        .foregroundColor(Color.primary)
                                        .frame(maxWidth: .infinity)
                                    Text("This will be shown as the asset name in the system. Leave unchanged to keep the current name.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 2)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Notes")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    TextEditor(text: $notes)
                                        .frame(minHeight: 60)
                                        .padding(8)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(12)
                                        .foregroundColor(Color.primary)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Location")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    HStack {
                                        Picker(selectedLocationId == nil ? "Select Location" : (apiClient.locations.first(where: { $0.id == selectedLocationId })?.name ?? "Location"), selection: $selectedLocationId) {
                                            Text("None").tag(nil as Int?)
                                            ForEach(sortedLocations, id: \.id) { loc in
                                                Text(loc.name).tag(Optional(loc.id))
                                            }
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .padding(.vertical, 8)
                                        .padding(.horizontal)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(10)
                                        
                                        if selectedLocationId != nil {
                                            Button(action: { selectedLocationId = nil }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.leading, 4)
                                            .transition(.scale.combined(with: .opacity))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            
                            Spacer(minLength: 20)
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.07), radius: 8, x: 0, y: 4)
                        .padding(.horizontal, 10)
                        
                        Spacer()
                        
                        Button(action: {
                            isSaving = true
                            Task {
                                var body: [String: Any] = [:]
                                if let statusId = selectedStatusId { body["status_id"] = statusId }
                                if !name.isEmpty, name != asset.name { body["name"] = name }
                                if !notes.isEmpty { body["note"] = notes }
                                if let locationId = selectedLocationId { body["location_id"] = locationId }
                                let success = await apiClient.checkinAssetCustom(assetId: asset.id, body: body)
                                isSaving = false
                                resultMessage = apiClient.lastApiMessage ?? (success ? "Check-in successful!" : "Check-in failed.")
                                showResult = true
                                if success { isPresented = false }
                            }
                        }) {
                            Text("Check In")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isSaving)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                    }
                    .padding(.top, 10)
                }
            }
            .onAppear {
                self.name = asset.name
                if self.selectedStatusId == nil {
                    if let readyToDeploy = apiClient.statusLabels.first(where: { $0.statusMeta?.lowercased() == "deployable" }) {
                        self.selectedStatusId = readyToDeploy.id
                    } else if let firstDeployable = apiClient.statusLabels.first(where: { $0.statusMeta?.lowercased() == "deployable" }) {
                        self.selectedStatusId = firstDeployable.id
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .alert(isPresented: $showResult) {
                Alert(title: Text("Result"), message: Text(resultMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
} 
