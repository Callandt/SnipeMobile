import SwiftUI

struct UserCardView: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "person.circle")
                    .foregroundColor(.gray)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading) {
                    Text(HTMLDecoder.decode(user.decodedName))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(HTMLDecoder.decode(user.decodedEmail))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(HTMLDecoder.decode(user.decodedLocationName))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .padding(.horizontal)
    }
} 