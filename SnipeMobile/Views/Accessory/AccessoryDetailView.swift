import SwiftUI

struct AccessoryDetailView: View {
    let accessory: Accessory
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @State private var checkedOutRows: [SnipeITAPIClient.AccessoryCheckedOutRow] = []
    @State private var isLoading = true
    @State private var showCheckinSheet: Bool = false
    @State private var checkinTarget: SnipeITAPIClient.AccessoryCheckedOutRow? = nil
    @State private var checkinResult: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Picker("Details", selection: $selectedTab) {
                Text("Details").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            if selectedTab == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Accessory Info")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(Array(accessoryInfoRows().enumerated()), id: \ .offset) { _, row in
                                row
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        if accessory.qty != nil || accessory.minAmt != nil || accessory.remaining != nil || accessory.checkoutsCount != nil {
                            Text("Stock & Usage")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            VStack(alignment: .leading, spacing: 10) {
                                if let qty = accessory.qty {
                                    HStack { Text("Total Quantity").foregroundColor(.secondary); Spacer(); Text("\(qty)").bold() }
                                }
                                if let minAmt = accessory.minAmt {
                                    HStack { Text("Minimum Amount").foregroundColor(.secondary); Spacer(); Text("\(minAmt)").bold() }
                                }
                                if let remaining = accessory.remaining {
                                    HStack { Text("Remaining").foregroundColor(.secondary); Spacer(); Text("\(remaining)").bold() }
                                }
                                if let checkouts = accessory.checkoutsCount {
                                    HStack { Text("Checkouts Count").foregroundColor(.secondary); Spacer(); Text("\(checkouts)").bold() }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // --- Assigned Users/Locations via checkedout API ---
                        checkedOutSection
                        Spacer()
                    }
                    .padding(.top)
                }
            } else {
                HistoryView(itemType: "accessory", itemId: accessory.id, apiClient: apiClient)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(action: {}) {
                    Text("Edit")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button(action: {}) {
                    Text((accessory.statusLabel?.statusMeta?.lowercased() == "deployed") ? "Check In" : "Check Out")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background((accessory.statusLabel?.statusMeta?.lowercased() == "deployed") ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(Color.white.ignoresSafeArea(edges: .bottom))
        }
        .navigationTitle(accessory.decodedName)
        .navigationBarTitleDisplayMode(.inline)
        .padding(.top, 8)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/accessories/\(accessory.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear {
            Task {
                isLoading = true
                checkedOutRows = await apiClient.fetchAccessoryCheckedOutList(accessoryId: accessory.id)
                isLoading = false
            }
        }
        .onChange(of: accessory.id) {
            Task {
                isLoading = true
                checkedOutRows = await apiClient.fetchAccessoryCheckedOutList(accessoryId: accessory.id)
                isLoading = false
            }
        }
        .sheet(isPresented: $showCheckinSheet) {
            VStack(spacing: 24) {
                Text("Check In Accessory")
                    .font(.title2).bold()
                    .padding(.top, 24)
                if let target = checkinTarget {
                    Text("Do you want to check in this accessory from \(target.assignedTo?.name ?? "")?")
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 20) {
                    Button("Cancel") { showCheckinSheet = false }
                        .foregroundColor(.secondary)
                    Button("Check In") {
                        Task {
                            let success = await checkinAccessory(checkedoutId: checkinTarget?.id)
                            checkinResult = success ? "Accessory checked in!" : "Check-in failed."
                            showCheckinSheet = false
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .cornerRadius(8)
                }
                if let result = checkinResult {
                    Text(result)
                        .foregroundColor(result.contains("failed") ? .red : .green)
                        .padding(.top, 8)
                }
                Spacer()
            }
            .padding()
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).bold()
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    private func accessoryInfoRows() -> [AnyView] {
        var rows: [AnyView] = []
        if !accessory.decodedName.isEmpty {
            rows.append(AnyView(detailRow(label: "Name", value: accessory.decodedName)))
        }
        if !accessory.decodedAssetTag.isEmpty {
            rows.append(AnyView(detailRow(label: "Asset Tag", value: accessory.decodedAssetTag)))
        }
        if let status = accessory.statusLabel?.statusMeta, !status.isEmpty {
            rows.append(AnyView(detailRow(label: "Status", value: status)))
        }
        if !accessory.decodedAssignedToName.isEmpty {
            rows.append(AnyView(detailRow(label: "Assigned To", value: accessory.decodedAssignedToName)))
        }
        if !accessory.decodedLocationName.isEmpty {
            rows.append(AnyView(detailRow(label: "Location", value: accessory.decodedLocationName)))
        }
        if !accessory.decodedManufacturerName.isEmpty {
            rows.append(AnyView(detailRow(label: "Manufacturer", value: accessory.decodedManufacturerName)))
        }
        if !accessory.decodedCategoryName.isEmpty {
            rows.append(AnyView(detailRow(label: "Category", value: accessory.decodedCategoryName)))
        }
        return rows
    }

    // --- Nieuwe checkedout section ---
    var checkedOutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assigned To")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            if isLoading {
                ProgressView("Loading assigned...")
                    .frame(maxWidth: .infinity)
            } else {
                let activeRows = checkedOutRows.filter { $0.availableActions?.checkin == true }
                if activeRows.isEmpty {
                    Text("Not assigned to any user or location.")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    ForEach(activeRows) { row in
                        Button(action: {
                            checkinTarget = row
                            showCheckinSheet = true
                        }) {
                            if row.assignedTo?.type == "user",
                               let assigned = row.assignedTo,
                               let id = assigned.id,
                               let name = assigned.name,
                               let firstName = assigned.firstName {
                                let user = User(
                                    id: id,
                                    name: name,
                                    first_name: firstName,
                                    email: assigned.username, // username als email niet beschikbaar
                                    location: nil,
                                    employeeNumber: nil,
                                    jobtitle: nil
                                )
                                UserCardView(user: user)
                            } else if row.assignedTo?.type == "location" {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.gray)
                                        .frame(width: 30, height: 30)
                                    VStack(alignment: .leading) {
                                        Text(row.assignedTo?.name ?? "")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        if let note = row.note, !note.isEmpty {
                                            Text(note)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Nieuwe checkin functie ---
    private func checkinAccessory(checkedoutId: Int?) async -> Bool {
        guard let checkedoutId = checkedoutId else { return false }
        guard let url = URL(string: "\(apiClient.baseURL)/api/v1/accessories/\(accessory.id)/checkin") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(UserDefaults.standard.string(forKey: "apiToken") ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["checkedout_id": checkedoutId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Refresh checkedout list na checkin
                checkedOutRows = await apiClient.fetchAccessoryCheckedOutList(accessoryId: accessory.id)
                return true
            }
            return false
        } catch {
            return false
        }
    }
} 

