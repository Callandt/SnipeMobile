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
    @State private var showCheckoutSheet: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var checkinTarget: SnipeITAPIClient.AccessoryCheckedOutRow? = nil
    @State private var checkinErrorMessage: String?
    @State private var showCheckinError = false
    @State private var isCheckingIn = false
    @State private var detailImageURL: String? = nil

    /// From apiClient or passed in.
    private var currentAccessory: Accessory {
        apiClient.accessories.first { $0.id == accessory.id } ?? accessory
    }

    private var resolvedImageURL: URL? {
        let rawValue = (detailImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? detailImageURL!
            : (currentAccessory.image?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        guard !rawValue.isEmpty else { return nil }

        if let absolute = URL(string: rawValue), absolute.scheme != nil {
            return absolute
        }
        if rawValue.hasPrefix("/") {
            return URL(string: "\(apiClient.baseURL)\(rawValue)")
        }
        return nil
    }

    /// No stock. Checkout disabled.
    private var canCheckout: Bool {
        guard let remaining = currentAccessory.remaining else { return true }
        return remaining > 0
    }

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
                        if let imageURL = resolvedImageURL {
                            VStack(spacing: 10) {
                                Text(L10n.string("image"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 220)
                                            .frame(maxWidth: .infinity)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    case .failure(_):
                                        Image(systemName: "photo")
                                            .font(.system(size: 36))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, minHeight: 140)
                                    case .empty:
                                        ProgressView()
                                            .frame(maxWidth: .infinity, minHeight: 140)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
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

                        if currentAccessory.qty != nil || currentAccessory.minAmt != nil || currentAccessory.remaining != nil || currentAccessory.checkoutsCount != nil {
                            Text(L10n.string("stock_usage"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            VStack(alignment: .leading, spacing: 10) {
                                if let qty = currentAccessory.qty {
                                    HStack { Text(L10n.string("total_quantity")).foregroundColor(.secondary); Spacer(); Text("\(qty)").bold() }
                                }
                                if let minAmt = currentAccessory.minAmt {
                                    HStack { Text(L10n.string("minimum_amount")).foregroundColor(.secondary); Spacer(); Text("\(minAmt)").bold() }
                                }
                                if let remaining = currentAccessory.remaining {
                                    HStack { Text(L10n.string("remaining")).foregroundColor(.secondary); Spacer(); Text("\(remaining)").bold() }
                                }
                                if let checkouts = currentAccessory.checkoutsCount {
                                    HStack { Text(L10n.string("checkouts_count")).foregroundColor(.secondary); Spacer(); Text("\(checkouts)").bold() }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        // Assigned via checkedout API
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
                Button(action: { showEditSheet = true }) {
                    Label(L10n.string("edit"), systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                if currentAccessory.statusLabel?.statusMeta?.lowercased() == "deployed" {
                    Button(action: {
                        let active = checkedOutRows.filter { $0.availableActions?.checkin == true }
                        if let first = active.first {
                            checkinTarget = first
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
                    Button(action: { showCheckoutSheet = true }) {
                        Label(L10n.string("check_out"), systemImage: "arrow.up.to.line")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .controlSize(.large)
                    .disabled(!canCheckout)
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
                Text(currentAccessory.decodedName)
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
                if let url = URL(string: "\(apiClient.baseURL)/accessories/\(currentAccessory.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear { reloadCheckedOut(clearImageWhenAbsent: false) }
        .onChange(of: accessory.id) { reloadCheckedOut(clearImageWhenAbsent: true) }
        .sheet(isPresented: $showEditSheet) {
            AccessoryEditSheet(apiClient: apiClient, accessory: currentAccessory, isPresented: $showEditSheet, onSuccess: {
                Task { await apiClient.fetchAccessories() }
            })
        }
        .sheet(isPresented: $showCheckoutSheet) {
            AccessoryCheckoutSheet(apiClient: apiClient, accessory: currentAccessory, isPresented: $showCheckoutSheet, onSuccess: {
                Task {
                    checkedOutRows = await apiClient.fetchAccessoryCheckedOutList(accessoryId: accessory.id)
                }
            })
        }
        .confirmationDialog(
            L10n.string("checkin_confirm_title"),
            isPresented: Binding(get: { checkinTarget != nil }, set: { if !$0 { checkinTarget = nil } }),
            titleVisibility: .visible,
            presenting: checkinTarget
        ) { _ in
            Button(L10n.string("check_in"), role: .destructive) {
                Task { await performCheckin() }
            }
            Button(L10n.string("cancel"), role: .cancel) {}
        } message: { row in
            Text(checkinConfirmMessage(for: row))
        }
        .alert(L10n.string("checkin_failed"), isPresented: $showCheckinError) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(checkinErrorMessage ?? "")
        }
        .overlay {
            if isCheckingIn {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func checkinConfirmMessage(for row: SnipeITAPIClient.AccessoryCheckedOutRow) -> String {
        let name = row.assignedTo?.name ?? ""
        if name.isEmpty {
            return L10n.string("checkin_generic_confirm_message")
        }
        return String(format: L10n.string("checkin_user_confirm_message"), name)
    }

    private func performCheckin() async {
        guard let target = checkinTarget else { return }
        checkinTarget = nil
        isCheckingIn = true
        let success = await checkinAccessory(checkedoutId: target.id)
        if !success {
            checkinErrorMessage = L10n.string("checkin_failed")
            showCheckinError = true
        }
        isCheckingIn = false
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(label).bold()
                Spacer(minLength: 8)
                Text(value)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).bold()
                Text(value)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func accessoryInfoRows() -> [AnyView] {
        var rows: [AnyView] = []
        if !currentAccessory.decodedName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("name"), value: currentAccessory.decodedName)))
        }
        if !currentAccessory.decodedAssetTag.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("asset_tag"), value: currentAccessory.decodedAssetTag)))
        }
        if let status = currentAccessory.statusLabel?.statusMeta, !status.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("status"), value: L10n.statusLabel(status))))
        }
        if !currentAccessory.decodedAssignedToName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("assigned_to"), value: currentAccessory.decodedAssignedToName)))
        }
        if !currentAccessory.decodedLocationName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("location"), value: currentAccessory.decodedLocationName)))
        }
        if !currentAccessory.decodedManufacturerName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("manufacturer"), value: currentAccessory.decodedManufacturerName)))
        }
        if !currentAccessory.decodedCategoryName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("category"), value: currentAccessory.decodedCategoryName)))
        }
        return rows
    }

    private var displayedCheckoutRows: [SnipeITAPIClient.AccessoryCheckedOutRow] {
        checkedOutRows.filter { $0.assignedTo?.id != nil }
    }

    private func reloadCheckedOut(clearImageWhenAbsent: Bool) {
        Task {
            isLoading = true
            if apiClient.assets.isEmpty {
                await apiClient.fetchAssets()
            }
            checkedOutRows = await apiClient.fetchAccessoryCheckedOutList(accessoryId: accessory.id)
            if let fullAccessory = await apiClient.fetchAccessoryDetails(accessoryId: accessory.id),
               let image = fullAccessory.image,
               !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailImageURL = image
            } else if clearImageWhenAbsent {
                detailImageURL = nil
            }
            isLoading = false
        }
    }

    private func openAssignee(for row: SnipeITAPIClient.AccessoryCheckedOutRow) {
        guard let assigned = row.assignedTo, let id = assigned.id else {
            checkinTarget = row
            return
        }
        if assigned.isUser, let fullUser = apiClient.users.first(where: { $0.id == id }) {
            onOpenUser?(fullUser)
        } else if assigned.isLocation, let fullLocation = apiClient.locations.first(where: { $0.id == id }) {
            onOpenLocation?(fullLocation)
        } else if assigned.isAsset, let fullAsset = apiClient.assets.first(where: { $0.id == id }) {
            onOpenAsset?(fullAsset)
        } else {
            checkinTarget = row
        }
    }

    @ViewBuilder
    private func checkedOutRowLabel(for row: SnipeITAPIClient.AccessoryCheckedOutRow) -> some View {
        if let assigned = row.assignedTo {
        if assigned.isUser {
            let fullUser = assigned.id.flatMap { id in apiClient.users.first(where: { $0.id == id }) }
            HStack {
                Image(systemName: "person.circle")
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fullUser?.decodedName ?? assigned.decodedName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let email = fullUser?.decodedEmail, !email.isEmpty {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if canNavigateAssignee(assigned) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if assigned.isLocation {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(assigned.decodedName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let note = row.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if canNavigateAssignee(assigned) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else if assigned.isAsset {
            let fullAsset = assigned.id.flatMap { id in apiClient.assets.first(where: { $0.id == id }) }
            let title = fullAsset.map { $0.decodedModelName.isEmpty ? $0.decodedName : $0.decodedModelName }
                ?? (assigned.decodedModel.isEmpty ? assigned.decodedName : assigned.decodedModel)
            let tag = fullAsset?.decodedAssetTag ?? assigned.decodedAssetTag
            let assignee = fullAsset?.decodedAssignedToName ?? ""
            HStack {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? L10n.string("asset") : title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !tag.isEmpty {
                        Text(String(format: L10n.string("tag_label"), tag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !assignee.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "person.circle")
                                .font(.caption)
                            Text(assignee)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if canNavigateAssignee(assigned) {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.tertiary)
                    .frame(width: 30, height: 30)
                Text(assigned.decodedName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        }
    }

    private func canNavigateAssignee(_ assigned: SnipeITAPIClient.AssignedToCheckedOut) -> Bool {
        guard let id = assigned.id else { return false }
        if assigned.isUser { return apiClient.users.contains(where: { $0.id == id }) }
        if assigned.isLocation { return apiClient.locations.contains(where: { $0.id == id }) }
        if assigned.isAsset { return apiClient.assets.contains(where: { $0.id == id }) }
        return false
    }

    // Assigned to user, location, or asset.
    var checkedOutSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L10n.string("assigned_to"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            if isLoading {
                ProgressView(L10n.string("loading_assigned"))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if displayedCheckoutRows.isEmpty {
                Text(L10n.string("assigned_to_none_accessory"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(displayedCheckoutRows) { row in
                    Button(action: { openAssignee(for: row) }) {
                        checkedOutRowLabel(for: row)
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .contextMenu {
                        if row.availableActions?.checkin == true {
                            Button(role: .destructive) {
                                checkinTarget = row
                            } label: {
                                Label(L10n.string("check_in"), systemImage: "arrow.down.to.line")
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // Check-in flow
    private func checkinAccessory(checkedoutId: Int?) async -> Bool {
        guard let checkedoutId = checkedoutId else { return false }
        guard let url = URL(string: "\(apiClient.baseURL)/api/v1/accessories/\(accessory.id)/checkin") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(KeychainSecretStore.string(for: .apiToken))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["checkedout_id": checkedoutId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Refresh list
                checkedOutRows = await apiClient.fetchAccessoryCheckedOutList(accessoryId: accessory.id)
                return true
            }
            return false
        } catch {
            return false
        }
    }
} 

