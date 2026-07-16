import SwiftUI

struct AccessoryDetailView: View {
    let accessory: Accessory
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
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
    @State private var ephemeralNotice: EphemeralNotice?

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

                        if hasPurchaseInfo {
                            Text(L10n.string("purchase_only"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            VStack(alignment: .leading, spacing: 10) {
                                if !currentAccessory.decodedManufacturerName.isEmpty {
                                    detailRow(label: L10n.string("manufacturer"), value: currentAccessory.decodedManufacturerName)
                                }
                                let supplierName = HTMLDecoder.decode(currentAccessory.supplier?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                if !supplierName.isEmpty {
                                    detailRow(label: L10n.string("supplier"), value: supplierName)
                                }
                                if let date = formattedPurchaseDate(currentAccessory.purchaseDate) {
                                    detailRow(label: L10n.string("purchase_date"), value: date)
                                }
                                if let cost = currentAccessory.purchaseCost?.trimmingCharacters(in: .whitespacesAndNewlines), !cost.isEmpty {
                                    detailRow(label: L10n.string("purchase_cost"), value: cost)
                                }
                                if let order = currentAccessory.orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !order.isEmpty {
                                    detailRow(label: L10n.string("order_number"), value: HTMLDecoder.decode(order))
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(currentAccessory.decodedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
                Task { await apiClient.refreshAccessoryInCache(accessoryId: accessory.id) }
            })
        }
        .sheet(isPresented: $showCheckoutSheet) {
            AccessoryCheckoutSheet(apiClient: apiClient, accessory: currentAccessory, isPresented: $showCheckoutSheet, onSuccess: {
                presentEphemeralNotice($ephemeralNotice, L10n.string("checkout_success"))
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
        .ephemeralNotice($ephemeralNotice)
    }

    private func checkinConfirmMessage(for row: SnipeITAPIClient.AccessoryCheckedOutRow) -> String {
        let name = row.assignedTo?.name ?? ""
        if name.isEmpty {
            return L10n.string("checkin_generic_confirm_message")
        }
        return String(format: L10n.string("checkin_user_confirm_message"), name)
    }

    private func performCheckin() async {
        guard let target = checkinTarget, let checkedoutId = target.id else { return }
        checkinTarget = nil
        isCheckingIn = true
        let success = await executeAccessoryCheckin(checkedoutId: checkedoutId)
        if success {
            presentEphemeralNotice($ephemeralNotice, L10n.string("checkin_success"))
        } else {
            checkinErrorMessage = L10n.string("checkin_failed")
            showCheckinError = true
        }
        isCheckingIn = false
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).bold()
            Text(value)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accessoryInfoRows() -> [AnyView] {
        var rows: [AnyView] = []
        if !currentAccessory.decodedName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("name"), value: currentAccessory.decodedName)))
        }
        if !currentAccessory.decodedAssetTag.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("asset_tag"), value: currentAccessory.decodedAssetTag)))
        }
        let modelNumber = HTMLDecoder.decode(currentAccessory.modelNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !modelNumber.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("model_number"), value: modelNumber)))
        }
        if let status = currentAccessory.statusLabel?.statusMeta, !status.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("status"), value: L10n.statusLabel(status))))
        }
        if !currentAccessory.decodedLocationName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("location"), value: currentAccessory.decodedLocationName)))
        }
        if !currentAccessory.decodedCategoryName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("category"), value: currentAccessory.decodedCategoryName)))
        }
        let companyName = HTMLDecoder.decode(currentAccessory.company?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !companyName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("company"), value: companyName)))
        }
        if !currentAccessory.decodedAssignedToName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("assigned_to"), value: currentAccessory.decodedAssignedToName)))
        }
        return rows
    }

    private var hasPurchaseInfo: Bool {
        let hasManufacturer = !currentAccessory.decodedManufacturerName.isEmpty
        let hasSupplier = !(currentAccessory.supplier?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasDate = formattedPurchaseDate(currentAccessory.purchaseDate) != nil
        let hasCost = currentAccessory.purchaseCost?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasOrder = currentAccessory.orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasManufacturer || hasSupplier || hasDate || hasCost || hasOrder
    }

    private func formattedPurchaseDate(_ raw: String?) -> String? {
        guard let parsed = DateInfo.parseAPIDate(raw) else {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = .none
        return output.string(from: parsed)
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
            if let fullAccessory = await apiClient.fetchAccessoryDetails(accessoryId: accessory.id) {
                apiClient.applyUpdatedAccessory(fullAccessory)
                if let image = fullAccessory.image,
                   !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailImageURL = image
                } else if clearImageWhenAbsent {
                    detailImageURL = nil
                }
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
                AssignedUserCard(
                    user: fullUser,
                    fallbackName: assigned.decodedName,
                    fallbackEmail: fullUser?.decodedEmail ?? ""
                )
            } else if assigned.isLocation {
                if let id = assigned.id, let fullLocation = apiClient.locations.first(where: { $0.id == id }) {
                    AssignedLocationCard(location: fullLocation)
                } else {
                    AssignedLocationCard(location: Location(id: assigned.id ?? 0, name: assigned.decodedName))
                }
            } else if assigned.isAsset {
                let fullAsset = assigned.id.flatMap { id in apiClient.assets.first(where: { $0.id == id }) }
                AssignedAssetCard(
                    asset: fullAsset,
                    fallbackTitle: assigned.decodedModel.isEmpty ? assigned.decodedName : assigned.decodedModel,
                    fallbackTag: assigned.decodedAssetTag,
                    fallbackAssignee: fullAsset?.decodedAssignedToName ?? ""
                )
            } else {
                AssignedUserCard(user: nil, fallbackName: assigned.decodedName)
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
                    .contextMenu {
                        if row.availableActions?.checkin == true {
                            Button(role: .destructive) {
                                let target = row
                                DispatchQueue.main.async { checkinTarget = target }
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

    private func executeAccessoryCheckin(checkedoutId: Int) async -> Bool {
        let success = await apiClient.checkinAccessory(accessoryId: accessory.id, checkedoutId: checkedoutId)
        if success {
            checkedOutRows = await apiClient.fetchAccessoryCheckedOutList(accessoryId: accessory.id)
        }
        return success
    }
} 

