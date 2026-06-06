//
//  CloudSettingsStore.swift
//  SnipeMobile
//
//  iCloud sync for API config and onboarding. New devices get same setup.
//

import Foundation
import UserNotifications

/// iCloud KV keys we sync.
private enum CloudKey: String, CaseIterable {
    case baseURL
    case apiToken
    case isConfigured
    case hasCompletedOnboarding
    case hasSeenModulesIntro
    case tabOrder
    case appTheme
    case useBiometrics
    case appLanguage
    case settingsLanguage
    case biometricsJustConfirmed
    case enableDellQrScan
    case autoFillAssetTag
    case dellTechDirectClientId
    case dellTechDirectClientSecret
    /// Unix timestamp of last wipe. Other devices mirror it locally.
    case lastWipeAt
}

private let useCloudSyncKey = "useCloudSync"
private let lastSeenWipeAtKey = "lastSeenWipeAt"

final class CloudSettingsStore {
    static let shared = CloudSettingsStore()

    // Lazy: no KVS touch without iCloud (avoids "No account" log spam).
    private lazy var store = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard

    /// iCloud sync on. Default true.
    var useCloudSync: Bool {
        defaults.object(forKey: useCloudSyncKey) as? Bool ?? true
    }

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
        guard isICloudAvailable else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ubiquitousStoreDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )
    }

    func mergeFromCloud() {
        guard useCloudSync, isICloudAvailable else { return }
        _ = store.synchronize()
        mergeCloudValuesIntoUserDefaults()
    }

    func pushToCloud() {
        guard useCloudSync, isICloudAvailable else { return }
        copyRelevantDefaultsToStore()
        _ = store.synchronize()
    }

    // MARK: - API config

    func writeAPIConfiguration(baseURL: String, apiToken: String, isConfigured: Bool) {
        defaults.set(baseURL, forKey: "baseURL")
        KeychainSecretStore.set(apiToken, for: .apiToken)
        defaults.removeObject(forKey: "apiToken")
        defaults.set(isConfigured, forKey: "isConfigured")
        if useCloudSync, isICloudAvailable {
            store.set(baseURL, forKey: CloudKey.baseURL.rawValue)
            store.removeObject(forKey: CloudKey.apiToken.rawValue)
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

    func setHasSeenModulesIntro(_ value: Bool) {
        defaults.set(value, forKey: "hasSeenModulesIntro")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.hasSeenModulesIntro.rawValue)
            _ = store.synchronize()
        }
    }

    func setTabOrder(_ value: String) {
        defaults.set(value, forKey: "tabOrder")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.tabOrder.rawValue)
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

    func setAutoFillAssetTag(_ value: Bool) {
        defaults.set(value, forKey: "autoFillAssetTag")
        if useCloudSync, isICloudAvailable {
            store.set(value, forKey: CloudKey.autoFillAssetTag.rawValue)
            _ = store.synchronize()
        }
    }

    func setDellTechDirectClientId(_ value: String) {
        KeychainSecretStore.set(value, for: .dellTechDirectClientId)
        defaults.removeObject(forKey: "dellTechDirectClientId")
        if useCloudSync, isICloudAvailable {
            store.removeObject(forKey: CloudKey.dellTechDirectClientId.rawValue)
            _ = store.synchronize()
        }
    }

    func setDellTechDirectClientSecret(_ value: String) {
        KeychainSecretStore.set(value, for: .dellTechDirectClientSecret)
        defaults.removeObject(forKey: "dellTechDirectClientSecret")
        if useCloudSync, isICloudAvailable {
            store.removeObject(forKey: CloudKey.dellTechDirectClientSecret.rawValue)
            _ = store.synchronize()
        }
    }

    // MARK: - Private

    private func mergeCloudValuesIntoUserDefaults() {
        guard useCloudSync, isICloudAvailable else { return }

        // Mirror a remote wipe before merging anything else.
        let cloudWipeAt = store.double(forKey: CloudKey.lastWipeAt.rawValue)
        let localSeenWipeAt = defaults.double(forKey: lastSeenWipeAtKey)
        if cloudWipeAt > 0, cloudWipeAt > localSeenWipeAt {
            performLocalWipe(rememberWipeAt: cloudWipeAt)
            return
        }

        if let v = store.string(forKey: CloudKey.baseURL.rawValue), !v.isEmpty {
            defaults.set(v, forKey: "baseURL")
        }
        if let v = store.string(forKey: CloudKey.apiToken.rawValue), !v.isEmpty {
            KeychainSecretStore.set(v, for: .apiToken)
            defaults.removeObject(forKey: "apiToken")
            store.removeObject(forKey: CloudKey.apiToken.rawValue)
        }
        if store.object(forKey: CloudKey.isConfigured.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.isConfigured.rawValue), forKey: "isConfigured")
        }
        if store.object(forKey: CloudKey.hasCompletedOnboarding.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.hasCompletedOnboarding.rawValue), forKey: "hasCompletedOnboarding")
        }
        if store.object(forKey: CloudKey.hasSeenModulesIntro.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.hasSeenModulesIntro.rawValue), forKey: "hasSeenModulesIntro")
        }
        if let v = store.string(forKey: CloudKey.tabOrder.rawValue) {
            defaults.set(v, forKey: "tabOrder")
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
        if store.object(forKey: CloudKey.autoFillAssetTag.rawValue) != nil {
            defaults.set(store.bool(forKey: CloudKey.autoFillAssetTag.rawValue), forKey: "autoFillAssetTag")
        }
        if let v = store.string(forKey: CloudKey.dellTechDirectClientId.rawValue) {
            KeychainSecretStore.set(v, for: .dellTechDirectClientId)
            defaults.removeObject(forKey: "dellTechDirectClientId")
            store.removeObject(forKey: CloudKey.dellTechDirectClientId.rawValue)
        }
        if let v = store.string(forKey: CloudKey.dellTechDirectClientSecret.rawValue) {
            KeychainSecretStore.set(v, for: .dellTechDirectClientSecret)
            defaults.removeObject(forKey: "dellTechDirectClientSecret")
            store.removeObject(forKey: CloudKey.dellTechDirectClientSecret.rawValue)
        }
    }

    private func copyRelevantDefaultsToStore() {
        guard useCloudSync, isICloudAvailable else { return }
        if let v = defaults.string(forKey: "baseURL") { store.set(v, forKey: CloudKey.baseURL.rawValue) }
        store.removeObject(forKey: CloudKey.apiToken.rawValue)
        store.set(defaults.bool(forKey: "isConfigured"), forKey: CloudKey.isConfigured.rawValue)
        store.set(defaults.bool(forKey: "hasCompletedOnboarding"), forKey: CloudKey.hasCompletedOnboarding.rawValue)
        store.set(defaults.bool(forKey: "hasSeenModulesIntro"), forKey: CloudKey.hasSeenModulesIntro.rawValue)
        if let v = defaults.string(forKey: "tabOrder") {
            store.set(v, forKey: CloudKey.tabOrder.rawValue)
        }
        if let v = defaults.string(forKey: "appTheme") { store.set(v, forKey: CloudKey.appTheme.rawValue) }
        store.set(defaults.bool(forKey: "useBiometrics"), forKey: CloudKey.useBiometrics.rawValue)
        if let v = defaults.string(forKey: "appLanguage") { store.set(v, forKey: CloudKey.appLanguage.rawValue) }
        if let v = defaults.string(forKey: "settingsLanguage") { store.set(v, forKey: CloudKey.settingsLanguage.rawValue) }
        store.set(defaults.bool(forKey: "biometricsJustConfirmed"), forKey: CloudKey.biometricsJustConfirmed.rawValue)
        store.set(defaults.object(forKey: "enableDellQrScan") as? Bool ?? true, forKey: CloudKey.enableDellQrScan.rawValue)
        store.set(defaults.object(forKey: "autoFillAssetTag") as? Bool ?? true, forKey: CloudKey.autoFillAssetTag.rawValue)
        store.removeObject(forKey: CloudKey.dellTechDirectClientId.rawValue)
        store.removeObject(forKey: CloudKey.dellTechDirectClientSecret.rawValue)
    }

    func wipeAllData() {
        let timestamp = Date().timeIntervalSince1970

        if isICloudAvailable {
            for key in CloudKey.allCases {
                store.removeObject(forKey: key.rawValue)
            }
            // Marker stays so other devices mirror the wipe.
            store.set(timestamp, forKey: CloudKey.lastWipeAt.rawValue)
            _ = store.synchronize()
        }

        performLocalWipe(rememberWipeAt: timestamp)
    }

    private func performLocalWipe(rememberWipeAt timestamp: TimeInterval) {
        KeychainSecretStore.wipeAll()

        if let bundleId = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleId)
        }
        defaults.set(timestamp, forKey: lastSeenWipeAtKey)
        defaults.synchronize()

        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        URLCache.shared.removeAllCachedResponses()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .appDataDidWipe, object: nil)
            NotificationCenter.default.post(name: .cloudSettingsDidChange, object: nil)
        }
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
    /// Posted after a local or remotely-triggered wipe.
    static let appDataDidWipe = Notification.Name("appDataDidWipe")
}
