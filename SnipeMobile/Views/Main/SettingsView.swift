import SwiftUI
import LocalAuthentication
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var apiClient: SnipeITAPIClient
    /// Shown as tab. No close button.
    var isPresentedAsTab: Bool = false

    @AppStorage("useBiometrics") private var useBiometrics: Bool = false
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("settingsLanguage") private var settingsLanguage: String = "en"
    @AppStorage("biometricsJustConfirmed") private var biometricsJustConfirmed: Bool = false
    @AppStorage("useCloudSync") private var useCloudSync: Bool = true
    @AppStorage("auditNotificationsEnabled") private var auditNotificationsEnabled: Bool = false
    @AppStorage("auditNotificationHour") private var auditNotificationHour: Int = 9
    @AppStorage("auditNotificationMinute") private var auditNotificationMinute: Int = 0
    @AppStorage("enableAuditSubtab") private var enableAuditSubtab: Bool = false
    @AppStorage("showAccessoriesTab") private var showAccessoriesTab: Bool = true
    @AppStorage("showLicensesTab") private var showLicensesTab: Bool = true
    @AppStorage("showConsumablesTab") private var showConsumablesSub: Bool = true
    @AppStorage("showComponentsTab") private var showComponentsSub: Bool = true
    @AppStorage("showMaintenance") private var showMaintenance: Bool = true
    @AppStorage("autoFillAssetTag") private var autoFillAssetTag: Bool = true

    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var path: [SettingsRoute] = []
    @State private var pendingBiometricsValue: Bool? = nil
    @State private var showResetConfirm: Bool = false
    @State private var notificationTime: Date = Date()
    @State private var versionDisplay = AppInfo.versionBase

    /// Device has iCloud.
    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var themeLabel: String {
        switch appTheme {
        case "light": return L10n.string("light")
        case "dark":  return L10n.string("dark")
        default:      return L10n.string("system")
        }
    }

    private var apiStatusLabel: String {
        guard apiClient.isConfigured, !apiClient.baseURL.isEmpty else {
            return L10n.string("settings_not_configured")
        }
        return URL(string: apiClient.baseURL)?.host ?? apiClient.baseURL
    }

    private var auditStatusLabel: String {
        enableAuditSubtab
            ? L10n.string("settings_status_on")
            : L10n.string("settings_status_off")
    }

    private func ensureAssetsLoadedIfNeeded() async {
        guard apiClient.isConfigured else { return }
        if apiClient.assets.isEmpty {
            await apiClient.fetchPrimaryThenBackground()
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                generalSection
                modulesSection
                privacySection
                featuresSection
                connectionSection
                aboutAndResetSection
            }
            .formStyle(.grouped)
            .navigationTitle(L10n.string("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbar }
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .appearance:
                    AppearanceSettingsView(appTheme: $appTheme)
                case .security:
                    SecuritySettingsView(useBiometrics: $useBiometrics)
                case .api:
                    APISettingsView(
                        apiClient: apiClient,
                        baseURL: $baseURL,
                        apiToken: $apiToken,
                        showAlert: $showAlert,
                        alertMessage: $alertMessage
                    )
                case .audit:
                    AuditSettingsView(
                        enableAuditSubtab: $enableAuditSubtab,
                        auditNotificationsEnabled: $auditNotificationsEnabled,
                        notificationTime: $notificationTime
                    )
                case .dell:
                    DellSettingsView()
                case .assets:
                    AssetSettingsView(autoFillAssetTag: $autoFillAssetTag)
                case .modules:
                    ModulesSettingsView(
                        showAccessoriesTab: $showAccessoriesTab,
                        showLicensesTab: $showLicensesTab,
                        showConsumablesSub: $showConsumablesSub,
                        showComponentsSub: $showComponentsSub
                    )
                }
            }
            .onAppear(perform: handleOnAppear)
            .task {
                let channel = await AppInfo.resolveChannel()
                versionDisplay = AppInfo.versionAndBuild(channel: channel)
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
            .onChange(of: autoFillAssetTag) { _, newValue in
                CloudSettingsStore.shared.setAutoFillAssetTag(newValue)
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
            .alert(
                L10n.string("reset_data_confirm_title"),
                isPresented: $showResetConfirm
            ) {
                Button(L10n.string("cancel"), role: .cancel) {}
                Button(L10n.string("reset_data_confirm_action"), role: .destructive) {
                    // SnipeITAPIClient reacts to `.appDataDidWipe` posted by wipeAllData.
                    CloudSettingsStore.shared.wipeAllData()
                }
            } message: {
                Text(L10n.string("reset_data_confirm_message"))
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.appearance) {
                SettingsRow(
                    icon: "paintbrush.fill",
                    iconColor: .purple,
                    title: L10n.string("appearance"),
                    value: themeLabel
                )
            }
        }
    }

    private var enabledModuleCount: Int {
        var count = 0
        if showAccessoriesTab { count += 1 }
        if showLicensesTab { count += 1 }
        if showConsumablesSub { count += 1 }
        if showComponentsSub { count += 1 }
        return count
    }

    private var modulesSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.modules) {
                SettingsRow(
                    icon: "square.grid.2x2.fill",
                    iconColor: .orange,
                    title: L10n.string("settings_modules"),
                    value: L10n.string("settings_modules_count", enabledModuleCount)
                )
            }
        }
    }

    private var privacySection: some View {
        Section {
            SettingsToggleRow(
                icon: "icloud.fill",
                iconColor: .blue,
                title: L10n.string("icloud_sync_toggle"),
                isOn: $useCloudSync
            )
            .disabled(!isICloudAvailable)

            SettingsToggleRow(
                icon: "faceid",
                iconColor: .indigo,
                title: L10n.string("require_biometrics"),
                isOn: Binding(
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
                )
            )
            .disabled(pendingBiometricsValue != nil)
        } header: {
            Text(L10n.string("settings_privacy"))
        } footer: {
            if !isICloudAvailable {
                Text(L10n.string("icloud_unavailable"))
            }
        }
    }

    private var connectionSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.api) {
                SettingsRow(
                    icon: "antenna.radiowaves.left.and.right",
                    iconColor: .green,
                    title: L10n.string("api_settings_short"),
                    value: apiStatusLabel
                )
            }
            NavigationLink(value: SettingsRoute.dell) {
                SettingsRow(
                    icon: "desktopcomputer",
                    iconColor: .gray,
                    title: L10n.string("settings_dell"),
                    value: nil
                )
            }
        } header: {
            Text(L10n.string("settings_connection"))
        } footer: {
            Text(L10n.string("connection_section_footer"))
        }
    }

    private var featuresSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.assets) {
                SettingsRow(
                    icon: "barcode",
                    iconColor: .blue,
                    title: L10n.string("settings_assets"),
                    value: nil
                )
            }
            NavigationLink(value: SettingsRoute.audit) {
                SettingsRow(
                    icon: "bell.badge.fill",
                    iconColor: .red,
                    title: L10n.string("settings_audit_short"),
                    value: auditStatusLabel
                )
            }
            SettingsToggleRow(
                icon: "wrench.and.screwdriver.fill",
                iconColor: .teal,
                title: L10n.string("settings_maintenance"),
                isOn: $showMaintenance
            )
        } header: {
            Text(L10n.string("settings_features"))
        } footer: {
            Text(L10n.string("settings_maintenance_footer"))
        }
    }

    private var aboutAndResetSection: some View {
        Section {
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: .gray,
                title: L10n.string("settings_version"),
                value: versionDisplay
            )
            if let githubURL = URL(string: "https://github.com/Callandt/SnipeMobile") {
                Link(destination: githubURL) {
                    HStack(spacing: 12) {
                        SettingsRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            iconColor: .black,
                            title: L10n.string("settings_source_code"),
                            value: "GitHub"
                        )
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                SettingsRow(
                    icon: "trash.fill",
                    iconColor: .red,
                    title: L10n.string("reset_data_button"),
                    value: nil,
                    titleColor: .red
                )
            }
        } header: {
            Text(L10n.string("settings_about"))
        } footer: {
            Text(L10n.string("reset_data_footer_short"))
        }
    }

    @ToolbarContentBuilder
    private var closeToolbar: some ToolbarContent {
        if !isPresentedAsTab {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(L10n.string("close")) {
                    let storedToken = KeychainSecretStore.string(for: .apiToken)
                    if apiCredentialsChanged(storedURL: apiClient.baseURL, storedToken: storedToken) {
                        apiClient.saveConfiguration(baseURL: baseURL, apiToken: apiToken)
                    }
                    CloudSettingsStore.shared.pushToCloud()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Lifecycle / helpers

    private func handleOnAppear() {
        // iCloud sync on by default if account present.
        if !isICloudAvailable {
            useCloudSync = false
            UserDefaults.standard.set(false, forKey: "useCloudSync")
        } else if UserDefaults.standard.object(forKey: "useCloudSync") == nil {
            useCloudSync = true
            UserDefaults.standard.set(true, forKey: "useCloudSync")
        }
        baseURL = apiClient.baseURL
        apiToken = KeychainSecretStore.string(for: .apiToken)

        let cal = Calendar.current
        notificationTime = cal.date(
            bySettingHour: auditNotificationHour,
            minute: auditNotificationMinute,
            second: 0,
            of: Date()
        ) ?? Date()
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

enum SettingsRoute: Hashable { case appearance, security, api, audit, dell, modules, assets }

// MARK: - Reusable building blocks (iOS Settings.app style)

/// Rounded square icon like the iOS Settings app.
private struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(color.gradient)
            .frame(width: 29, height: 29)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// App version, build, and distribution channel.
enum AppInfo {
    enum Channel: String {
        case appStore = "App Store"
        case testFlight = "TestFlight"
        case debug = "Debug"
    }

    /// e.g. "1.2.3"
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// e.g. "42" (CFBundleVersion, increments per TestFlight build).
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    /// Resolves the distribution channel via StoreKit. Cached after first call.
    static func resolveChannel() async -> Channel {
        #if DEBUG
        return .debug
        #else
        if let cachedChannel { return cachedChannel }
        let resolved = await channelFromStoreKit()
        cachedChannel = resolved
        return resolved
        #endif
    }

    /// Version + build, no channel suffix.
    static var versionBase: String {
        build.isEmpty ? version : "\(version) (\(build))"
    }

    /// e.g. "1.2.3 (42) · TestFlight".
    static func versionAndBuild(channel: Channel) -> String {
        "\(versionBase) · \(channel.rawValue)"
    }

    private static var cachedChannel: Channel?

    private static func channelFromStoreKit() async -> Channel {
        do {
            let result = try await AppTransaction.shared
            let environment: AppStore.Environment
            switch result {
            case .verified(let transaction):
                environment = transaction.environment
            case .unverified(let transaction, _):
                environment = transaction.environment
            }
            return mapEnvironment(environment)
        } catch {
            return .debug
        }
    }

    private static func mapEnvironment(_ environment: AppStore.Environment) -> Channel {
        switch environment {
        case .production:
            return .appStore
        case .sandbox:
            return .testFlight
        case .xcode:
            return .debug
        default:
            return .debug
        }
    }
}

/// Row with a colored icon, title, and optional trailing value.
private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil
    var titleColor: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: icon, color: iconColor)
            Text(title)
                .foregroundStyle(titleColor)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// Toggle row with a colored icon.
private struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: icon, color: iconColor)
                Text(title)
            }
        }
    }
}

