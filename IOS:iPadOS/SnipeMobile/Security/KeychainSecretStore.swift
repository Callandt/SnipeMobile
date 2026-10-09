import Foundation
import Security

enum SecretKey: String, CaseIterable {
    case apiToken
    case dellTechDirectClientId
    case dellTechDirectClientSecret
}

/// Keychain wrapper. Always keeps a local copy. iCloud Keychain only for small secrets.
enum KeychainSecretStore {
    private static let migrationFlagKey = "didMigrateSecretsToKeychainV1"
    private static let iCloudMigrationFlagKey = "didMigrateSecretsToICloudKeychainV1"
    /// Above this, skip iCloud Keychain.
    private static let cloudKeychainByteLimit = 2048

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

    /// Local first. A cloud hit is copied locally.
    static func string(for key: SecretKey) -> String {
        if let value = read(key: key, scope: .localOnly), !value.isEmpty {
            return value
        }
        if let value = read(key: key, scope: .cloud), !value.isEmpty {
            upsert(
                data: Data(value.utf8),
                key: key,
                scope: .localOnly,
                accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            )
            return value
        }
        return ""
    }

    /// On-device value only.
    static func localString(for key: SecretKey) -> String {
        read(key: key, scope: .localOnly) ?? ""
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

        let encoded = Data(value.utf8)
        upsert(
            data: encoded,
            key: key,
            scope: .localOnly,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
        guard read(key: key, scope: .localOnly) == value else {
            AppLog.info(
                "Local keychain save did not stick key=\(key.rawValue) bytes=\(encoded.count)",
                category: "keychain"
            )
            if encoded.count <= cloudKeychainByteLimit {
                upsert(
                    data: encoded,
                    key: key,
                    scope: .cloud,
                    accessible: kSecAttrAccessibleAfterFirstUnlock
                )
            }
            return
        }

        if encoded.count > cloudKeychainByteLimit {
            // Drop the previous iCloud Keychain item.
            SecItemDelete(baseQuery(for: key, scope: .cloud) as CFDictionary)
            AppLog.info(
                "Skipped iCloud Keychain for \(key.rawValue) bytes=\(encoded.count)",
                category: "keychain"
            )
            return
        }

        upsert(
            data: encoded,
            key: key,
            scope: .cloud,
            accessible: kSecAttrAccessibleAfterFirstUnlock
        )
    }

    /// On-device item only.
    static func setLocal(_ value: String, for key: SecretKey) {
        if value.isEmpty {
            SecItemDelete(baseQuery(for: key, scope: .localOnly) as CFDictionary)
            return
        }
        upsert(
            data: Data(value.utf8),
            key: key,
            scope: .localOnly,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    private static func upsert(data: Data, key: SecretKey, scope: SyncScope, accessible: CFString) {
        let query = baseQuery(for: key, scope: scope)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus != errSecItemNotFound {
            SecItemDelete(query as CFDictionary)
        }

        var insertQuery = query
        insertQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            AppLog.info(
                "Keychain write failed key=\(key.rawValue) scope=\(String(describing: scope)) bytes=\(data.count) update=\(updateStatus) add=\(addStatus)",
                category: "keychain"
            )
            return
        }
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

    /// One-time: copy local items into iCloud Keychain. Keep the local copy.
    static func migrateLocalSecretsToICloudKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: iCloudMigrationFlagKey) else { return }

        for key in SecretKey.allCases {
            let localValue = read(key: key, scope: .localOnly) ?? ""
            guard !localValue.isEmpty else { continue }

            let cloudValue = read(key: key, scope: .cloud) ?? ""
            if cloudValue.isEmpty {
                set(localValue, for: key)
            }
        }

        defaults.set(true, forKey: iCloudMigrationFlagKey)
    }
}
