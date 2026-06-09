import SwiftUI

extension View {
    // White page behind the grey browse cards.
    func browseListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
    }
}
