import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var apiClient: SnipeITAPIClient
    /// Shown as tab. No close button.
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
    @AppStorage("auditNotificationsEnabled") private var auditNotificationsEnabled: Bool = false
    @AppStorage("auditNotificationHour") private var auditNotificationHour: Int = 9
    @AppStorage("auditNotificationMinute") private var auditNotificationMinute: Int = 0
    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = true
    @State private var notificationTime: Date = Date()
    /// Device has iCloud.
    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func ensureAssetsLoadedIfNeeded() async {
        guard apiClient.isConfigured else { return }
        if apiClient.assets.isEmpty {
            await apiClient.fetchPrimaryThenBackground()
        }
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
                Section(header: Text(L10n.string("audit_settings_title"))) {
                    Toggle(L10n.string("audit_subtab_toggle"), isOn: $enableAuditSubtab)

                    Toggle(
                        L10n.string("audit_notifications_toggle"),
                        isOn: $auditNotificationsEnabled
                    )
                    .disabled(!enableAuditSubtab)

                    DatePicker(
                        L10n.string("audit_notification_time"),
                        selection: $notificationTime,
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!enableAuditSubtab || !auditNotificationsEnabled)
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

                Section(header: Text(L10n.string("settings_brand_integrations"))) {
                    NavigationLink(value: SettingsRoute.dell) {
                        Label(L10n.string("settings_dell"), systemImage: "desktopcomputer")
                    }
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
                case .dell:
                    DellSettingsView()
                }
            }
            .onAppear {
                // iCloud sync on by default if account present.
                if !isICloudAvailable {
                    useCloudSync = false
                    UserDefaults.standard.set(false, forKey: "useCloudSync")
                } else if UserDefaults.standard.object(forKey: "useCloudSync") == nil {
                    useCloudSync = true
                    UserDefaults.standard.set(true, forKey: "useCloudSync")
                }
                baseURL = apiClient.baseURL
                apiToken = UserDefaults.standard.string(forKey: "apiToken") ?? ""

                let cal = Calendar.current
                notificationTime = cal.date(
                    bySettingHour: auditNotificationHour,
                    minute: auditNotificationMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
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
            .onChange(of: enableAuditSubtab) { _, newValue in
                // Notifications only make sense when the Audit subtab is visible.
                if !newValue, auditNotificationsEnabled {
                    auditNotificationsEnabled = false
                    Task {
                        await AuditNotificationManager.shared.updateSchedule(
                            enabled: false,
                            hour: auditNotificationHour,
                            minute: auditNotificationMinute,
                            assets: apiClient.assets
                        )
                    }
                }
            }
            .onChange(of: notificationTime) { _, newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                auditNotificationHour = comps.hour ?? 9
                auditNotificationMinute = comps.minute ?? 0
            }
            .onChange(of: auditNotificationsEnabled) { _, _ in
                // block notifications if the subtab is off
                if !enableAuditSubtab, auditNotificationsEnabled {
                    auditNotificationsEnabled = false
                    return
                }
                Task {
                    await ensureAssetsLoadedIfNeeded()
                    await AuditNotificationManager.shared.updateSchedule(
                        enabled: auditNotificationsEnabled,
                        hour: auditNotificationHour,
                        minute: auditNotificationMinute,
                        assets: apiClient.assets
                    )
                }
            }
            .onChange(of: auditNotificationHour) { _, _ in
                guard auditNotificationsEnabled else { return }
                Task {
                    await ensureAssetsLoadedIfNeeded()
                    await AuditNotificationManager.shared.updateSchedule(
                        enabled: true,
                        hour: auditNotificationHour,
                        minute: auditNotificationMinute,
                        assets: apiClient.assets
                    )
                }
            }
            .onChange(of: auditNotificationMinute) { _, _ in
                guard auditNotificationsEnabled else { return }
                Task {
                    await ensureAssetsLoadedIfNeeded()
                    await AuditNotificationManager.shared.updateSchedule(
                        enabled: true,
                        hour: auditNotificationHour,
                        minute: auditNotificationMinute,
                        assets: apiClient.assets
                    )
                }
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

enum SettingsRoute: Hashable { case appearance, security, api, dell }

struct DellSettingsView: View {
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true
    @AppStorage("dellTechDirectClientId") private var dellTechDirectClientId: String = ""
    @AppStorage("dellTechDirectClientSecret") private var dellTechDirectClientSecret: String = ""

    var body: some View {
        Form {
            Section(header: Text(L10n.string("scanning")), footer: Text(L10n.string("dell_qr_scan_footer"))) {
                Toggle(L10n.string("dell_qr_scan_toggle"), isOn: $enableDellQrScan)
            }
            Section(header: Text(L10n.string("dell_techdirect_api")), footer: Text(L10n.string("dell_techdirect_footer"))) {
                TextField(L10n.string("dell_client_id"), text: $dellTechDirectClientId)
                    .textContentType(.username)
                    .autocapitalization(.none)
                SecureField(L10n.string("dell_client_secret"), text: $dellTechDirectClientSecret)
                    .textContentType(.password)
            }
        }
        .navigationTitle(L10n.string("dell_settings_title"))
        .onChange(of: enableDellQrScan) { _, newValue in
            CloudSettingsStore.shared.setEnableDellQrScan(newValue)
        }
        .onChange(of: dellTechDirectClientId) { _, newValue in
            CloudSettingsStore.shared.setDellTechDirectClientId(newValue)
        }
        .onChange(of: dellTechDirectClientSecret) { _, newValue in
            CloudSettingsStore.shared.setDellTechDirectClientSecret(newValue)
        }
    }
}

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
