package com.callandt.snipemobile.data.secure

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec

enum class AppSecret(val storageKey: String) {
    API_TOKEN("apiToken"),
    DELL_TECH_DIRECT_CLIENT_ID("dellTechDirectClientId"),
    DELL_TECH_DIRECT_CLIENT_SECRET("dellTechDirectClientSecret"),
}

/**
 * Secrets encrypted with an AES key in the Android Keystore.
 * Ciphertext is stored in ordinary SharedPreferences.
 */
class SecureStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    private val aesKey: javax.crypto.SecretKey by lazy { getOrCreateKeystoreKey() }

    fun getString(key: AppSecret): String {
        val encoded = prefs.getString(key.storageKey, null) ?: return ""
        return runCatching { decrypt(encoded) }.getOrDefault("")
    }

    fun setString(key: AppSecret, value: String) {
        if (value.isEmpty()) {
            delete(key)
            return
        }
        prefs.edit().putString(key.storageKey, encrypt(value)).apply()
    }

    fun delete(key: AppSecret) {
        prefs.edit().remove(key.storageKey).apply()
    }

    fun wipeAll() {
        AppSecret.entries.forEach { delete(it) }
    }

    /** Migrate legacy plaintext prefs into Keystore-backed storage. */
    fun migrateLegacyPlaintextSecretsIfNeeded(legacyPrefs: SharedPreferences) {
        if (legacyPrefs.getBoolean(MIGRATION_FLAG, false)) return
        AppSecret.entries.forEach { key ->
            val legacy = legacyPrefs.getString(key.storageKey, "").orEmpty()
            if (legacy.isNotEmpty() && getString(key).isEmpty()) {
                setString(key, legacy)
            }
            legacyPrefs.edit().remove(key.storageKey).apply()
        }
        legacyPrefs.edit().putBoolean(MIGRATION_FLAG, true).apply()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, aesKey)
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        val payload = ByteBuffer.allocate(4 + iv.size + ciphertext.size)
            .putInt(iv.size)
            .put(iv)
            .put(ciphertext)
            .array()
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String {
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        val buffer = ByteBuffer.wrap(payload)
        val ivSize = buffer.int
        require(ivSize in 1..64) { "Invalid IV size" }
        val iv = ByteArray(ivSize)
        buffer.get(iv)
        val ciphertext = ByteArray(buffer.remaining())
        buffer.get(ciphertext)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, aesKey, GCMParameterSpec(GCM_TAG_BITS, iv))
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    private fun getOrCreateKeystoreKey(): javax.crypto.SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? javax.crypto.SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    companion object {
        private const val PREFS_FILE = "snipe_secrets_v2"
        private const val MIGRATION_FLAG = "didMigrateSecretsToEncryptedPrefsV1"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "snipe_mobile_secrets_aes"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
    }
}
