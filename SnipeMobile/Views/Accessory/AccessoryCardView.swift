import SwiftUI

struct AccessoryCardView: View {
    let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mediastick")
                    .foregroundColor(.gray)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading) {
                    Text(accessory.decodedName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("tag: \(accessory.decodedAssetTag)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let manufacturerName = accessory.manufacturer?.name, !manufacturerName.isEmpty {
                        Text("manufacturer: \(manufacturerName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            if !accessory.decodedAssignedToName.isEmpty {
                Text("Assigned to: \(accessory.decodedAssignedToName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !accessory.decodedLocationName.isEmpty {
                Text("Location: \(accessory.decodedLocationName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
} 