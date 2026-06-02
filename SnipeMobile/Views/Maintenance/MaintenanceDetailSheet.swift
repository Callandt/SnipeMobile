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
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    VStack(spacing: 10) {
                        if let type = record.assetMaintenanceType, !type.isEmpty {
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
                        if let cost = record.cost, !cost.isEmpty {
                            detailRow(label: L10n.string("cost"), value: cost)
                        }
                        detailRow(label: L10n.string("is_warranty"), value: record.isWarranty ? L10n.string("yes") : L10n.string("no"))
                        if let completedBy = record.completedBy {
                            detailRow(label: L10n.string("completed_by"), value: HTMLDecoder.decode(completedBy.name))
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
                    .disabled(isDeleting)
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .disabled(isDeleting)
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
        .alert(L10n.string("error"), isPresented: $showErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).fontWeight(.semibold)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
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
}
