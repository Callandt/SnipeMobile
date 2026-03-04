import SwiftUI

struct AssetCardView: View {
    let asset: Asset
    /// Op iPad lijst: false = transparant (rij-achtergrond zichtbaar), true = eigen kaart-achtergrond.
    var useExplicitBackground: Bool = true
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
        .background(
            useExplicitBackground ? Color(.secondarySystemGroupedBackground) : Color.clear,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .contentShape(Rectangle())
    }
} 