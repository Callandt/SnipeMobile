import SwiftUI

struct AssetCardView: View {
    let asset: Asset
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
                    Text("Tag: \(asset.decodedAssetTag)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let status = asset.statusLabel.statusMeta, !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if !asset.decodedAssignedToName.isEmpty || !asset.decodedLocationName.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !asset.decodedAssignedToName.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "person.circle")
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
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
} 