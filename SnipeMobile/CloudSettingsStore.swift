//
//  CloudSettingsStore.swift
//  SnipeMobile
//
//  iCloud sync for API config and onboarding. New devices get same setup.
//

import Foundation

/// iCloud KV keys we sync.
private enum CloudKey: String, CaseIterable {
    case baseURL
    case apiToken
    case isConfigured
    case hasCompletedOnboarding
    case appTheme
    case useBiometrics
    case appLanguage
    case settingsLanguage
    case biometricsJustConfirmed
    case enableDellQrScan
    case dellTechDirectClientId
    case dellTechDirectClientSecret
}

private let useCloudSyncKey = "useCloudSync"

final class CloudSettingsStore {
    static let shared = CloudSettingsStore()

    private let store = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// iCloud sync on. Default true.
    var useCloudSync: Bool {
        defaults.object(forKey: useCloudSyncKey) as? Bool ?? true
    }

    /// Has iCloud account. Avoids no-account errors.
    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Toggle iCloud sync. Off clears synced keys.
    func setUseCloudSync(_ enabled: Bool) {
        defaults.set(enabled, forKey: useCloudSyncKey)
        guard isICloudAvailable else { return }
        if !enabled {
            // Clear iCloud keys.
            for key in CloudKey.allCases {
                store.removeObject(forKey: key.rawValue)
            }
            _ = store.synchronize()
        } else {
            // Push local values to iCloud.
            copyRelevantDefaultsToStore()
            _ = store.synchronize()
        }
    }

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquitousStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
    }

    /// Pull iCloud into UserDefaults at launch. New device gets synced config.
    func mergeFromCloud() {
        guard useCloudSync, isICloudAvailable else { return }
        _ = store.synchronize()
        mergeCloudValuesIntoUserDefaults()
    }

    /// Push UserDefaults to iCloud. Call after saving API config.
    func pushToCloud() {
        guard useCloudSync, isICloudAvailable else { return }
        copyRelevantDefaultsToStore()
        _ = store.synchronize()
    }

    // MARK: - API config

    func writeAPIConfiguration(baseURL: String, apiToken: String, isConfigured: Bool) {
        defaults.set(baseURL, forKey: "baseURL")
        defaults.set(apiToken, forKey: "apiToken")
        defaults.set(isConfigured, forKey: "isConfigured")
        if useCloudSync, isICloudAvailable {
            store.set(baseURL, forKey: CloudKey.baseURL.rawValue)
            store.set(apiToken, forKey: CloudKey.apiToken.rawValue)
            store.set(isConfigured, forKey: CloudKey.isConfigured.rawValue)
            _ = store.synchronize()
        }
    }

    func setHasCompletedOnboarding(_ value: Bool) {
        defaults.set(value, forKey: "hasCompletedOnboarding")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.hasCompletedOnboarding.rawValue)
            _ = store.synchronize()
        }
    }

    // MARK: - App settings

    func setAppTheme(_ value: String) {
        defaults.set(value, forKey: "appTheme")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.appTheme.rawValue)
            _ = store.synchronize()
        }
    }

    func setUseBiometrics(_ value: Bool) {
        defaults.set(value, forKey: "useBiometrics")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.useBiometrics.rawValue)
            _ = store.synchronize()
        }
    }

    func setAppLanguage(_ value: String) {
        defaults.set(value, forKey: "appLanguage")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.appLanguage.rawValue)
            _ = store.synchronize()
        }
    }

    func setSettingsLanguage(_ value: String) {
        defaults.set(value, forKey: "settingsLanguage")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.settingsLanguage.rawValue)
            _ = store.synchronize()
        }
    }

    func setBiometricsJustConfirmed(_ value: Bool) {
        defaults.set(value, forKey: "biometricsJustConfirmed")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.biometricsJustConfirmed.rawValue)
            _ = store.synchronize()
        }
    }

    func setEnableDellQrScan(_ value: Bool) {
        defaults.set(value, forKey: "enableDellQrScan")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.enableDellQrScan.rawValue)
            _ = store.synchronize()
        }
    }

    func setDellTechDirectClientId(_ value: String) {
        defaults.set(value, forKey: "dellTechDirectClientId")
        if useCloudSync, isICloudAvailable {
            if value.isEmpty { store.removeObject(forKey: CloudKey.dellTechDirectClientId.rawValue) }
            else { store.set(value, forKey: CloudKey.dellTechDirectClientId.rawValue) }
            _ = store.synchronize()
        }
    }

    func setDellTechDirectClientSecret(_ value: String) {
        defaults.set(value, forKey: "dellTechDirectClientSecret")
        if useCloudSync, isICloudAvailable {
            if value.isEmpty { store.removeObject(forKey: CloudKey.dellTechDirectClientSecret.rawValue) }
            else { store.set(value, forKey: CloudKey.dellTechDirectClientSecret.rawValue) }
            _ = store.synchronize()
        }
    }

    // MARK: - Private

    private func mergeCloudValuesIntoUserDefaults() {
        guard useCloudSync, isICloudAvailable else { return }
        if let v = store.string(forKey: CloudKey.baseURL.rawValue), !v.isEmpty {
            defaults.set(v, forKey: "baseURL")
        }
        if let v = store.string(forKey: CloudKey.apiToken.rawValue), !v.isEmpty {
            defaults.set(v, forKey: "apiToken")
        }
        if store.object(forKey: CloudKey.isConfigured.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.isConfigured.rawValue), forKey: "isConfigured")
        }
        if store.object(forKey: CloudKey.hasCompletedOnboarding.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.hasCompletedOnboarding.rawValue), forKey: "hasCompletedOnboarding")
        }
        if let v = store.string(forKey: CloudKey.appTheme.rawValue) {
            defaults.set(v, forKey: "appTheme")
        }
        if store.object(forKey: CloudKey.useBiometrics.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.useBiometrics.rawValue), forKey: "useBiometrics")
        }
        if let v = store.string(forKey: CloudKey.appLanguage.rawValue) {
            defaults.set(v, forKey: "appLanguage")
        }
        if let v = store.string(forKey: CloudKey.settingsLanguage.rawValue) {
            defaults.set(v, forKey: "settingsLanguage")
        }
        if store.object(forKey: CloudKey.biometricsJustConfirmed.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.biometricsJustConfirmed.rawValue), forKey: "biometricsJustConfirmed")
        }
        if store.object(forKey: CloudKey.enableDellQrScan.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.enableDellQrScan.rawValue), forKey: "enableDellQrScan")
        }
        if let v = store.string(forKey: CloudKey.dellTechDirectClientId.rawValue) {
            defaults.set(v, forKey: "dellTechDirectClientId")
        }
        if let v = store.string(forKey: CloudKey.dellTechDirectClientSecret.rawValue) {
            defaults.set(v, forKey: "dellTechDirectClientSecret")
        }
    }

    private func copyRelevantDefaultsToStore() {
        guard useCloudSync, isICloudAvailable else { return }
        if let v = defaults.string(forKey: "baseURL") { store.set(v, forKey: CloudKey.baseURL.rawValue) }
        if let v = defaults.string(forKey: "apiToken") { store.set(v, forKey: CloudKey.apiToken.rawValue) }
        store.set(defaults.bool(forKey: "isConfigured"), forKey: CloudKey.isConfigured.rawValue)
        store.set(defaults.bool(forKey: "hasCompletedOnboarding"), forKey: CloudKey.hasCompletedOnboarding.rawValue)
        if let v = defaults.string(forKey: "appTheme") { store.set(v, forKey: CloudKey.appTheme.rawValue) }
        store.set(defaults.bool(forKey: "useBiometrics"), forKey: CloudKey.useBiometrics.rawValue)
        if let v = defaults.string(forKey: "appLanguage") { store.set(v, forKey: CloudKey.appLanguage.rawValue) }
        if let v = defaults.string(forKey: "settingsLanguage") { store.set(v, forKey: CloudKey.settingsLanguage.rawValue) }
        store.set(defaults.bool(forKey: "biometricsJustConfirmed"), forKey: CloudKey.biometricsJustConfirmed.rawValue)
        store.set(defaults.object(forKey: "enableDellQrScan") as? Bool ?? true, forKey: CloudKey.enableDellQrScan.rawValue)
        if let v = defaults.string(forKey: "dellTechDirectClientId") { store.set(v, forKey: CloudKey.dellTechDirectClientId.rawValue) }
        if let v = defaults.string(forKey: "dellTechDirectClientSecret") { store.set(v, forKey: CloudKey.dellTechDirectClientSecret.rawValue) }
    }

    @objc private func ubiquitousStoreDidChange(_ notification: Notification) {
        guard useCloudSync, isICloudAvailable else { return }
        mergeCloudValuesIntoUserDefaults()
        // UI refresh.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let cloudSettingsDidChange = Notification.Name("cloudSettingsDidChange")
}
