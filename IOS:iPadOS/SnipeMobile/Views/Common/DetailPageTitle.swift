import SwiftUI

struct DetailPageTitle: View {
    let title: String

    var body: some View {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Text(trimmed)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
        }
    }
}
