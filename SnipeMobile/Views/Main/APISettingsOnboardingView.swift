import SwiftUI

struct APISettingsOnboardingView: View {
    @State private var apiUrl: String = ""
    @State private var apiKey: String = ""
    var onContinue: (_ apiUrl: String, _ apiKey: String) -> Void
    var onSkip: () -> Void
    
    var body: some View {
        ZStack {
            Image("WelcomeBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 32) {
                        Image("SnipeMobile")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(radius: 8, y: 4)
                            .padding(.top, 16)
                        Text("Connect to Snipe-IT")
                            .font(.title).bold()
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        Text("Enter your Snipe-IT API URL and API Key to sync your assets. You can skip this step and add it later in Settings.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)

                        // Toevoegen van de link naar de Snipe-IT API key uitleg
                        Link(destination: URL(string: "https://snipe-it.readme.io/reference/generating-api-tokens")!) {
                            Text("How to generate an API key?")
                                .font(.footnote)
                                .foregroundColor(Color.blue)
                                .underline()
                                .padding(.top, 2)
                        }

                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Snipe-IT URL").font(.headline)
                                TextField("https://snipeit.yourcompany.com", text: $apiUrl)
                                    .textContentType(.URL)
                                    .keyboardType(.URL)
                                    .autocapitalization(.none)
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("API Key").font(.headline)
                                SecureField("Your API Key", text: $apiKey)
                                    .textContentType(.password)
                                    .autocapitalization(.none)
                                    .padding()
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .cornerRadius(12)
                            }
                        }
                        Button(action: {
                            let urlEmpty = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            let keyEmpty = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            if urlEmpty || keyEmpty {
                                onSkip()
                            } else {
                                onContinue(apiUrl, apiKey)
                            }
                        }) {
                            Text("Continue")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    Color(red: 15/255, green: 61/255, blue: 102/255)
                                        .opacity(0.95)
                                        .blendMode(.multiply)
                                )
                                .cornerRadius(16)
                                .shadow(radius: 4, y: 2)
                        }
                        .padding(.top, 18)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground).opacity(0.98))
                            .shadow(color: Color.black.opacity(0.07), radius: 12, y: 4)
                    )
                    .frame(maxWidth: 420)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
            }
        }
    }
}

// Preview
struct APISettingsOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        APISettingsOnboardingView(onContinue: { _, _ in }, onSkip: {})
    }
} 
