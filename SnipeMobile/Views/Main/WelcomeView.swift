import SwiftUI

struct WelcomeView: View {
    var onGetStarted: () -> Void
    
    var body: some View {
        ZStack {
            Image("WelcomeBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            VStack {
                Spacer()
                VStack(spacing: 32) {
                    Image("SnipeMobile")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(radius: 8, y: 4)
                        .padding(.top, 16)

                    Text("Welcome to SnipeMobile")
                        .font(.title).bold()
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manage Assets On-the-Go").bold()
                                Text("Scan QR codes to view and manage assets instantly.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "key.fill")
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connect Snipe-IT").bold()
                                Text("Add your Snipe-IT API key in your profile to sync and start managing.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "bird.fill")
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Always Free").bold()
                                Text("The app is free forever. All features are available at no cost.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button(action: onGetStarted) {
                            Text("Get Started")
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
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground).opacity(0.98))
                        .shadow(color: Color.black.opacity(0.07), radius: 12, y: 4)
                )
                .frame(maxWidth: 420)
                Spacer()
            }
        }
    }
}

// Preview
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(onGetStarted: {})
    }
} 
