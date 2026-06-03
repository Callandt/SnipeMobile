import SwiftUI

struct ComponentDetailView: View {
    let component: Component
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil

    @State private var checkedOutRows: [SnipeITAPIClient.ComponentAssetRow] = []
    @State private var isLoading = true
    @State private var showCheckoutSheet: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var detailImageURL: String? = nil
    @State private var ephemeralNotice: EphemeralNotice?
    @State private var checkinTarget: SnipeITAPIClient.ComponentAssetRow?
    @State private var checkinErrorMessage: String?
    @State private var showCheckinError = false
    @State private var isCheckingIn = false

    private var currentComponent: Component {
        apiClient.components.first { $0.id == component.id } ?? component
    }

    private var resolvedImageURL: URL? {
        let rawValue = (detailImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? detailImageURL!
            : (currentComponent.image?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        guard !rawValue.isEmpty else { return nil }

        if let absolute = URL(string: rawValue), absolute.scheme != nil {
            return absolute
        }
        if rawValue.hasPrefix("/") {
            return URL(string: "\(apiClient.baseURL)\(rawValue)")
        }
        return nil
    }

    private var canCheckout: Bool {
        guard let remaining = currentComponent.remaining else { return true }
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

                        Text(L10n.string("component_info"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(Array(infoRows().enumerated()), id: \.offset) { _, row in
                                row
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        if currentComponent.qty != nil || currentComponent.minAmt != nil || currentComponent.remaining != nil {
                            Text(L10n.string("stock_usage"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            VStack(alignment: .leading, spacing: 10) {
                                if let qty = currentComponent.qty {
                                    HStack { Text(L10n.string("total_quantity")).foregroundColor(.secondary); Spacer(); Text("\(qty)").bold() }
                                }
                                if let minAmt = currentComponent.minAmt {
                                    HStack { Text(L10n.string("minimum_amount")).foregroundColor(.secondary); Spacer(); Text("\(minAmt)").bold() }
                                }
                                if let remaining = currentComponent.remaining {
                                    HStack { Text(L10n.string("remaining")).foregroundColor(.secondary); Spacer(); Text("\(remaining)").bold().foregroundColor(remaining <= 0 ? .red : .primary) }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if let notes = currentComponent.notes, !notes.isEmpty {
                            Text(L10n.string("notes"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text(notes)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                                .padding(.horizontal)
                        }

                        checkedOutSection
                        Spacer()
                    }
                    .padding(.top, 16)
                }
            } else {
                HistoryView(itemType: "component", itemId: component.id, apiClient: apiClient)
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
                Text(currentComponent.decodedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: 200)
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
                if let url = URL(string: "\(apiClient.baseURL)/components/\(currentComponent.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: component.id) { reload() }
        .sheet(isPresented: $showEditSheet) {
            ComponentEditSheet(apiClient: apiClient, component: currentComponent, isPresented: $showEditSheet, onSuccess: {
                Task { await apiClient.fetchComponents() }
            })
        }
        .sheet(isPresented: $showCheckoutSheet) {
            ComponentCheckoutSheet(apiClient: apiClient, component: currentComponent, isPresented: $showCheckoutSheet, onSuccess: {
                presentEphemeralNotice($ephemeralNotice, L10n.string("checkout_success"))
                Task {
                    checkedOutRows = await apiClient.fetchComponentAssetsList(componentId: component.id)
                }
            })
        }
        .confirmationDialog(
            L10n.string("checkin_confirm_title"),
            isPresented: Binding(get: { checkinTarget != nil }, set: { if !$0 { checkinTarget = nil } }),
            titleVisibility: .visible,
            presenting: checkinTarget
        ) { row in
            Button(L10n.string("check_in"), role: .destructive) {
                Task { await performCheckin(row: row) }
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

    private func checkinConfirmMessage(for row: SnipeITAPIClient.ComponentAssetRow) -> String {
        let name = HTMLDecoder.decode(row.assetName ?? "")
        if name.isEmpty {
            return L10n.string("checkin_generic_confirm_message")
        }
        return String(format: L10n.string("checkin_user_confirm_message"), name)
    }

    private func requestCheckin(for row: SnipeITAPIClient.ComponentAssetRow) {
        DispatchQueue.main.async { checkinTarget = row }
    }

    private func performCheckin(row: SnipeITAPIClient.ComponentAssetRow) async {
        checkinTarget = nil
        guard let pivotId = row.assignedPivotId else {
            checkinErrorMessage = L10n.string("checkin_failed")
            showCheckinError = true
            return
        }
        isCheckingIn = true
        defer { isCheckingIn = false }

        let error = await apiClient.checkinComponent(
            componentId: component.id,
            componentAssetId: pivotId,
            quantity: row.assignedQty ?? 1
        )
        if let error {
            checkinErrorMessage = error
            showCheckinError = true
            return
        }
        presentEphemeralNotice($ephemeralNotice, L10n.string("checkin_success"))
        try? await Task.sleep(nanoseconds: 350_000_000)
        checkedOutRows = await apiClient.fetchComponentAssetsList(componentId: component.id)
    }

    private func reload() {
        Task {
            isLoading = true
            checkedOutRows = await apiClient.fetchComponentAssetsList(componentId: component.id)
            if let full = await apiClient.fetchComponentDetails(componentId: component.id),
               let image = full.image,
               !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                detailImageURL = image
            } else {
                detailImageURL = nil
            }
            isLoading = false
        }
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

    private func infoRows() -> [AnyView] {
        var rows: [AnyView] = []
        if !currentComponent.decodedName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("name"), value: currentComponent.decodedName)))
        }
        if !currentComponent.decodedSerial.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("serial"), value: currentComponent.decodedSerial)))
        }
        if !currentComponent.decodedModelNumber.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("model_number"), value: currentComponent.decodedModelNumber)))
        }
        if !currentComponent.decodedCategoryName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("category"), value: currentComponent.decodedCategoryName)))
        }
        if !currentComponent.decodedManufacturerName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("manufacturer"), value: currentComponent.decodedManufacturerName)))
        }
        if !currentComponent.decodedLocationName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("location"), value: currentComponent.decodedLocationName)))
        }
        if !currentComponent.decodedCompanyName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("company"), value: currentComponent.decodedCompanyName)))
        }
        if let order = currentComponent.orderNumber, !order.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("order_number"), value: order)))
        }
        return rows
    }

    var checkedOutSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L10n.string("checked_out_to"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            if isLoading {
                ProgressView(L10n.string("loading_assigned"))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if checkedOutRows.isEmpty {
                Text(L10n.string("assigned_to_none_component"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(checkedOutRows) { row in
                    let fullAsset = row.assetId.flatMap { id in apiClient.assets.first(where: { $0.id == id }) }
                    Button(action: {
                        if let fullAsset { onOpenAsset?(fullAsset) }
                    }) {
                        AssignedAssetCard(
                            asset: fullAsset,
                            fallbackTitle: HTMLDecoder.decode(row.assetName ?? ""),
                            fallbackTag: HTMLDecoder.decode(row.assetTag ?? ""),
                            quantity: row.assignedQty
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(fullAsset == nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        if row.assignedPivotId != nil {
                            Button(role: .destructive) {
                                requestCheckin(for: row)
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
}
