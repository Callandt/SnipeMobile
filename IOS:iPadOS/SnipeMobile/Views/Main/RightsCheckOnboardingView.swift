import SwiftUI

struct RightsCheckOnboardingView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    var onFinished: (_ mode: AppMode) -> Void
    var onFailed: () -> Void

    @State private var progress = AppModeCheckProgress()
    @State private var didStart = false

    var body: some View {
        ZStack {
            Image("WelcomeBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 28) {
                        Image("SnipeMobile")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(radius: 8, y: 4)
                            .padding(.top, 8)

                        VStack(spacing: 8) {
                            Text(L10n.string("rights_check_title"))
                                .font(.title).bold()
                                .multilineTextAlignment(.center)

                            Text(L10n.string("rights_check_subtitle"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }

                        VStack(spacing: 0) {
                            RightsCheckProgressList(progress: progress)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(UIColor.tertiarySystemBackground))
                        )

                        if progress.succeeded, let mode = progress.detectedMode {
                            Text(
                                mode == .admin
                                    ? L10n.string("rights_check_result_admin")
                                    : L10n.string("rights_check_result_user")
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                        } else if case .failure(let message) = progress.connection {
                            Text(message ?? L10n.string("rights_check_failed"))
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        } else if case .failure(let message) = progress.rights {
                            Text(message ?? L10n.string("rights_check_failed"))
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        if progress.isComplete {
                            VStack(spacing: 12) {
                                Button {
                                    if progress.succeeded, let mode = progress.detectedMode {
                                        onFinished(mode)
                                    } else {
                                        Task { await runCheck() }
                                    }
                                } label: {
                                    Text(
                                        progress.succeeded
                                            ? L10n.string("continue")
                                            : L10n.string("rights_check_retry")
                                    )
                                }
                                .buttonStyle(PrimaryActionButtonStyle())

                                if !progress.succeeded {
                                    Button(L10n.string("back")) {
                                        onFailed()
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)
                        } else {
                            ProgressView()
                                .padding(.top, 8)
                        }
                    }
                    .padding(28)
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
        .task {
            guard !didStart else { return }
            didStart = true
            await runCheck()
        }
    }

    private func runCheck() async {
        progress = AppModeCheckProgress()
        _ = await apiClient.detectAppMode { updated in
            progress = updated
        }
    }
}

#Preview {
    RightsCheckOnboardingView(apiClient: SnipeITAPIClient(), onFinished: { _ in }, onFailed: {})
}
