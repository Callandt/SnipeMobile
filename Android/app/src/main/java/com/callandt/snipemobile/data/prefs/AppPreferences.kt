package com.callandt.snipemobile.data.prefs

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "snipe_app_prefs")

/**
 * App settings stored in DataStore.
 */
class AppPreferences(private val context: Context) {

    val baseUrl: Flow<String> = context.dataStore.data.map { it[Keys.BASE_URL].orEmpty() }
    val isConfigured: Flow<Boolean> = context.dataStore.data.map { it[Keys.IS_CONFIGURED] ?: false }
    val hasCompletedOnboarding: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.HAS_COMPLETED_ONBOARDING] ?: false }
    val hasSeenModulesIntro: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.HAS_SEEN_MODULES_INTRO] ?: false }
    val showAccessoriesTab: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.SHOW_ACCESSORIES_TAB] ?: true }
    val showLicensesTab: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.SHOW_LICENSES_TAB] ?: true }
    val showConsumablesTab: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.SHOW_CONSUMABLES_TAB] ?: true }
    val showComponentsTab: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.SHOW_COMPONENTS_TAB] ?: true }
    val showAuditSubtab: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.ENABLE_AUDIT_SUBTAB] ?: false }
    val showMaintenanceSubtab: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.SHOW_MAINTENANCE] ?: true }
    val appTheme: Flow<String> = context.dataStore.data.map { it[Keys.APP_THEME] ?: "system" }
    val useBiometrics: Flow<Boolean> = context.dataStore.data.map { it[Keys.USE_BIOMETRICS] ?: false }
    val autoFillAssetTag: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.AUTO_FILL_ASSET_TAG] ?: true }
    val enableDellQrScan: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.ENABLE_DELL_QR_SCAN] ?: true }
    val useCloudSync: Flow<Boolean> = context.dataStore.data.map { it[Keys.USE_CLOUD_SYNC] ?: true }
    val settingsLanguage: Flow<String> = context.dataStore.data.map { it[Keys.SETTINGS_LANGUAGE] ?: "en" }
    val auditNotificationsEnabled: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.AUDIT_NOTIFICATIONS_ENABLED] ?: false }
    val auditNotificationHour: Flow<Int> =
        context.dataStore.data.map { it[Keys.AUDIT_NOTIFICATION_HOUR] ?: 9 }
    val auditNotificationMinute: Flow<Int> =
        context.dataStore.data.map { it[Keys.AUDIT_NOTIFICATION_MINUTE] ?: 0 }

    suspend fun getBaseUrl(): String = context.dataStore.data.first()[Keys.BASE_URL].orEmpty()

    suspend fun getIsConfigured(): Boolean = context.dataStore.data.first()[Keys.IS_CONFIGURED] ?: false

    fun getBaseUrlBlocking(): String = runBlocking { getBaseUrl() }

    fun getIsConfiguredBlocking(): Boolean = runBlocking { getIsConfigured() }

    fun getHasCompletedOnboardingBlocking(): Boolean =
        runBlocking { context.dataStore.data.first()[Keys.HAS_COMPLETED_ONBOARDING] ?: false }

    suspend fun setBaseUrl(value: String) {
        context.dataStore.edit { it[Keys.BASE_URL] = value }
    }

    suspend fun setIsConfigured(value: Boolean) {
        context.dataStore.edit { it[Keys.IS_CONFIGURED] = value }
    }

    suspend fun setHasCompletedOnboarding(value: Boolean) {
        context.dataStore.edit { it[Keys.HAS_COMPLETED_ONBOARDING] = value }
    }

    suspend fun setHasSeenModulesIntro(value: Boolean) {
        context.dataStore.edit { it[Keys.HAS_SEEN_MODULES_INTRO] = value }
    }

    suspend fun setShowAccessoriesTab(value: Boolean) {
        context.dataStore.edit { it[Keys.SHOW_ACCESSORIES_TAB] = value }
    }

    suspend fun setShowLicensesTab(value: Boolean) {
        context.dataStore.edit { it[Keys.SHOW_LICENSES_TAB] = value }
    }

    suspend fun setShowConsumablesTab(value: Boolean) {
        context.dataStore.edit { it[Keys.SHOW_CONSUMABLES_TAB] = value }
    }

    suspend fun setShowComponentsTab(value: Boolean) {
        context.dataStore.edit { it[Keys.SHOW_COMPONENTS_TAB] = value }
    }

    suspend fun isAuditSubtabPreferenceSet(): Boolean =
        context.dataStore.data.first().contains(Keys.ENABLE_AUDIT_SUBTAB)

    suspend fun setShowAuditSubtab(value: Boolean) {
        context.dataStore.edit { it[Keys.ENABLE_AUDIT_SUBTAB] = value }
    }

    suspend fun setShowMaintenanceSubtab(value: Boolean) {
        context.dataStore.edit { it[Keys.SHOW_MAINTENANCE] = value }
    }

    suspend fun setAppTheme(value: String) {
        context.dataStore.edit { it[Keys.APP_THEME] = value }
    }

    suspend fun setUseBiometrics(value: Boolean) {
        context.dataStore.edit { it[Keys.USE_BIOMETRICS] = value }
    }

    suspend fun setBiometricsJustConfirmed(value: Boolean) {
        context.dataStore.edit { it[Keys.BIOMETRICS_JUST_CONFIRMED] = value }
    }

    /** Returns true once after settings confirmation, then clears the flag. */
    suspend fun consumeBiometricsJustConfirmed(): Boolean {
        var wasConfirmed = false
        context.dataStore.edit { prefs ->
            wasConfirmed = prefs[Keys.BIOMETRICS_JUST_CONFIRMED] == true
            if (wasConfirmed) prefs[Keys.BIOMETRICS_JUST_CONFIRMED] = false
        }
        return wasConfirmed
    }

    suspend fun setAutoFillAssetTag(value: Boolean) {
        context.dataStore.edit { it[Keys.AUTO_FILL_ASSET_TAG] = value }
    }

    suspend fun setEnableDellQrScan(value: Boolean) {
        context.dataStore.edit { it[Keys.ENABLE_DELL_QR_SCAN] = value }
    }

    suspend fun setAuditNotificationsEnabled(value: Boolean) {
        context.dataStore.edit { it[Keys.AUDIT_NOTIFICATIONS_ENABLED] = value }
    }

    suspend fun setAuditNotificationHour(value: Int) {
        context.dataStore.edit { it[Keys.AUDIT_NOTIFICATION_HOUR] = value.coerceIn(0, 23) }
    }

    suspend fun setAuditNotificationMinute(value: Int) {
        context.dataStore.edit { it[Keys.AUDIT_NOTIFICATION_MINUTE] = value.coerceIn(0, 59) }
    }

    suspend fun wipeAll() {
        context.dataStore.edit { it.clear() }
    }

    private object Keys {
        val BASE_URL = stringPreferencesKey("baseURL")
        val IS_CONFIGURED = booleanPreferencesKey("isConfigured")
        val HAS_COMPLETED_ONBOARDING = booleanPreferencesKey("hasCompletedOnboarding")
        val HAS_SEEN_MODULES_INTRO = booleanPreferencesKey("hasSeenModulesIntro")
        val SHOW_ACCESSORIES_TAB = booleanPreferencesKey("showAccessoriesTab")
        val SHOW_LICENSES_TAB = booleanPreferencesKey("showLicensesTab")
        val SHOW_CONSUMABLES_TAB = booleanPreferencesKey("showConsumablesTab")
        val SHOW_COMPONENTS_TAB = booleanPreferencesKey("showComponentsTab")
        val ENABLE_AUDIT_SUBTAB = booleanPreferencesKey("enableAuditSubtab")
        val SHOW_MAINTENANCE = booleanPreferencesKey("showMaintenance")
        val APP_THEME = stringPreferencesKey("appTheme")
        val USE_BIOMETRICS = booleanPreferencesKey("useBiometrics")
        val AUTO_FILL_ASSET_TAG = booleanPreferencesKey("autoFillAssetTag")
        val ENABLE_DELL_QR_SCAN = booleanPreferencesKey("enableDellQrScan")
        val USE_CLOUD_SYNC = booleanPreferencesKey("useCloudSync")
        val SETTINGS_LANGUAGE = stringPreferencesKey("settingsLanguage")
        val AUDIT_NOTIFICATIONS_ENABLED = booleanPreferencesKey("auditNotificationsEnabled")
        val AUDIT_NOTIFICATION_HOUR = intPreferencesKey("auditNotificationHour")
        val AUDIT_NOTIFICATION_MINUTE = intPreferencesKey("auditNotificationMinute")
        val STOCK_SELECTED_SUBMODULE = stringPreferencesKey("stockSelectedSubmodule")
        val DIRECTORY_SELECTED_SUBMODULE = stringPreferencesKey("directorySelectedSubmodule")
        val BIOMETRICS_JUST_CONFIRMED = booleanPreferencesKey("biometricsJustConfirmed")
    }
}
