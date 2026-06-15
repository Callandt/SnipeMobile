import SwiftUI
import UIKit

struct AuditDetailSheet: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    let asset: Asset
    var onCompleted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var showCompleteSheet = false
    @State private var isCompleting = false
    @State private var completeNote = ""
    @State private var nextAuditDate = Date()
    @State private var setNextAuditDate = true
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private var auditStatus: (text: String, color: Color, icon: String) {
        let now = Date()
        if AuditDateClassifier.isOverdue(asset, now: now) {
            return (L10n.string("audit_status_overdue"), .red, "exclamationmark.triangle.fill")
        }
        if AuditDateClassifier.isDueToday(asset, now: now) {
            return (L10n.string("audit_status_due_today"), .orange, "clock.fill")
        }
        if AuditDateClassifier.isDueSoon(asset, now: now, dueSoonDays: 7) {
            return (L10n.string("audit_status_due_soon"), .yellow, "clock")
        }
        return (L10n.string("audit_status_scheduled"), .green, "checkmark.seal")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    statusHeader

                    assetHeaderCard

                    VStack(spacing: 10) {
                        if let status = asset.statusLabel.statusMeta, !status.isEmpty {
                            detailRow(label: L10n.string("status"), value: L10n.statusLabel(status))
                        }
                        if !asset.decodedModelName.isEmpty {
                            detailRow(label: L10n.string("model"), value: asset.decodedModelName)
                        }
                        if !asset.decodedSerial.isEmpty {
                            detailRow(label: L10n.string("serial_number"), value: asset.decodedSerial)
                        }
                        if !asset.decodedLocationName.isEmpty {
                            detailRow(label: L10n.string("location"), value: asset.decodedLocationName)
                        }
                        if !asset.decodedAssignedToName.isEmpty {
                            detailRow(label: L10n.string("checked_out_to"), value: asset.decodedAssignedToName)
                        }
                        if let last = asset.lastAuditDate?.formatted, !last.isEmpty {
                            detailRow(label: L10n.string("last_audit_date"), value: last)
                        }
                        if let next = asset.nextAuditDate?.formatted, !next.isEmpty {
                            detailRow(label: L10n.string("next_audit_date"), value: next)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .navigationTitle(L10n.string("audit_details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("close")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    completeNote = ""
                    nextAuditDate = AuditDateClassifier.nextAuditDateGMT(asset) ?? Date()
                    setNextAuditDate = true
                    showCompleteSheet = true
                } label: {
                    Label(L10n.string("complete_audit"), systemImage: "checkmark.seal")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(isCompleting)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.bar)
            }
            .overlay {
                if isCompleting {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(isPresented: $showCompleteSheet) {
            CompletionActionSheet(
                title: L10n.string("complete_audit_confirm_title"),
                message: L10n.string("complete_audit_confirm_message"),
                dateLabel: L10n.string("next_audit_date"),
                date: $nextAuditDate,
                includeDate: $setNextAuditDate,
                includeDateLabel: L10n.string("audit_set_next_audit_date"),
                note: $completeNote,
                confirmTitle: L10n.string("complete_audit"),
                isSaving: isCompleting,
                onSave: { Task { await completeAudit() } }
            )
        }
        .alert(L10n.string("error"), isPresented: $showErrorAlert) {
            Button(L10n.string("ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var statusHeader: some View {
        let status = auditStatus
        return HStack(spacing: 6) {
            Image(systemName: status.icon)
            Text(status.text)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(status.color.opacity(0.12), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var assetHeaderCard: some View {
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
                    Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(String(format: L10n.string("tag_label"), asset.decodedAssetTag))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
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

    @MainActor
    private func completeAudit() async {
        guard !isCompleting else { return }
        let tag = asset.decodedAssetTag
        guard !tag.isEmpty else {
            errorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showErrorAlert = true
            return
        }
        isCompleting = true
        defer { isCompleting = false }

        let nextStr = setNextAuditDate ? dateFormatter.string(from: nextAuditDate) : nil
        let noteOpt = completeNote.trimmingCharacters(in: .whitespaces).isEmpty ? nil : completeNote

        let ok = await apiClient.auditAsset(
            assetTag: tag,
            assetId: asset.id,
            nextAuditDate: nextStr,
            note: noteOpt
        )

        if ok {
            await apiClient.fetchAssets()
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            showCompleteSheet = false
            onCompleted()
            dismiss()
        } else {
            errorMessage = apiClient.lastApiMessage ?? apiClient.errorMessage ?? L10n.string("error")
            showErrorAlert = true
        }
    }
}