// MARK: - Detail views

struct AppearanceSettingsView: View {
    @Binding var appTheme: String

    var body: some View {
        Form {
            Section {
                Picker(L10n.string("theme"), selection: $appTheme) {
                    Text(L10n.string("system")).tag("system")
                    Text(L10n.string("light")).tag("light")
                    Text(L10n.string("dark")).tag("dark")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(L10n.string("theme"))
            }
        }
        .navigationTitle(L10n.string("appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SecuritySettingsView: View {
    @Binding var useBiometrics: Bool

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("require_biometrics"), isOn: $useBiometrics)
            } header: {
                Text(L10n.string("security"))
            }
        }
        .navigationTitle(L10n.string("security"))
        .navigationBarTitleDisplayMode(.inline)
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
            Section {
                TextField("https://snipeit.yourcompany.com", text: $baseURL)
                    .autocapitalization(.none)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                SecureField(L10n.string("dell_client_id"), text: $apiToken)
                    .textContentType(.password)
            } header: {
                Text(L10n.string("api_settings"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("api_settings_desc"))
                    Link(destination: URL(string: "https://snipe-it.readme.io/reference/generating-api-tokens")!) {
                        Text(L10n.string("how_api_key"))
                            .font(.footnote.weight(.medium))
                    }
                }
            }
        }
        .navigationTitle(L10n.string("api_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            baseURL = apiClient.baseURL
            apiToken = KeychainSecretStore.string(for: .apiToken)
        }
    }
}

