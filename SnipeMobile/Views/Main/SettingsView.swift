import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var apiClient: SnipeITAPIClient
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

    var isDutch: Bool { settingsLanguage == "nl" }
    var isEnglish: Bool { settingsLanguage == "en" }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appTheme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text("Security")) {
                    Toggle("Require biometrics at launch", isOn: Binding(
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
                Section(header: Text("API Settings")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter your Snipe-IT API URL and API Key to sync your assets.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                        Link(destination: URL(string: "https://snipe-it.readme.io/reference/generating-api-tokens")!) {
                            Text("How to generate an API key?")
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
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
                baseURL = apiClient.baseURL
                apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
            }
            .onDisappear {
                Task {
                    if let error = await apiClient.validateApiCredentials() {
                        alertMessage = error
                        showAlert = true
                    } else {
                        apiClient.saveConfiguration(baseURL: baseURL, apiToken: apiToken)
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertMessage))
            }
        }
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
            Section(header: Text("Theme")) {
                Picker("Theme", selection: $appTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }
        .navigationTitle("Appearance")
    }
}

struct SecuritySettingsView: View {
    @Binding var useBiometrics: Bool
    var body: some View {
        Form {
            Section(header: Text("Security")) {
                Toggle("Require biometrics at launch", isOn: $useBiometrics)
            }
        }
        .navigationTitle("Security")
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
            Section(header: Text("API Settings")) {
                TextField("Snipe-IT URL (e.g., https://snipeit.yourcompany.com)", text: $baseURL)
                    .autocapitalization(.none)
                    .textContentType(.URL)
                SecureField("API Key", text: $apiToken)
                    .textContentType(.password)
            }
        }
        .navigationTitle("API Settings")
        .onAppear {
            baseURL = apiClient.baseURL
            apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""
        }
    }
} 