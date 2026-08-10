import SwiftUI

// Big primary button used across onboarding.
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.headline)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(background)
            .cornerRadius(16)
            .shadow(radius: 4, y: 2)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var background: some View {
        // Typed as Color so opacity stays unambiguous on newer SDKs.
        let tint: Color = Color(red: 15 / 255, green: 61 / 255, blue: 102 / 255).opacity(0.95)
        return tint.blendMode(.multiply)
    }
}