struct AuditSettingsView: View {
    @Binding var enableAuditSubtab: Bool
    @Binding var auditNotificationsEnabled: Bool
    @Binding var notificationTime: Date

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("audit_subtab_toggle"), isOn: $enableAuditSubtab)
            } footer: {
                Text(L10n.string("audit_settings_compact_footer"))
            }

            Section {
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
        }
        .navigationTitle(L10n.string("audit_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ModulesSettingsView: View {
    @Binding var showAccessoriesTab: Bool
    @Binding var showLicensesTab: Bool
    @Binding var showConsumablesSub: Bool
    @Binding var showComponentsSub: Bool

    var body: some View {
        List {
            Section {
                Toggle(isOn: $showAccessoriesTab) {
                    Label(L10n.string("tab_accessories"), systemImage: "mediastick")
                }

                Toggle(isOn: $showLicensesTab) {
                    Label(L10n.string("tab_licenses"), systemImage: "doc.text.fill")
                }
            } header: {
                Text(L10n.string("settings_modules_tabs_header"))
            } footer: {
                Text(L10n.string("settings_modules_tabs_footer"))
            }

            Section {
                Toggle(isOn: $showConsumablesSub) {
                    Label(L10n.string("tab_consumables"), systemImage: "shippingbox.fill")
                }
                Toggle(isOn: $showComponentsSub) {
                    Label(L10n.string("tab_components"), systemImage: "cpu")
                }
            } header: {
                Text(L10n.string("tab_stock"))
            } footer: {
                Text(L10n.string("settings_modules_stock_footer"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.string("settings_modules"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AssetSettingsView: View {
    @Binding var autoFillAssetTag: Bool

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("auto_fill_asset_tag_toggle"), isOn: $autoFillAssetTag)
            } header: {
                Text(L10n.string("settings_assets_creation_header"))
            } footer: {
                Text(L10n.string("auto_fill_asset_tag_footer"))
            }
        }
        .navigationTitle(L10n.string("settings_assets"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DellSettingsView: View {
    @AppStorage("enableDellQrScan") private var enableDellQrScan: Bool = true
    @State private var dellTechDirectClientId: String = ""
    @State private var dellTechDirectClientSecret: String = ""

    var body: some View {
        Form {
            Section {
                Toggle(L10n.string("dell_qr_scan_toggle"), isOn: $enableDellQrScan)
            } header: {
                Text(L10n.string("scanning"))
            } footer: {
                Text(L10n.string("dell_qr_scan_footer"))
            }

            Section {
                TextField(L10n.string("dell_client_id"), text: $dellTechDirectClientId)
                    .textContentType(.username)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                SecureField(L10n.string("dell_client_secret"), text: $dellTechDirectClientSecret)
                    .textContentType(.password)
            } header: {
                Text(L10n.string("dell_techdirect_api"))
            } footer: {
                Text(L10n.string("dell_techdirect_footer"))
            }
        }
        .navigationTitle(L10n.string("dell_settings_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dellTechDirectClientId = KeychainSecretStore.string(for: .dellTechDirectClientId)
            dellTechDirectClientSecret = KeychainSecretStore.string(for: .dellTechDirectClientSecret)
        }
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
