import SwiftUI

struct StrongBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.alpha = 0.98 // bijna volledig dekkend
        return blurView
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
} 