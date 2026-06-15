import SwiftUI

struct ConsumableDetailView: View {
    let consumable: Consumable
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var onOpenUser: ((User) -> Void)? = nil

    @State private var checkedOutRows: [SnipeITAPIClient.ConsumableUserRow] = []
    @State private var isLoading = true
    @State private var showCheckoutSheet: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var detailImageURL: String? = nil
    @State private var ephemeralNotice: EphemeralNotice?

    private var currentConsumable: Consumable {
        apiClient.consumables.first { $0.id == consumable.id } ?? consumable
    }

    private var resolvedImageURL: URL? {
        let rawValue = (detailImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? detailImageURL!
            : (currentConsumable.image?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
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
        guard let remaining = currentConsumable.remaining else { return true }
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

                        Text(L10n.string("consumable_info"))
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

                        if currentConsumable.qty != nil || currentConsumable.minAmt != nil || currentConsumable.remaining != nil {
                            Text(L10n.string("stock_usage"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            VStack(alignment: .leading, spacing: 10) {
                                if let qty = currentConsumable.qty {
                                    HStack { Text(L10n.string("total_quantity")).foregroundColor(.secondary); Spacer(); Text("\(qty)").bold() }
                                }
                                if let minAmt = currentConsumable.minAmt {
                                    HStack { Text(L10n.string("minimum_amount")).foregroundColor(.secondary); Spacer(); Text("\(minAmt)").bold() }
                                }
                                if let remaining = currentConsumable.remaining {
                                    HStack { Text(L10n.string("remaining")).foregroundColor(.secondary); Spacer(); Text("\(remaining)").bold().foregroundColor(remaining <= 0 ? .red : .primary) }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }

                        if let notes = currentConsumable.notes, !notes.isEmpty {
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
                HistoryView(itemType: "consumable", itemId: consumable.id, apiClient: apiClient)
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(currentConsumable.decodedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if let url = URL(string: "\(apiClient.baseURL)/consumables/\(currentConsumable.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: consumable.id) { reload() }
        .sheet(isPresented: $showEditSheet) {
            ConsumableEditSheet(apiClient: apiClient, consumable: currentConsumable, isPresented: $showEditSheet, onSuccess: {
                Task { await apiClient.fetchConsumables() }
            })
        }
        .sheet(isPresented: $showCheckoutSheet) {
            ConsumableCheckoutSheet(apiClient: apiClient, consumable: currentConsumable, isPresented: $showCheckoutSheet, onSuccess: {
                presentEphemeralNotice($ephemeralNotice, L10n.string("checkout_success"))
                Task {
                    checkedOutRows = await apiClient.fetchConsumableCheckedOutList(consumableId: consumable.id)
                }
            })
        }
        .ephemeralNotice($ephemeralNotice)
    }

    private func reload() {
        Task {
            isLoading = true
            checkedOutRows = await apiClient.fetchConsumableCheckedOutList(consumableId: consumable.id)
            if let full = await apiClient.fetchConsumableDetails(consumableId: consumable.id),
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label).bold()
            Text(value)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRows() -> [AnyView] {
        var rows: [AnyView] = []
        if !currentConsumable.decodedName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("name"), value: currentConsumable.decodedName)))
        }
        if !currentConsumable.decodedItemNo.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("item_no"), value: currentConsumable.decodedItemNo)))
        }
        if !currentConsumable.decodedModelNumber.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("model_number"), value: currentConsumable.decodedModelNumber)))
        }
        if !currentConsumable.decodedCategoryName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("category"), value: currentConsumable.decodedCategoryName)))
        }
        if !currentConsumable.decodedManufacturerName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("manufacturer"), value: currentConsumable.decodedManufacturerName)))
        }
        if !currentConsumable.decodedLocationName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("location"), value: currentConsumable.decodedLocationName)))
        }
        if !currentConsumable.decodedCompanyName.isEmpty {
            rows.append(AnyView(detailRow(label: L10n.string("company"), value: currentConsumable.decodedCompanyName)))
        }
        if let order = currentConsumable.orderNumber, !order.isEmpty {
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
                Text(L10n.string("assigned_to_none_consumable"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(checkedOutRows) { row in
                    let fullUser = row.userId.flatMap { id in apiClient.users.first(where: { $0.id == id }) }
                    Button(action: {
                        if let fullUser { onOpenUser?(fullUser) }
                    }) {
                        AssignedUserCard(
                            user: fullUser,
                            fallbackName: HTMLDecoder.decode(row.name ?? ""),
                            fallbackEmail: fullUser?.decodedEmail ?? row.email ?? ""
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(fullUser == nil)
                }
            }
        }
        .padding(.horizontal)
    }
}
