package com.callandt.snipemobile.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.callandt.snipemobile.SnipeMobileApp
import com.callandt.snipemobile.data.api.DellTechDirectClient
import com.callandt.snipemobile.data.api.SnipeApiClient
import com.callandt.snipemobile.data.cache.LocalCacheStore
import com.callandt.snipemobile.notifications.AuditNotificationScheduler
import com.callandt.snipemobile.widget.WidgetSnapshotBuilder
import com.callandt.snipemobile.data.prefs.AppMode
import com.callandt.snipemobile.data.prefs.AppModeCheckProgress
import com.callandt.snipemobile.data.prefs.AppModeStore
import com.callandt.snipemobile.data.prefs.AppPreferences
import com.callandt.snipemobile.data.secure.SecretKey
import com.callandt.snipemobile.data.secure.SecureStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class AuditNavigationIntent {
    OpenDueToday,
}

enum class HardwareSubtabIntent {
    Assets,
    Audit,
    Maintenance,
}

data class DellAddPrefill(
    val url: String,
    val serial: String,
)

class AppViewModel(
    application: Application,
    val apiClient: SnipeApiClient,
    val preferences: AppPreferences,
    private val secureStore: SecureStore,
    val appModeStore: AppModeStore,
) : AndroidViewModel(application) {

    val assets = apiClient.assets
    val users = apiClient.users
    val accessories = apiClient.accessories
    val licenses = apiClient.licenses
    val consumables = apiClient.consumables
    val components = apiClient.components
    val locations = apiClient.locations
    val maintenances = apiClient.maintenances
    val currentUser = apiClient.currentUser
    val isLoading = apiClient.isLoading
    val isConfigured = apiClient.isConfigured
    val hasCompletedInitialLoad = apiClient.hasCompletedInitialLoad
    val errorMessage = apiClient.errorMessage
    val refreshErrorMessage = apiClient.refreshErrorMessage
    val pendingUnauthorizedSessionWipe = apiClient.pendingUnauthorizedSessionWipe
    val lastApiMessage = apiClient.lastApiMessage
    val loadingProgress = apiClient.loadingProgress

    val appMode: StateFlow<AppMode?> = appModeStore.current
    val isAdminCapable: StateFlow<Boolean> = appModeStore.isAdminCapable
    val hasDetectedAppMode: StateFlow<Boolean> = appModeStore.hasDetectedMode
    val canRequestAssets: StateFlow<Boolean> = appModeStore.canRequestAssets

    fun clearRefreshError() {
        apiClient.clearRefreshError()
    }

    // Seeded from DataStore so cold start skips a blank spinner frame.
    val hasCompletedOnboarding: StateFlow<Boolean> =
        preferences.hasCompletedOnboarding
            .stateIn(
                viewModelScope,
                SharingStarted.Eagerly,
                preferences.getHasCompletedOnboardingBlocking(),
            )

    val appTheme: StateFlow<String> =
        preferences.appTheme.stateIn(viewModelScope, SharingStarted.Eagerly, "system")

    val useBiometrics: StateFlow<Boolean> =
        preferences.useBiometrics.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    val showAccessoriesTab: StateFlow<Boolean> =
        preferences.showAccessoriesTab.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    val showLicensesTab: StateFlow<Boolean> =
        preferences.showLicensesTab.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    val showConsumablesTab: StateFlow<Boolean> =
        preferences.showConsumablesTab.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    val showComponentsTab: StateFlow<Boolean> =
        preferences.showComponentsTab.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    val showAuditSubtab: StateFlow<Boolean> =
        preferences.showAuditSubtab.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    val showMaintenanceSubtab: StateFlow<Boolean> =
        preferences.showMaintenanceSubtab.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    val baseUrl: StateFlow<String> =
        preferences.baseUrl.stateIn(viewModelScope, SharingStarted.Eagerly, "")

    val autoFillAssetTag: StateFlow<Boolean> =
        preferences.autoFillAssetTag.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    val enableDellQrScan: StateFlow<Boolean> =
        preferences.enableDellQrScan.stateIn(viewModelScope, SharingStarted.Eagerly, true)

    val auditNotificationsEnabled: StateFlow<Boolean> =
        preferences.auditNotificationsEnabled.stateIn(viewModelScope, SharingStarted.Eagerly, false)

    val auditNotificationHour: StateFlow<Int> =
        preferences.auditNotificationHour.stateIn(viewModelScope, SharingStarted.Eagerly, 9)

    val auditNotificationMinute: StateFlow<Int> =
        preferences.auditNotificationMinute.stateIn(viewModelScope, SharingStarted.Eagerly, 0)

    private val _pendingAuditNavigation = MutableStateFlow<AuditNavigationIntent?>(null)
    val pendingAuditNavigation: StateFlow<AuditNavigationIntent?> = _pendingAuditNavigation.asStateFlow()

    private val _pendingMainTab = MutableStateFlow<com.callandt.snipemobile.ui.main.MainTab?>(null)
    val pendingMainTab: StateFlow<com.callandt.snipemobile.ui.main.MainTab?> = _pendingMainTab.asStateFlow()

    private val _pendingHardwareSubtab = MutableStateFlow<HardwareSubtabIntent?>(null)
    val pendingHardwareSubtab: StateFlow<HardwareSubtabIntent?> = _pendingHardwareSubtab.asStateFlow()

    private val _pendingDellAdd = MutableStateFlow<DellAddPrefill?>(null)
    val pendingDellAdd: StateFlow<DellAddPrefill?> = _pendingDellAdd.asStateFlow()

    val statusLabels = apiClient.statusLabels
    val models = apiClient.models
    val categories = apiClient.categories
    val companies = apiClient.companies
    val manufacturers = apiClient.manufacturers
    val suppliers = apiClient.suppliers
    val fieldDefinitions = apiClient.fieldDefinitions
    val fieldsets = apiClient.fieldsets

    fun refresh() {
        viewModelScope.launch {
            when (appModeStore.current.value) {
                AppMode.User -> apiClient.fetchUserModeData(clearRefreshError = true)
                else -> apiClient.fetchPrimaryThenBackground(clearRefreshError = true)
            }
        }
    }

    fun syncInBackground() {
        apiClient.syncAllInBackground()
    }

    fun setActiveMode(mode: AppMode) {
        appModeStore.setActiveMode(mode)
        viewModelScope.launch { apiClient.syncForCurrentAppMode() }
    }

    suspend fun detectAppMode(
        onProgress: (AppModeCheckProgress) -> Unit = {},
    ): AppModeCheckProgress = apiClient.detectAppMode(onProgress)

    fun syncForCurrentAppMode() {
        viewModelScope.launch { apiClient.syncForCurrentAppMode() }
    }

    suspend fun syncForCurrentAppModeSuspending() {
        apiClient.syncForCurrentAppMode()
    }

    suspend fun saveApiConfiguration(
        url: String,
        token: String,
        syncAfterSave: Boolean = true,
    ) {
        apiClient.saveConfiguration(url, token, syncAfterSave)
    }

    suspend fun validateApiCredentials(): String? = apiClient.validateApiCredentials()

    fun completeOnboarding() {
        viewModelScope.launch {
            preferences.setHasCompletedOnboarding(true)
        }
    }

    fun setAppTheme(theme: String) {
        viewModelScope.launch { preferences.setAppTheme(theme) }
    }

    fun setUseBiometrics(enabled: Boolean, justConfirmed: Boolean = false) {
        viewModelScope.launch {
            if (justConfirmed) preferences.setBiometricsJustConfirmed(true)
            preferences.setUseBiometrics(enabled)
        }
    }

    suspend fun consumeBiometricsJustConfirmed(): Boolean =
        preferences.consumeBiometricsJustConfirmed()

    fun setShowAccessoriesTab(enabled: Boolean) {
        viewModelScope.launch { preferences.setShowAccessoriesTab(enabled) }
    }

    fun setShowLicensesTab(enabled: Boolean) {
        viewModelScope.launch { preferences.setShowLicensesTab(enabled) }
    }

    fun setShowConsumablesTab(enabled: Boolean) {
        viewModelScope.launch { preferences.setShowConsumablesTab(enabled) }
    }

    fun setShowComponentsTab(enabled: Boolean) {
        viewModelScope.launch { preferences.setShowComponentsTab(enabled) }
    }

    suspend fun isAuditSubtabPreferenceSet(): Boolean =
        preferences.isAuditSubtabPreferenceSet()

    fun setShowAuditSubtab(enabled: Boolean) {
        viewModelScope.launch {
            preferences.setShowAuditSubtab(enabled)
            if (!enabled) {
                preferences.setAuditNotificationsEnabled(false)
            }
            refreshAuditNotificationSchedule()
        }
    }

    fun setAuditNotificationsEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferences.setAuditNotificationsEnabled(enabled)
            refreshAuditNotificationSchedule()
        }
    }

    fun setAuditNotificationTime(hour: Int, minute: Int) {
        viewModelScope.launch {
            preferences.setAuditNotificationHour(hour)
            preferences.setAuditNotificationMinute(minute)
            refreshAuditNotificationSchedule()
        }
    }

    fun refreshAuditNotificationSchedule() {
        viewModelScope.launch {
            val enabled = preferences.auditNotificationsEnabled.first()
            val showAudit = preferences.showAuditSubtab.first()
            val hour = preferences.auditNotificationHour.first()
            val minute = preferences.auditNotificationMinute.first()
            AuditNotificationScheduler.updateSchedule(
                getApplication(),
                enabled && showAudit,
                hour,
                minute,
            )
        }
    }

    fun setPendingAuditNavigation(intent: AuditNavigationIntent) {
        _pendingAuditNavigation.value = intent
    }

    fun consumePendingAuditNavigation() {
        _pendingAuditNavigation.value = null
    }

    fun setPendingWidgetDestination(destination: com.callandt.snipemobile.widget.WidgetDestination) {
        when (destination) {
            com.callandt.snipemobile.widget.WidgetDestination.Overview,
            com.callandt.snipemobile.widget.WidgetDestination.Assets,
            -> {
                _pendingMainTab.value = com.callandt.snipemobile.ui.main.MainTab.Hardware
                _pendingHardwareSubtab.value = HardwareSubtabIntent.Assets
            }
            com.callandt.snipemobile.widget.WidgetDestination.Audits -> {
                _pendingMainTab.value = com.callandt.snipemobile.ui.main.MainTab.Hardware
                _pendingHardwareSubtab.value = HardwareSubtabIntent.Audit
                _pendingAuditNavigation.value = AuditNavigationIntent.OpenDueToday
            }
            com.callandt.snipemobile.widget.WidgetDestination.Maintenance -> {
                _pendingMainTab.value = com.callandt.snipemobile.ui.main.MainTab.Hardware
                _pendingHardwareSubtab.value = HardwareSubtabIntent.Maintenance
            }
            com.callandt.snipemobile.widget.WidgetDestination.Stock -> {
                _pendingMainTab.value = com.callandt.snipemobile.ui.main.MainTab.Stock
                _pendingHardwareSubtab.value = null
            }
        }
    }

    fun consumePendingMainTab(): com.callandt.snipemobile.ui.main.MainTab? {
        val value = _pendingMainTab.value
        _pendingMainTab.value = null
        return value
    }

    fun consumePendingHardwareSubtab(): HardwareSubtabIntent? {
        val value = _pendingHardwareSubtab.value
        _pendingHardwareSubtab.value = null
        return value
    }

    fun setShowMaintenanceSubtab(enabled: Boolean) {
        viewModelScope.launch { preferences.setShowMaintenanceSubtab(enabled) }
    }

    fun setAutoFillAssetTag(enabled: Boolean) {
        viewModelScope.launch { preferences.setAutoFillAssetTag(enabled) }
    }

    fun setEnableDellQrScan(enabled: Boolean) {
        viewModelScope.launch { preferences.setEnableDellQrScan(enabled) }
    }

    fun dellTechDirectClientId(): String =
        secureStore.getString(SecretKey.DELL_TECH_DIRECT_CLIENT_ID)

    fun dellTechDirectClientSecret(): String =
        secureStore.getString(SecretKey.DELL_TECH_DIRECT_CLIENT_SECRET)

    fun saveDellTechDirectCredentials(clientId: String, clientSecret: String) {
        secureStore.setString(SecretKey.DELL_TECH_DIRECT_CLIENT_ID, clientId.trim())
        secureStore.setString(SecretKey.DELL_TECH_DIRECT_CLIENT_SECRET, clientSecret)
    }

    suspend fun testDellTechDirectConnection(): String? {
        val clientId = dellTechDirectClientId()
        val clientSecret = dellTechDirectClientSecret()
        return DellTechDirectClient.testConnection(clientId, clientSecret)
    }

    fun setPendingDellAdd(url: String, serial: String) {
        _pendingDellAdd.value = DellAddPrefill(url = url, serial = serial)
    }

    fun clearPendingDellAdd() {
        _pendingDellAdd.value = null
    }

    fun wipeAllData() {
        apiClient.clearPendingUnauthorizedSessionWipe()
        apiClient.clearSessionData(resetConfigured = true, resetAppMode = true, fullWipe = true)
        appModeStore.clear()
        secureStore.wipeAll()
        LocalCacheStore.clearAll(getApplication())
        WidgetSnapshotBuilder.clear(getApplication())
        viewModelScope.launch {
            preferences.wipeAll()
            AuditNotificationScheduler.updateSchedule(getApplication(), false, 9, 0)
        }
    }

    fun acknowledgeUnauthorizedSessionWipe() {
        apiClient.clearPendingUnauthorizedSessionWipe()
    }

    fun currentApiToken(): String = secureStore.getString(SecretKey.API_TOKEN)

    class Factory(private val app: SnipeMobileApp) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(AppViewModel::class.java)) {
                return AppViewModel(
                    app,
                    app.apiClient,
                    app.preferences,
                    app.secureStore,
                    app.appModeStore,
                ) as T
            }
            throw IllegalArgumentException("Onbekende ViewModel: ${modelClass.name}")
        }
    }
}
