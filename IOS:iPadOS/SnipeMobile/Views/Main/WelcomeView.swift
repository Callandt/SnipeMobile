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

                    Text(L10n.string("welcome_title"))
                        .font(.title).bold()
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string("welcome_manage_assets")).bold()
                                Text(L10n.string("welcome_scan_qr"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "key.fill")
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string("welcome_connect")).bold()
                                Text(L10n.string("welcome_connect_desc"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "bird.fill")
                                .font(.title2)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string("welcome_free")).bold()
                                Text(L10n.string("welcome_free_desc"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button(action: onGetStarted) {
                            Text(L10n.string("get_started"))
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
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
