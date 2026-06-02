import Foundation
import Security

enum SecretKey: String, CaseIterable {
    case apiToken
    case dellTechDirectClientId
    case dellTechDirectClientSecret
}

/// Keychain wrapper. Writes are synchronizable (iCloud Keychain); reads fall back to legacy local items.
enum KeychainSecretStore {
    private static let migrationFlagKey = "didMigrateSecretsToKeychainV1"
    private static let iCloudMigrationFlagKey = "didMigrateSecretsToICloudKeychainV1"

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.snipeMobile.app"
    }

    /// Target the iCloud copy, the legacy local-only copy, or either.
    private enum SyncScope {
        case cloud
        case localOnly
        case any
    }

    private static func baseQuery(for key: SecretKey, scope: SyncScope) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        switch scope {
        case .cloud:
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue as Any
        case .localOnly:
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        case .any:
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        return query
    }

    static func string(for key: SecretKey) -> String {
        if let value = read(key: key, scope: .cloud), !value.isEmpty {
            return value
        }
        if let value = read(key: key, scope: .localOnly), !value.isEmpty {
            return value
        }
        return ""
    }

    private static func read(key: SecretKey, scope: SyncScope) -> String? {
        var query = baseQuery(for: key, scope: scope)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func set(_ value: String, for key: SecretKey) {
        if value.isEmpty {
            delete(key)
            return
        }

        // Drop legacy local-only copy first.
        SecItemDelete(baseQuery(for: key, scope: .localOnly) as CFDictionary)

        let encoded = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: encoded,
            // Required for iCloud Keychain replication.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateQuery = baseQuery(for: key, scope: .cloud)
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        var insertQuery = baseQuery(for: key, scope: .cloud)
        insertQuery.merge(attributes) { _, new in new }
        SecItemAdd(insertQuery as CFDictionary, nil)
    }

    static func delete(_ key: SecretKey) {
        SecItemDelete(baseQuery(for: key, scope: .cloud) as CFDictionary)
        SecItemDelete(baseQuery(for: key, scope: .localOnly) as CFDictionary)
    }

    /// Remove every app-managed secret from the keychain.
    static func wipeAll() {
        for key in SecretKey.allCases {
            delete(key)
        }
    }

    static func migrateLegacyUserDefaultsSecretsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationFlagKey) else { return }

        let keys: [SecretKey] = [.apiToken, .dellTechDirectClientId, .dellTechDirectClientSecret]
        for key in keys {
            let legacy = defaults.string(forKey: key.rawValue) ?? ""
            if !legacy.isEmpty && string(for: key).isEmpty {
                set(legacy, for: key)
            }
            defaults.removeObject(forKey: key.rawValue)
        }

        defaults.set(true, forKey: migrationFlagKey)
    }

    /// One-time migration: rewrite local-only items as iCloud-synced so other devices pick them up.
    static func migrateLocalSecretsToICloudKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: iCloudMigrationFlagKey) else { return }

        for key in SecretKey.allCases {
            let localValue = read(key: key, scope: .localOnly) ?? ""
            guard !localValue.isEmpty else { continue }

            let cloudValue = read(key: key, scope: .cloud) ?? ""
            if cloudValue.isEmpty {
                set(localValue, for: key)
            } else {
                SecItemDelete(baseQuery(for: key, scope: .localOnly) as CFDictionary)
            }
        }

        defaults.set(true, forKey: iCloudMigrationFlagKey)
    }
}
