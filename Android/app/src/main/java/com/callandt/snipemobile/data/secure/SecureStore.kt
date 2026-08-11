package com.callandt.snipemobile.data.secure

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

enum class SecretKey(val storageKey: String) {
    API_TOKEN("apiToken"),
    DELL_TECH_DIRECT_CLIENT_ID("dellTechDirectClientId"),
    DELL_TECH_DIRECT_CLIENT_SECRET("dellTechDirectClientSecret"),
}

/**
 * Encrypted storage for API token and Dell TechDirect credentials.
 */
class SecureStore(context: Context) {

    private val prefs: SharedPreferences

    init {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        prefs = EncryptedSharedPreferences.create(
            context,
            PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun getString(key: SecretKey): String = prefs.getString(key.storageKey, "").orEmpty()

    fun setString(key: SecretKey, value: String) {
        if (value.isEmpty()) {
            delete(key)
            return
        }
        prefs.edit().putString(key.storageKey, value).apply()
    }

    fun delete(key: SecretKey) {
        prefs.edit().remove(key.storageKey).apply()
    }

    fun wipeAll() {
        SecretKey.entries.forEach { delete(it) }
    }

    /** Migrate legacy plaintext prefs into encrypted storage. */
    fun migrateLegacyPlaintextSecretsIfNeeded(legacyPrefs: SharedPreferences) {
        if (legacyPrefs.getBoolean(MIGRATION_FLAG, false)) return
        SecretKey.entries.forEach { key ->
            val legacy = legacyPrefs.getString(key.storageKey, "").orEmpty()
            if (legacy.isNotEmpty() && getString(key).isEmpty()) {
                setString(key, legacy)
            }
            legacyPrefs.edit().remove(key.storageKey).apply()
        }
        legacyPrefs.edit().putBoolean(MIGRATION_FLAG, true).apply()
    }

    companion object {
        private const val PREFS_FILE = "snipe_secrets"
        private const val MIGRATION_FLAG = "didMigrateSecretsToEncryptedPrefsV1"
    }
}
