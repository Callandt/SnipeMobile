import SwiftUI

struct AssetCardView<Footer: View>: View {
    let asset: Asset
    /// iPad list rows skip the card fill.
    var useExplicitBackground: Bool = true
    /// Audit subtab: next audit date.
    var showNextAuditDate: Bool = false
    var onSelect: (() -> Void)? = nil
    @ViewBuilder private var footer: () -> Footer
    @Environment(\.cardLayouts) private var cardLayouts

    init(
        asset: Asset,
        useExplicitBackground: Bool = true,
        showNextAuditDate: Bool = false,
        onSelect: (() -> Void)? = nil,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.asset = asset
        self.useExplicitBackground = useExplicitBackground
        self.showNextAuditDate = showNextAuditDate
        self.onSelect = onSelect
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let onSelect {
                    infoSection
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onSelect)
                } else {
                    infoSection
                }
            }

            footer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            useExplicitBackground ? Color(.secondarySystemBackground) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var infoSection: some View {
        let resolved = AssetCardFields.resolve(
            asset,
            layouts: cardLayouts,
            locationName: cardLocationName,
            status: resolvedStatusLabel
        )
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CardListIcon(
                    systemName: "laptopcomputer",
                    imagePath: asset.image,
                    cacheBuster: asset.updatedAt?.datetime ?? asset.updatedAt?.date
                )
                CardLayoutHeader(
                    resolved: resolved,
                    extraLines: auditExtraLines
                )
                Spacer()
            }
            CardLayoutMeta(items: resolved.meta)

            if let assigneeName = checkedOutAssigneeName {
                checkedOutBanner(assigneeName: assigneeName)
            }
        }
    }

    private var auditExtraLines: [String] {
        guard showNextAuditDate,
              let nextAudit = asset.nextAuditDate?.formatted,
              !nextAudit.isEmpty else { return [] }
        return ["\(L10n.string("next_audit_date")): \(nextAudit)"]
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

extension AssetCardView where Footer == EmptyView {
    init(
        asset: Asset,
        useExplicitBackground: Bool = true,
        showNextAuditDate: Bool = false,
        onSelect: (() -> Void)? = nil
    ) {
        self.init(
            asset: asset,
            useExplicitBackground: useExplicitBackground,
            showNextAuditDate: showNextAuditDate,
            onSelect: onSelect,
            footer: { EmptyView() }
        )
    }
}
