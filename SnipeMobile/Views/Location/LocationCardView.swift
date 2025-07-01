import SwiftUI

struct LocationCardView: View {
    let location: Location
    @EnvironmentObject var appSettings: AppSettings

    var body: some View {
        HStack {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(.gray)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading) {
                Text(location.name)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 4, x: 0, y: 2)
    }
} 