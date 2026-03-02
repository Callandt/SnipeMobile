import SwiftUI

struct AccessoryCardView: View {
    let accessory: Accessory
    var useExplicitBackground: Bool = true
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "mediastick")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(accessory.decodedName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(String(format: L10n.string("tag_label"), accessory.decodedAssetTag))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let manufacturerName = accessory.manufacturer?.name, !manufacturerName.isEmpty {
                        Text(manufacturerName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if !accessory.decodedAssignedToName.isEmpty || !accessory.decodedLocationName.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !accessory.decodedAssignedToName.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "person.circle")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(accessory.decodedAssignedToName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(2)
                        }
                    }
                    if !accessory.decodedLocationName.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "mappin.circle")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                            Text(accessory.decodedLocationName)
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
            useExplicitBackground ? Color(.secondarySystemGroupedBackground) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
    }
} 