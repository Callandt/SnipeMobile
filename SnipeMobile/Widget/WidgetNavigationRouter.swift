import Foundation

@MainActor
final class WidgetNavigationRouter: ObservableObject {
    struct PendingRequest: Identifiable {
        let id = UUID()
        let destination: WidgetDeepLinkDestination
    }

    @Published var pendingRequest: PendingRequest?

    func open(_ destination: WidgetDeepLinkDestination) {
        WidgetDeepLinkStore.storePending(destination)
        pendingRequest = PendingRequest(destination: destination)
    }

    func consume() {
        pendingRequest = nil
        _ = WidgetDeepLinkStore.consumePending()
    }
}
