import SwiftUI

struct AssetCardView: View {
    let asset: Asset
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "laptopcomputer")
                    .foregroundColor(.gray)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading) {
                    Text(asset.decodedModelName.isEmpty ? asset.decodedName : asset.decodedModelName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Tag: " + asset.decodedAssetTag)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Status: " + asset.statusLabel.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            if !asset.decodedAssignedToName.isEmpty {
                Text("Assigned to: " + asset.decodedAssignedToName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !asset.decodedLocationName.isEmpty {
                Text("Location: " + asset.decodedLocationName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 4, x: 0, y: 2)
    }
} 