import SwiftUI

struct LicenseDetailView: View {
    let license: License
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var selectedTab: Int
    @Binding var isDetailViewActive: Bool
    var returnToTab: MainTab? = nil
    var onBackToPrevious: (() -> Void)? = nil
    var onOpenUser: ((User) -> Void)? = nil
    var onOpenAsset: ((Asset) -> Void)? = nil

    @State private var seats: [SnipeITAPIClient.LicenseSeatRow] = []
    @State private var isLoading = true
    @State private var fullLicense: License? = nil
    @State private var showProductKey = false
    @State private var checkinTarget: SnipeITAPIClient.LicenseSeatRow?
    @State private var checkinErrorMessage: String?
    @State private var showCheckinError = false
    @State private var isCheckingIn = false
    @State private var showEditSheet = false
    @State private var showCheckoutSheet = false
    @State private var copyNotification: String?
    @State private var showCopyNotification = false

    private var canCheckout: Bool {
        let free = currentLicense.freeSeatsCount ?? currentLicense.remaining ?? 0
        return free > 0
    }

    private var currentLicense: License {
        fullLicense ?? apiClient.licenses.first { $0.id == license.id } ?? license
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
                        if showCopyNotification, let text = copyNotification {
                            Text(L10n.string("copied", text))
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(8)
                                .transition(.opacity)
                        }
                        Text(L10n.string("license_info"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(Array(licenseInfoRows().enumerated()), id: \.offset) { _, row in
                                row
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        productKeySection
                        seatsSummarySection
                        assignedSeatsSection
                        Spacer()
                    }
                    .padding(.top, 16)
                }
            } else {
                HistoryView(itemType: "license", itemId: license.id, apiClient: apiClient)
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
        .sheet(isPresented: $showEditSheet) {
            LicenseEditSheet(
                apiClient: apiClient,
                license: currentLicense,
                isPresented: $showEditSheet,
                onSuccess: {
                    Task { await loadDetail() }
                }
            )
        }
        .sheet(isPresented: $showCheckoutSheet) {
            LicenseCheckoutSheet(
                apiClient: apiClient,
                license: currentLicense,
                availableSeats: seats,
                isPresented: $showCheckoutSheet,
                onSuccess: {
                    Task { await loadDetail() }
                }
            )
        }
        .onAppear { isDetailViewActive = true }
        .onDisappear { isDetailViewActive = false }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(returnToTab != nil)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(currentLicense.decodedName)
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
                if let url = URL(string: "\(apiClient.baseURL)/licenses/\(currentLicense.id)") {
                    Link(destination: url) {
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .task(id: license.id) {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoading = true
        if let detailed = await apiClient.fetchLicenseDetails(licenseId: license.id) {
            fullLicense = detailed
        }
        seats = await apiClient.fetchLicenseSeats(licenseId: license.id)
        isLoading = false
    }

    @ViewBuilder
    private var productKeySection: some View {
        let key = currentLicense.decodedProductKey
        if !key.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.string("product_key"))
                        .font(.headline)
                    Spacer()
                    Button {
                        showProductKey.toggle()
                    } label: {
                        Image(systemName: showProductKey ? "eye.slash" : "eye")
                    }
                    if showProductKey {
                        Button {
                            copy(value: key, label: L10n.string("product_key"))
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
                Text(showProductKey ? key : String(repeating: "•", count: max(8, min(key.count, 24))))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var seatsSummarySection: some View {
        let total = currentLicense.seats
        let free = currentLicense.freeSeatsCount ?? currentLicense.remaining
        if total != nil || free != nil || currentLicense.minAmt != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("seats"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                if let total {
                    HStack { Text(L10n.string("license_seats_total_label")).foregroundColor(.secondary); Spacer(); Text("\(total)").bold() }
                }
                if let free {
                    HStack { Text(L10n.string("license_seats_free")).foregroundColor(.secondary); Spacer(); Text("\(free)").bold() }
                }
                if let total, let free {
                    let assigned = seats.filter { $0.assignedUser != nil || $0.assignedAsset != nil }.count
                    HStack { Text(L10n.string("license_seats_assigned")).foregroundColor(.secondary); Spacer(); Text("\(assigned)").bold() }
                    let used = max(0, total - free)
                    ProgressView(value: Double(used), total: Double(max(total, 1)))
                        .tint(used >= total ? .red : .accentColor)
                }
                if let minAmt = currentLicense.minAmt {
                    HStack { Text(L10n.string("minimum_amount")).foregroundColor(.secondary); Spacer(); Text("\(minAmt)").bold() }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    private var assignedSeatsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L10n.string("seats"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
            if isLoading {
                ProgressView(L10n.string("loading_assigned"))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if seats.isEmpty {
                Text(L10n.string("assigned_to_any"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let groups = categorizedSeats()
                if !groups.assigned.isEmpty {
                    seatGroupHeader(
                        title: L10n.string("license_seats_assigned"),
                        count: groups.assigned.count,
                        color: .blue
                    )
                    ForEach(groups.assigned) { seat in
                        seatCard(seat, kind: .assigned)
                    }
                }
                if !groups.free.isEmpty {
                    seatGroupHeader(
                        title: L10n.string("license_seats_free"),
                        count: groups.free.count,
                        color: .green
                    )
                    ForEach(groups.free) { seat in
                        seatCard(seat, kind: .free)
                    }
                }
                if !groups.consumed.isEmpty {
                    seatGroupHeader(
                        title: L10n.string("license_seats_consumed"),
                        count: groups.consumed.count,
                        color: .orange
                    )
                    ForEach(groups.consumed) { seat in
                        seatCard(seat, kind: .consumed)
                    }
                }
            }
        }
        .padding(.horizontal)
        .confirmationDialog(
            checkinConfirmTitle,
            isPresented: Binding(get: { checkinTarget != nil }, set: { if !$0 { checkinTarget = nil } }),
            titleVisibility: .visible,
            presenting: checkinTarget
        ) { seat in
            Button(L10n.string("check_in"), role: .destructive) {
                Task { await performCheckin(seat: seat) }
            }
            Button(L10n.string("cancel"), role: .cancel) {}
        } message: { seat in
            Text(checkinConfirmMessage(for: seat))
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

    private var checkinConfirmTitle: String {
        L10n.string("checkin_confirm_title")
    }

    private func checkinConfirmMessage(for seat: SnipeITAPIClient.LicenseSeatRow) -> String {
        var base: String
        if let userId = seat.assignedUser?.id,
           let user = apiClient.users.first(where: { $0.id == userId }) {
            base = String(format: L10n.string("checkin_user_confirm_message"), user.decodedName)
        } else if let name = seat.assignedUser?.name, !name.isEmpty {
            base = String(format: L10n.string("checkin_user_confirm_message"), name)
        } else if let assetName = seat.assignedAsset?.name, !assetName.isEmpty {
            base = String(format: L10n.string("checkin_user_confirm_message"), assetName)
        } else {
            base = L10n.string("checkin_generic_confirm_message")
        }
        if currentLicense.reassignable == false {
            base += "\n\n" + L10n.string("checkin_unreassignable_warning")
        }
        return base
    }

    private func performCheckin(seat: SnipeITAPIClient.LicenseSeatRow) async {
        checkinTarget = nil
        isCheckingIn = true
        let error = await apiClient.checkinLicenseSeat(licenseId: license.id, seatId: seat.id)
        if let error {
            checkinErrorMessage = error
            showCheckinError = true
        } else {
            seats = await apiClient.fetchLicenseSeats(licenseId: license.id)
            if let detailed = await apiClient.fetchLicenseDetails(licenseId: license.id) {
                fullLicense = detailed
            }
        }
        isCheckingIn = false
    }

    private enum SeatKind {
        case assigned, free, consumed
    }

    /// Splits seats into assigned / free / consumed, using the server's freeSeatsCount
    /// as the source of truth for the unassigned ones (server already accounts for
    /// disabled / unreassignable seats).
    private func categorizedSeats() -> (assigned: [SnipeITAPIClient.LicenseSeatRow],
                                        free: [SnipeITAPIClient.LicenseSeatRow],
                                        consumed: [SnipeITAPIClient.LicenseSeatRow]) {
        let assigned = seats.filter { $0.assignedUser != nil || $0.assignedAsset != nil }
        let unassigned = seats.filter { $0.assignedUser == nil && $0.assignedAsset == nil }
        // Server marks unreassignable / inactive seats as disabled — use that as the
        // primary signal. Fall back to the freeSeatsCount when the field is missing
        // (older Snipe-IT versions).
        var free: [SnipeITAPIClient.LicenseSeatRow] = []
        var consumed: [SnipeITAPIClient.LicenseSeatRow] = []
        if unassigned.contains(where: { $0.disabled != nil }) {
            free = unassigned.filter { $0.disabled != true }
            consumed = unassigned.filter { $0.disabled == true }
        } else {
            let reportedFree = currentLicense.freeSeatsCount ?? currentLicense.remaining ?? unassigned.count
            let freeCount = max(0, min(reportedFree, unassigned.count))
            free = Array(unassigned.prefix(freeCount))
            consumed = Array(unassigned.dropFirst(freeCount))
        }
        return (assigned, free, consumed)
    }

    @ViewBuilder
    private func seatGroupHeader(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("(\(count))")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func seatCard(_ seat: SnipeITAPIClient.LicenseSeatRow, kind: SeatKind) -> some View {
        switch kind {
        case .assigned:
            seatRow(seat)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .contextMenu {
                    Button(role: .destructive) {
                        checkinTarget = seat
                    } label: {
                        Label(L10n.string("check_in"), systemImage: "arrow.down.to.line")
                    }
                    .disabled(seat.userCanCheckin == false)
                }
        case .free:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .frame(width: 30, height: 30)
                Text(L10n.string("license_seats_free"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        case .consumed:
            HStack(spacing: 12) {
                Image(systemName: "xmark.seal.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .frame(width: 30, height: 30)
                Text(L10n.string("license_seats_consumed"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private func seatRow(_ seat: SnipeITAPIClient.LicenseSeatRow) -> some View {
        if let assigned = seat.assignedUser, let userId = assigned.id as Int? {
            Button {
                if let fullUser = apiClient.users.first(where: { $0.id == userId }) {
                    onOpenUser?(fullUser)
                }
            } label: {
                HStack {
                    Image(systemName: "person.circle")
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(apiClient.users.first(where: { $0.id == userId })?.decodedName ?? assigned.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let email = apiClient.users.first(where: { $0.id == userId })?.decodedEmail, !email.isEmpty {
                            Text(email)
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
            .buttonStyle(.plain)
        } else if let assignedAsset = seat.assignedAsset {
            Button {
                if let fullAsset = apiClient.assets.first(where: { $0.id == assignedAsset.id }) {
                    onOpenAsset?(fullAsset)
                }
            } label: {
                HStack {
                    Image(systemName: "laptopcomputer")
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assignedAsset.name ?? "")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func copyableDetailRow(label: String, value: String, copyValue: String? = nil) -> some View {
        let toCopy = copyValue ?? value
        // No spaces (serial/email/key): truncate instead of ugly wrap.
        let isSingleToken = !value.contains(" ")
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
                    .lineLimit(isSingleToken ? 1 : nil)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                copy(value: toCopy, label: label)
            } label: {
                Label(L10n.string("copy"), systemImage: "doc.on.doc")
            }
        }
    }

    private func copy(value: String, label: String) {
        UIPasteboard.general.string = value
        withAnimation {
            copyNotification = label
            showCopyNotification = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showCopyNotification = false }
        }
    }

    private func licenseInfoRows() -> [AnyView] {
        var rows: [AnyView] = []
        let l = currentLicense
        if !l.decodedName.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("name"), value: l.decodedName)))
        }
        if !l.decodedManufacturerName.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("manufacturer"), value: l.decodedManufacturerName)))
        }
        if !l.decodedCategoryName.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("category"), value: l.decodedCategoryName)))
        }
        if !l.decodedLicenseName.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("license_to_name"), value: l.decodedLicenseName)))
        }
        if !l.decodedLicenseEmail.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("license_to_email"), value: l.decodedLicenseEmail)))
        }
        if let expires = l.expirationDate?.formatted, !expires.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("expiration_date"), value: expires)))
        }
        if let purchased = l.purchaseDate?.formatted, !purchased.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("purchase_date"), value: purchased)))
        }
        if let cost = l.purchaseCost, !cost.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("purchase_cost"), value: cost)))
        }
        if let order = l.orderNumber, !order.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("order_number"), value: order)))
        }
        if !l.decodedSupplierName.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("supplier"), value: l.decodedSupplierName)))
        }
        if !l.decodedCompanyName.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("company"), value: l.decodedCompanyName)))
        }
        if let reassignable = l.reassignable {
            rows.append(AnyView(detailRow(
                label: L10n.string("reassignable"),
                value: reassignable ? L10n.string("yes") : L10n.string("no")
            )))
        }
        if let maintained = l.maintained {
            rows.append(AnyView(detailRow(
                label: L10n.string("maintained"),
                value: maintained ? L10n.string("yes") : L10n.string("no")
            )))
        }
        if !l.decodedNotes.isEmpty {
            rows.append(AnyView(copyableDetailRow(label: L10n.string("notes"), value: l.decodedNotes)))
        }
        return rows
    }
}
