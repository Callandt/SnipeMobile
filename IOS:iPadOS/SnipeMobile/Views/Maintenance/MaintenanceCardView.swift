import SwiftUI

struct MaintenanceCardView: View {
    let record: AssetMaintenance
    // resolved from the cached asset list for a nicer header
    var linkedAsset: Asset? = nil
    // only the overview shows the asset strip
    var showAssetHeader: Bool = false

    private var assetInfo: MaintenanceLinkedAssetInfo? {
        guard showAssetHeader else { return nil }
        return MaintenanceLinkedAssetInfo.resolve(record: record, asset: linkedAsset)
    }

    private var accentColor: Color {
        record.isCompleted ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let assetInfo {
                assetHeader(assetInfo)
                Divider()
                    .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 40, height: 40)
                        .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.decodedTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let type = record.displayType {
                            Text(type)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if let cost = record.cost, !cost.isEmpty {
                        Text(cost)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                }

                if let dateText = dateRangeText {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Text(dateText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    statusBadge
                    if record.isWarranty {
                        badge(
                            icon: "checkmark.shield.fill",
                            text: L10n.string("is_warranty"),
                            color: .accentColor
                        )
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private var dateRangeText: String? {
        guard let start = record.startDate?.formatted, !start.isEmpty else { return nil }
        if let end = record.completionDate?.formatted, !end.isEmpty {
            return "\(start)  →  \(end)"
        }
        return "\(start)  →  \(L10n.string("in_progress"))"
    }

    private func assetHeader(_ info: MaintenanceLinkedAssetInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail = info.detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let assignee = info.assignee {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text(assignee)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if record.isCompleted {
            badge(icon: "checkmark.seal.fill", text: L10n.string("status_completed"), color: .green)
        } else {
            badge(icon: "clock.fill", text: L10n.string("in_progress"), color: .orange)
        }
    }

    private func badge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}
