import SwiftUI

struct LocationCardView: View {
    let location: Location

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
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
} 