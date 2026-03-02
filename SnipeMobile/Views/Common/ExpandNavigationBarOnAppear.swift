import SwiftUI
import UIKit

/// Zorgt ervoor dat de navigation bar op een gepushte detail view weer groot (large title) wordt,
/// ook als de vorige scherm gebar was ingeklapt door scrollen.
struct ExpandNavigationBarOnAppear: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ExpandNavBarTrigger())
    }
}

private struct ExpandNavBarTrigger: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coord = context.coordinator
        guard !coord.didRun else { return }
        coord.didRun = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let vc = uiView.findViewController() else { return }
            vc.navigationItem.largeTitleDisplayMode = .always
            vc.navigationController?.navigationBar.setNeedsLayout()
            vc.navigationController?.navigationBar.layoutIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var didRun = false
    }
}

private extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}

extension View {
    /// Gebruik op detail views zodat de navigation bar daar weer groot (expanded) wordt na push.
    func expandNavigationBarOnAppear() -> some View {
        modifier(ExpandNavigationBarOnAppear())
    }
}
