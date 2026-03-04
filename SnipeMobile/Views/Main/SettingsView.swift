import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var apiClient: SnipeITAPIClient
    /// When true, view is shown inside the tab bar (no Close button).
    var isPresentedAsTab: Bool = false
    @AppStorage("useBiometrics") private var useBiometrics: Bool = false
    @AppStorage("appTheme") private var appTheme: String = "system"
    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var path: [SettingsRoute] = []
    @AppStorage("settingsLanguage") private var settingsLanguage: String = "en"
    @State private var showBiometricError: Bool = false
    @State private var biometricErrorMessage: String = ""
    @State private var didAppear = false
    @State private var pendingBiometricsValue: Bool? = nil
    @AppStorage("biometricsJustConfirmed") private var biometricsJustConfirmed: Bool = false
    @AppStorage("useCloudSync") private var useCloudSync: Bool = true

    /// iCloud is beschikbaar als het toestel met een Apple ID is ingelogd.
    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var isDutch: Bool { settingsLanguage == "nl" }
    var isEnglish: Bool { settingsLanguage == "en" }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section(header: Text(L10n.string("appearance"))) {
                    Picker(L10n.string("theme"), selection: $appTheme) {
                        Text(L10n.string("system")).tag("system")
                        Text(L10n.string("light")).tag("light")
                        Text(L10n.string("dark")).tag("dark")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text(L10n.string("icloud")), footer: Text(isICloudAvailable ? L10n.string("icloud_sync_footer") : L10n.string("icloud_unavailable"))) {
                    Toggle(L10n.string("icloud_sync_toggle"), isOn: $useCloudSync)
                        .disabled(!isICloudAvailable)
                }
                Section(header: Text(L10n.string("security"))) {
                    Toggle(L10n.string("require_biometrics"), isOn: Binding(
                        get: { useBiometrics },
                        set: { newValue in
                            pendingBiometricsValue = newValue
                            authenticateBiometric { success in
                                if success {
                                    biometricsJustConfirmed = true
                                    useBiometrics = newValue
                                }
                                pendingBiometricsValue = nil
                            }
                        }
                    ))
                    .disabled(pendingBiometricsValue != nil)
                }
                Section(header: Text(L10n.string("api_settings"))) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.string("api_settings_desc"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                        Link(destination: URL(string: "https://snipe-it.readme.io/reference/generating-api-tokens")!) {
                            Text(L10n.string("how_api_key"))
                                .font(.footnote)
                                .foregroundColor(Color.blue)
                                .underline()
                                .padding(.top, 2)
                        }
                    }
                    TextField("Snipe-IT URL (e.g., https://snipeit.yourcompany.com)", text: $baseURL)
                        .autocapitalization(.none)
                        .textContentType(.URL)
                    SecureField("API Key", text: $apiToken)
                        .textContentType(.password)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isPresentedAsTab {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(L10n.string("close")) {
                            let storedToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
                            if apiCredentialsChanged(storedURL: apiClient.baseURL, storedToken: storedToken) {
                                apiClient.saveConfiguration(baseURL: baseURL, apiToken: apiToken)
                            }
                            CloudSettingsStore.shared.pushToCloud()
                            dismiss()
                        }
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .appearance:
                    AppearanceSettingsView(appTheme: $appTheme)
                case .security:
                    SecuritySettingsView(useBiometrics: $useBiometrics)
                case .api:
                    APISettingsView(apiClient: apiClient, baseURL: $baseURL, apiToken: $apiToken, showAlert: $showAlert, alertMessage: $alertMessage)
                }
            }
            .onAppear {
                // Standaard: iCloud-sync aan, behalve als er geen iCloud-account is gekoppeld.
                if !isICloudAvailable {
                    useCloudSync = false
                    UserDefaults.standard.set(false, forKey: "useCloudSync")
                } else if UserDefaults.standard.object(forKey: "useCloudSync") == nil {
                    useCloudSync = true
                    UserDefaults.standard.set(true, forKey: "useCloudSync")
                }
                baseURL = apiClient.baseURL
                apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
            }
            .onChange(of: appTheme) { _, newValue in
                CloudSettingsStore.shared.setAppTheme(newValue)
            }
            .onChange(of: useBiometrics) { _, newValue in
                CloudSettingsStore.shared.setUseBiometrics(newValue)
            }
            .onChange(of: settingsLanguage) { _, newValue in
                CloudSettingsStore.shared.setSettingsLanguage(newValue)
            }
            .onChange(of: useCloudSync) { _, newValue in
                CloudSettingsStore.shared.setUseCloudSync(newValue)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertMessage))
            }
        }
    }

    private func apiCredentialsChanged(storedURL: String, storedToken: String) -> Bool {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed != storedURL || apiToken != storedToken
    }

    private func authenticateBiometric(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        let reason = "Authenticate to change biometric settings"
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        } else {
            completion(false)
        }
    }
}

enum SettingsRoute: Hashable { case appearance, security, api }

struct AppearanceSettingsView: View {
    @Binding var appTheme: String
    var body: some View {
        Form {
            Section(header: Text(L10n.string("theme"))) {
                Picker(L10n.string("theme"), selection: $appTheme) {
                    Text(L10n.string("system")).tag("system")
                    Text(L10n.string("light")).tag("light")
                    Text(L10n.string("dark")).tag("dark")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .navigationTitle(L10n.string("appearance"))
    }
}

struct SecuritySettingsView: View {
    @Binding var useBiometrics: Bool
    var body: some View {
        Form {
            Section(header: Text(L10n.string("security"))) {
                Toggle(L10n.string("require_biometrics"), isOn: $useBiometrics)
            }
        }
        .navigationTitle(L10n.string("security"))
    }
}

struct APISettingsView: View {
    @ObservedObject var apiClient: SnipeITAPIClient
    @Binding var baseURL: String
    @Binding var apiToken: String
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    var body: some View {
        Form {
            Section(header: Text(L10n.string("api_settings"))) {
                TextField("Snipe-IT URL (e.g., https://snipeit.yourcompany.com)", text: $baseURL)
                    .autocapitalization(.none)
                    .textContentType(.URL)
                SecureField("API Key", text: $apiToken)
                    .textContentType(.password)
            }
        }
        .navigationTitle(L10n.string("api_settings"))
        .onAppear {
            baseURL = apiClient.baseURL
            apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        }
    }
} 