import SwiftUI

extension View {
    /// Centered icon + title over a list when there are no items (matches consumables/stock tabs).
    func moduleEmptyOverlay(isVisible: Bool, title: String, systemImage: String) -> some View {
        overlay {
            if isVisible {
                ContentUnavailableView(title, systemImage: systemImage)
            }
        }
    }
}
