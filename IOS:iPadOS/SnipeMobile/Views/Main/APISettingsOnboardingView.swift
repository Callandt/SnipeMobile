import SwiftUI

struct APISettingsOnboardingView: View {
    var onContinue: (_ apiUrl: String, _ apiKey: String) -> Void
    var onSkip: () -> Void
    @ObservedObject var apiClient: SnipeITAPIClient

    private enum Phase: Equatable {
        case domain
        case checking
        case oauth(clientId: String)
        case apiKey
        case error
    }

    @State private var apiUrl: String = ""
    @State private var apiKey: String = ""
    @State private var phase: Phase = .domain
    @State private var showAPIKeyOverride = false
    @State private var isSigningIn = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showSkipConfirm = false
    @State private var checkGeneration = 0

    var body: some View {
        ZStack {
            Image("WelcomeBG")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            GeometryReader { geometry in
                ScrollView {
                    VStack {
                        Spacer(minLength: 24)
                        card
                        Spacer(minLength: 24)
                    }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertMessage))
        }
        .alert(L10n.string("skip_api_confirm_title"), isPresented: $showSkipConfirm) {
            Button(L10n.string("continue")) {
                onSkip()
            }
            Button(L10n.string("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("skip_api_confirm_message"))
        }
    }

    private var card: some View {
        VStack(spacing: 28) {
            Image("SnipeMobile")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(radius: 8, y: 4)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text(L10n.string("connect_snipe_it"))
                    .font(.title).bold()
                    .multilineTextAlignment(.center)
                Text(L10n.string("connect_snipe_it_desc"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snipe-IT URL").font(.headline)
                    TextField("https://snipeit.yourcompany.com", text: $apiUrl)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(12)
                        .disabled(isBusy)
                        .onChange(of: apiUrl) { _, _ in
                            resetToDomainIfNeeded()
                        }
                }

                phaseContent
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.98))
                .shadow(color: Color.black.opacity(0.07), radius: 12, y: 4)
        )
        .frame(maxWidth: 420)
        .padding(.horizontal, 24)
    }

    private var isBusy: Bool {
        isSigningIn || phase == .checking
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .domain:
            Button(action: handleContinueFromDomain) {
                Text(L10n.string("continue"))
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .padding(.top, 4)

        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.string("login_checking_instance"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        case .oauth:
            oauthContent

        case .apiKey:
            apiKeyContent(reason: L10n.string("login_oauth_unavailable"))

        case .error:
            VStack(spacing: 12) {
                Text(L10n.string("login_connection_error"))
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button(L10n.string("rights_check_retry")) {
                    phase = .domain
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
    }

    private var oauthContent: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Text(L10n.string("login_oauth_ready"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await signInWithOAuth() }
            } label: {
                HStack {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSigningIn ? L10n.string("login_signing_in") : L10n.string("login_sign_in"))
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(isSigningIn)

            Button {
                withAnimation {
                    showAPIKeyOverride.toggle()
                }
            } label: {
                Text(
                    showAPIKeyOverride
                        ? L10n.string("login_hide_api_key")
                        : L10n.string("login_use_api_key")
                )
                .font(.subheadline.weight(.medium))
            }
            .disabled(isSigningIn)

            if showAPIKeyOverride {
                apiKeyFields
                Button {
                    Task { await continueWithAPIKey() }
                } label: {
                    Text(L10n.string("continue"))
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isSigningIn)
            }
        }
    }

    private func apiKeyContent(reason: String) -> some View {
        VStack(spacing: 14) {
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            apiKeyFields
            Link(destination: URL(string: "https://snipe-it.readme.io/reference/generating-api-tokens")!) {
                Text(L10n.string("how_api_key"))
                    .font(.footnote)
                    .underline()
            }
            Button {
                Task { await continueWithAPIKey() }
            } label: {
                Text(L10n.string("continue"))
            }
            .buttonStyle(PrimaryActionButtonStyle())
        }
    }

    private var apiKeyFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("login_api_key")).font(.headline)
            SecureField(L10n.string("login_api_key_placeholder"), text: $apiKey)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .padding()
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(12)
        }
    }

    private func resetToDomainIfNeeded() {
        switch phase {
        case .domain, .checking:
            break
        default:
            checkGeneration += 1
            phase = .domain
            showAPIKeyOverride = false
        }
    }

    private func handleContinueFromDomain() {
        let trimmed = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showSkipConfirm = true
            return
        }
        Task { await checkServer() }
    }

    private func checkServer() async {
        let generation = checkGeneration + 1
        checkGeneration = generation
        phase = .checking
        let discovery = await SnipeITOAuthService.shared.discover(baseURL: apiUrl)
        guard generation == checkGeneration else { return }
        switch discovery {
        case .oauth(let clientId):
            phase = .oauth(clientId: clientId)
        case .unavailable:
            phase = .apiKey
        case .unreachable:
            phase = .error
        }
    }

    private func signInWithOAuth() async {
        guard case .oauth(let clientId) = phase else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let result = try await SnipeITOAuthService.shared.signIn(
                baseURL: apiUrl,
                clientId: clientId
            )
            apiClient.saveConfiguration(
                baseURL: result.baseURL,
                apiToken: result.token,
                syncAfterSave: false
            )
            if let error = await apiClient.validateApiCredentials() {
                alertMessage = error
                showAlert = true
                return
            }
            onContinue(result.baseURL, result.token)
        } catch {
            if (error as? SnipeITOAuthService.ServiceError) == .cancelled {
                return
            }
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func continueWithAPIKey() async {
        let urlEmpty = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let keyEmpty = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if urlEmpty || keyEmpty {
            showSkipConfirm = true
            return
        }
        apiClient.saveConfiguration(
            baseURL: apiUrl,
            apiToken: apiKey,
            syncAfterSave: false
        )
        if let error = await apiClient.validateApiCredentials() {
            alertMessage = error
            showAlert = true
            return
        }
        onContinue(apiUrl, apiKey)
    }
}

struct APISettingsOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        APISettingsOnboardingView(onContinue: { _, _ in }, onSkip: {}, apiClient: SnipeITAPIClient())
    }
}
