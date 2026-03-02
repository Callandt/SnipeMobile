import SwiftUI

struct AccessoryDetailView: View {
    let accessory: Accessory
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil
    var onOpenLocation: ((Location) -> Void)? = nil
    @State private var checkedOutRows: [SnipeITAPIClient.AccessoryCheckedOutRow] = []
    @State private var isLoading = true
    @State private var showCheckinSheet: Bool = false
    @State private var checkinTarget: SnipeITAPIClient.AccessoryCheckedOutRow? = nil
    @State private var checkinResult: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Picker("Details", selection: $selectedTab) {
                Text(L10n.string("details")).tag(0)
                Text(L10n.string("history")).tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 2)

            if selectedTab == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(L10n.string("accessory_info"))
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
                            Text(L10n.string("stock_usage"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            VStack(alignment: .leading, spacing: 10) {
                                if let qty = accessory.qty {
                                    HStack { Text(L10n.string("total_quantity")).foregroundColor(.secondary); Spacer(); Text("\(qty)").bold() }
                                }
                                if let minAmt = accessory.minAmt {
                                    HStack { Text(L10n.string("minimum_amount")).foregroundColor(.secondary); Spacer(); Text("\(minAmt)").bold() }
                                }
                                if let remaining = accessory.remaining {
                                    HStack { Text(L10n.string("remaining")).foregroundColor(.secondary); Spacer(); Text("\(remaining)").bold() }
                                }
                                if let checkouts = accessory.checkoutsCount {
                                    HStack { Text(L10n.string("checkouts_count")).foregroundColor(.secondary); Spacer(); Text("\(checkouts)").bold() }
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
                    .padding(.top, 16)
                }
            } else {
                HistoryView(itemType: "accessory", itemId: accessory.id, apiClient: apiClient)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button(action: {}) {
                    Label(L10n.string("edit"), systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                if accessory.statusLabel?.statusMeta?.lowercased() == "deployed" {
                    Button(action: {
                        let active = checkedOutRows.filter { $0.availableActions?.checkin == true }
                        if let first = active.first {
                            checkinTarget = first
                            showCheckinSheet = true
                        }
                    }) {
                        Label(L10n.string("check_in"), systemImage: "arrow.down.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                } else {
                    Button(action: {}) {
                        Label(L10n.string("check_out"), systemImage: "arrow.up.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .background(Color(.systemBackground))
        .onAppear { isDetailViewActive = true }
        .onDisappear { isDetailViewActive = false }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(returnToTab != nil)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(accessory.decodedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let _ = returnToTab, let onBack = onBackToPrevious {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        onBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
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
            rows.append(AnyView(detailRow(label: L10n.string("name"), value: accessory.decodedName)))
        }
        if !accessory.decodedAssetTag.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("asset_tag"), value: accessory.decodedAssetTag)))
        }
        if let status = accessory.statusLabel?.statusMeta, !status.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("status"), value: L10n.statusLabel(status))))
        }
        if !accessory.decodedAssignedToName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("assigned_to"), value: accessory.decodedAssignedToName)))
        }
        if !accessory.decodedLocationName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("location"), value: accessory.decodedLocationName)))
        }
        if !accessory.decodedManufacturerName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("manufacturer"), value: accessory.decodedManufacturerName)))
        }
        if !accessory.decodedCategoryName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("category"), value: accessory.decodedCategoryName)))
        }
        return rows
    }

    // --- Assigned To: zelfde opmaak als Hardware (grijze kaarten, Bewerken/Check in-out stijl) ---
    var checkedOutSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L10n.string("assigned_to"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            if isLoading {
                ProgressView(L10n.string("loading_assigned"))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let activeRows = checkedOutRows.filter { $0.availableActions?.checkin == true }
                if activeRows.isEmpty {
                    Text(L10n.string("assigned_to_any"))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(activeRows) { row in
                        Button(action: {
                            if row.assignedTo?.type == "user", let id = row.assignedTo?.id,
                               let fullUser = apiClient.users.first(where: { $0.id == id }) {
                                onOpenUser?(fullUser)
                            } else if row.assignedTo?.type == "location", let id = row.assignedTo?.id,
                                      let fullLocation = apiClient.locations.first(where: { $0.id == id }) {
                                onOpenLocation?(fullLocation)
                            } else {
                                checkinTarget = row
                                showCheckinSheet = true
                            }
                        }) {
                            if row.assignedTo?.type == "user",
                               let assigned = row.assignedTo,
                               let id = assigned.id,
                               assigned.name != nil,
                               assigned.firstName != nil,
                               let fullUser = apiClient.users.first(where: { $0.id == id }) {
                                HStack {
                                    Image(systemName: "person.circle")
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fullUser.decodedName)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if !fullUser.decodedEmail.isEmpty {
                                            Text(fullUser.decodedEmail)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        if !fullUser.decodedLocationName.isEmpty {
                                            Text(fullUser.decodedLocationName)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            } else if row.assignedTo?.type == "location" {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.assignedTo?.name ?? "")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if let note = row.note, !note.isEmpty {
                                            Text(note)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .contextMenu {
                            Button(L10n.string("check_in")) {
                                checkinTarget = row
                                showCheckinSheet = true
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
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

