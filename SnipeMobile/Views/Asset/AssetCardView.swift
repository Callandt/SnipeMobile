import SwiftUI

struct AssetCardView: View {
    let asset: Asset
    /// iPad: transparent row vs card background.
    var useExplicitBackground: Bool = true
    /// Used in the audit subtab to show the next audit date on the card.
    var showNextAuditDate: Bool = false
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(format: L10n.string("tag_label"), asset.decodedAssetTag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !asset.decodedSerial.isEmpty {
                            HStack(spacing: 4) {
                                Text(L10n.string("sn_label"))
                                Text(asset.decodedSerial)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let status = asset.statusLabel.statusMeta, !status.isEmpty {
                        Text(L10n.statusLabel(status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if showNextAuditDate,
                       let nextAudit = asset.nextAuditDate?.formatted,
                       !nextAudit.isEmpty {
                        Text("\(L10n.string("next_audit_date")): \(nextAudit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            let effectiveTitle = asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName
            let showAssetName = !asset.decodedName.isEmpty && asset.decodedName != effectiveTitle
            if showAssetName || !asset.decodedAssignedToName.isEmpty || !asset.decodedLocationName.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if showAssetName {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "tag")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(asset.decodedName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(2)
                        }
                    }
                    if !asset.decodedAssignedToName.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: assigneeIconName)
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(asset.decodedAssignedToName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(2)
                        }
                    }
                    if !asset.decodedLocationName.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "mappin.circle")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(asset.decodedLocationName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            useExplicitBackground ? Color(.secondarySystemBackground) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var assigneeIconName: String {
        guard let assignedTo = asset.assignedTo else { return "person.circle" }
        if assignedTo.isLocation { return "mappin.circle" }
        if assignedTo.isAsset { return "laptopcomputer" }
        return "person.circle"
    }
} 
