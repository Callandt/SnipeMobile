import Foundation
import Security

enum SecretKey: String {
    case apiToken
    case dellTechDirectClientId
    case dellTechDirectClientSecret
}

enum KeychainSecretStore {
    private static let migrationFlagKey = "didMigrateSecretsToKeychainV1"

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.snipeMobile.app"
    }

    static func string(for key: SecretKey) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func set(_ value: String, for key: SecretKey) {
        if value.isEmpty {
            delete(key)
            return
        }

        let encoded = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: encoded,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        var insertQuery = query
        insertQuery.merge(attributes) { _, new in new }
        SecItemAdd(insertQuery as CFDictionary, nil)
    }

    static func delete(_ key: SecretKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
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
}
