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
                    if let status = resolvedStatusLabel, !status.isEmpty {
                        Text(status)
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
            if showAssetName || cardLocationName != nil {
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
                    if let locationName = cardLocationName {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "mappin.circle")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(locationName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(2)
                        }
                    }
                }
            }

            if let assigneeName = checkedOutAssigneeName {
                checkedOutBanner(assigneeName: assigneeName)
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

    private func checkedOutBanner(assigneeName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: checkedOutTargetIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("checked_out_to"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(assigneeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var checkedOutAssigneeName: String? {
        let assignee = asset.decodedAssignedToName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assignee.isEmpty, asset.assignedTo != nil else { return nil }
        return assignee
    }

    private var checkedOutTargetIcon: String {
        guard let assignedTo = asset.assignedTo else { return "arrow.up.to.line" }
        if assignedTo.isLocation { return "mappin.circle.fill" }
        if assignedTo.isAsset { return "laptopcomputer" }
        return "person.fill"
    }

    private var cardLocationName: String? {
        if asset.assignedTo == nil {
            let defaultName = decodedDefaultLocationName
            if !defaultName.isEmpty { return defaultName }
            let current = asset.decodedLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
            return current.isEmpty ? nil : current
        }

        if asset.assignedTo?.isLocation == true { return nil }

        let location = asset.decodedLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !location.isEmpty else { return nil }
        let assignee = asset.decodedAssignedToName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assignee.isEmpty,
           assignee.caseInsensitiveCompare(location) == .orderedSame {
            return nil
        }
        return location
    }

    private var decodedDefaultLocationName: String {
        HTMLDecoder.decode(asset.rtdLocation?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedStatusLabel: String? {
        let name = asset.decodedStatusLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let meta = asset.statusLabel.statusMeta?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return meta.isEmpty ? nil : L10n.statusLabel(meta)
    }
}
