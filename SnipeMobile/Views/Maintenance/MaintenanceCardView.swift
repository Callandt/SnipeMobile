import SwiftUI

struct MaintenanceCardView: View {
    let record: AssetMaintenance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.decodedTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if let type = record.assetMaintenanceType, !type.isEmpty {
                        Text(type)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let cost = record.cost, !cost.isEmpty {
                    Text(cost)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            if let start = record.startDate?.formatted, !start.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    if let end = record.completionDate?.formatted, !end.isEmpty {
                        Text("\(start) → \(end)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(start) → \(L10n.string("in_progress"))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if record.isWarranty {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.string("is_warranty"))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}
