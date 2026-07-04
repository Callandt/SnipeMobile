import SwiftUI

struct MaintenanceDetailSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let assetId: Int
    let record: AssetMaintenance
    var onMutated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showCompleteConfirm = false
    @State private var isCompleting = false
    @State private var completeNote = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var isBusy: Bool { isDeleting || isCompleting }

    private var linkedAsset: Asset? {
        guard let id = record.assetId, id > 0 else { return nil }
        return apiClient.assets.first { $0.id == id }
    }

    private var assetInfo: MaintenanceLinkedAssetInfo? {
        MaintenanceLinkedAssetInfo.resolve(record: record, asset: linkedAsset)
    }

    private var resolvedImageURL: URL? {
        guard let raw = record.image?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        if raw.hasPrefix("/") {
            return URL(string: "\(apiClient.baseURL)\(raw)")
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    statusHeader

                    if let assetInfo {
                        assetHeaderCard(assetInfo)
                    }

                    if let imageURL = resolvedImageURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("image"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 220)
                                        .frame(maxWidth: .infinity)
                                case .failure:
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, minHeight: 140)
                                default:
                                    ProgressView()
                                        .frame(maxWidth: .infinity, minHeight: 140)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    VStack(spacing: 10) {
                        if let type = record.displayType {
                            detailRow(label: L10n.string("maintenance_type"), value: type)
                        }
                        if let supplier = record.supplier {
                            detailRow(label: L10n.string("supplier_optional"), value: HTMLDecoder.decode(supplier.name))
                        }
                        if let start = record.startDate?.formatted, !start.isEmpty {
                            detailRow(label: L10n.string("start_date"), value: start)
                        }
                        if let end = record.completionDate?.formatted, !end.isEmpty {
                            detailRow(label: L10n.string("completion_date"), value: end)
                        } else {
                            detailRow(label: L10n.string("completion_date"), value: L10n.string("in_progress"))
                        }
                        if let time = record.maintenanceTime, time > 0 {
                            detailRow(label: L10n.string("maintenance_duration"), value: L10n.string("maintenance_duration_days", time))
                        }
                        if let cost = record.cost, !cost.isEmpty {
                            detailRow(label: L10n.string("cost"), value: cost)
                        }
                        detailRow(label: L10n.string("is_warranty"), value: record.isWarranty ? L10n.string("yes") : L10n.string("no"))
                        if let urlString = record.url, !urlString.isEmpty {
                            detailLinkRow(label: L10n.string("url"), urlString: urlString)
                        }
                        if let responsible = record.responsibleParty {
                            detailRow(label: L10n.string("responsible_party"), value: HTMLDecoder.decode(responsible.name))
                        }
                        if let createdBy = record.createdBy {
                            detailRow(label: L10n.string("created_by"), value: HTMLDecoder.decode(createdBy.name))
                        }
                        if let completedBy = record.completedBy {
                            detailRow(label: L10n.string("completed_by"), value: HTMLDecoder.decode(completedBy.name))
                        }
                        if let completedAt = record.completedAt?.formatted, !completedAt.isEmpty {
                            detailRow(label: L10n.string("completed_date"), value: completedAt)
                        }
                        if let created = record.createdAt?.formatted, !created.isEmpty {
                            detailRow(label: L10n.string("created_date"), value: created)
                        }
                        if let updated = record.updatedAt?.formatted, !updated.isEmpty {
                            detailRow(label: L10n.string("updated_date"), value: updated)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    if !record.decodedNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.string("notes"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(record.decodedNotes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .navigationTitle(record.decodedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("close")) { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showEditSheet = true } label: {
                        Image(systemName: "pencil")
                    }
                    .disabled(isBusy)
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(isBusy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !record.isCompleted {
                    Button {
                        completeNote = ""
                        showCompleteConfirm = true
                    } label: {
                        Label(L10n.string("mark_complete"), systemImage: "checkmark.seal")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .disabled(isBusy)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.bar)
                }
            }
            .overlay {
                if isBusy {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            MaintenanceFormSheet(apiClient: apiClient, assetId: assetId, record: record) {
                onMutated()
                dismiss()
            }
        }
        .alert(L10n.string("delete_maintenance_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L10n.string("cancel"), role: .cancel) {}
            Button(L10n.string("delete"), role: .destructive) {
                Task { await deleteRecord() }
            }
        } message: {
            Text(L10n.string("delete_maintenance_confirm_message", record.decodedTitle))
        }
        .sheet(isPresented: $showCompleteConfirm) {
            CompletionActionSheet(
                title: L10n.string("mark_complete_confirm_title"),
                message: L10n.string("mark_complete_confirm_message"),
                note: $completeNote,
                confirmTitle: L10n.string("mark_complete"),
                isSaving: isCompleting,
                onSave: { Task { await completeRecord() } }
            )
        }
        .alert(L10n.string("error"), isPresented: $showErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private var statusHeader: some View {
        let completed = record.isCompleted
        HStack(spacing: 6) {
            Image(systemName: completed ? "checkmark.seal.fill" : "clock")
            Text(completed ? L10n.string("status_completed") : L10n.string("in_progress"))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(completed ? .green : .orange)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background((completed ? Color.green : Color.orange).opacity(0.12), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func assetHeaderCard(_ info: MaintenanceLinkedAssetInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("asset"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(info.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let detail = info.detailLine {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            if let assignee = info.assignee {
                HStack(spacing: 6) {
                    Image(systemName: "person.circle")
                        .foregroundStyle(.secondary)
                    Text(L10n.string("checked_out_to"))
                        .fontWeight(.semibold)
                    Text(assignee)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).fontWeight(.semibold)
            Text(value)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailLinkRow(label: String, urlString: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).fontWeight(.semibold)
            if let url = URL(string: urlString) {
                Link(urlString, destination: url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(urlString)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deleteRecord() async {
        isDeleting = true
        let ok = await apiClient.deleteMaintenance(id: record.id)
        isDeleting = false
        if ok {
            onMutated()
            dismiss()
        } else {
            errorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showErrorAlert = true
        }
    }

    private func completeRecord() async {
        isCompleting = true
        let ok = await apiClient.completeMaintenance(id: record.id, note: completeNote)
        isCompleting = false
        showCompleteConfirm = false
        if ok {
            onMutated()
            dismiss()
        } else {
            errorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showErrorAlert = true
        }
    }
}
