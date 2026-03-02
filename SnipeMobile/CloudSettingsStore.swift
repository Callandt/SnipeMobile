//
//  CloudSettingsStore.swift
//  SnipeMobile
//
//  Syncs API settings and onboarding state to iCloud so new devices (e.g. iPad)
//  get the same config and skip the welcome/API setup. Data is encrypted by Apple.
//

import Foundation

/// Keys we sync to iCloud Key-Value storage (encrypted by Apple).
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
}

final class CloudSettingsStore {
    static let shared = CloudSettingsStore()

    private let store = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquitousStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
    }

    /// Call once at app launch to pull iCloud values into UserDefaults so existing
    /// @AppStorage / UserDefaults code sees synced data (e.g. on a new iPad).
    func mergeFromCloud() {
        _ = store.synchronize()
        mergeCloudValuesIntoUserDefaults()
    }

    /// Push current UserDefaults values to iCloud (e.g. after saving API config).
    func pushToCloud() {
        copyRelevantDefaultsToStore()
        _ = store.synchronize()
    }

    // MARK: - API configuration (used by SnipeITAPIClient and onboarding)

    func writeAPIConfiguration(baseURL: String, apiToken: String, isConfigured: Bool) {
        defaults.set(baseURL, forKey: "baseURL")
        defaults.set(apiToken, forKey: "apiToken")
        defaults.set(isConfigured, forKey: "isConfigured")
        store.set(baseURL, forKey: CloudKey.baseURL.rawValue)
        store.set(apiToken, forKey: CloudKey.apiToken.rawValue)
        store.set(isConfigured, forKey: CloudKey.isConfigured.rawValue)
        _ = store.synchronize()
    }

    func setHasCompletedOnboarding(_ value: Bool) {
        defaults.set(value, forKey: "hasCompletedOnboarding")
        store.set(value, forKey: CloudKey.hasCompletedOnboarding.rawValue)
        _ = store.synchronize()
    }

    // MARK: - App settings (theme, biometrics, language) – keep in sync with UserDefaults

    func setAppTheme(_ value: String) {
        defaults.set(value, forKey: "appTheme")
        store.set(value, forKey: CloudKey.appTheme.rawValue)
        _ = store.synchronize()
    }

    func setUseBiometrics(_ value: Bool) {
        defaults.set(value, forKey: "useBiometrics")
        store.set(value, forKey: CloudKey.useBiometrics.rawValue)
        _ = store.synchronize()
    }

    func setAppLanguage(_ value: String) {
        defaults.set(value, forKey: "appLanguage")
        store.set(value, forKey: CloudKey.appLanguage.rawValue)
        _ = store.synchronize()
    }

    func setSettingsLanguage(_ value: String) {
        defaults.set(value, forKey: "settingsLanguage")
        store.set(value, forKey: CloudKey.settingsLanguage.rawValue)
        _ = store.synchronize()
    }

    func setBiometricsJustConfirmed(_ value: Bool) {
        defaults.set(value, forKey: "biometricsJustConfirmed")
        store.set(value, forKey: CloudKey.biometricsJustConfirmed.rawValue)
        _ = store.synchronize()
    }

    // MARK: - Private

    private func mergeCloudValuesIntoUserDefaults() {
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
    }

    private func copyRelevantDefaultsToStore() {
        if let v = defaults.string(forKey: "baseURL") { store.set(v, forKey: CloudKey.baseURL.rawValue) }
        if let v = defaults.string(forKey: "apiToken") { store.set(v, forKey: CloudKey.apiToken.rawValue) }
        store.set(defaults.bool(forKey: "isConfigured"), forKey: CloudKey.isConfigured.rawValue)
        store.set(defaults.bool(forKey: "hasCompletedOnboarding"), forKey: CloudKey.hasCompletedOnboarding.rawValue)
        if let v = defaults.string(forKey: "appTheme") { store.set(v, forKey: CloudKey.appTheme.rawValue) }
        store.set(defaults.bool(forKey: "useBiometrics"), forKey: CloudKey.useBiometrics.rawValue)
        if let v = defaults.string(forKey: "appLanguage") { store.set(v, forKey: CloudKey.appLanguage.rawValue) }
        if let v = defaults.string(forKey: "settingsLanguage") { store.set(v, forKey: CloudKey.settingsLanguage.rawValue) }
        store.set(defaults.bool(forKey: "biometricsJustConfirmed"), forKey: CloudKey.biometricsJustConfirmed.rawValue)
    }

    @objc private func ubiquitousStoreDidChange(_ notification: Notification) {
        mergeCloudValuesIntoUserDefaults()
        // Notify so UI can refresh (e.g. apiClient.isConfigured)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let cloudSettingsDidChange = Notification.Name("cloudSettingsDidChange")
}
