import SwiftUI

struct UserCardView: View {
    let user: User
    @EnvironmentObject var appSettings: AppSettings

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.07), radius: 4, x: 0, y: 2)
    }
} 