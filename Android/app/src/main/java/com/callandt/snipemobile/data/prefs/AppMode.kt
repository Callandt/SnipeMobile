package com.callandt.snipemobile.data.prefs

import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking

enum class AppMode(val rawValue: String) {
    Admin("admin"),
    User("user");

    val localizedTitle: String
        get() = when (this) {
            Admin -> L10n.string("app_mode_admin")
            User -> L10n.string("app_mode_user")
        }

    companion object {
        fun fromRaw(raw: String?): AppMode? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** UI mode + whether the token can use admin features. */
class AppModeStore(private val preferences: AppPreferences) {
    private val _current = MutableStateFlow(AppMode.fromRaw(preferences.getAppModeBlocking()))
    val current: StateFlow<AppMode?> = _current.asStateFlow()

    private val _isAdminCapable = MutableStateFlow(preferences.getApiIsAdminCapableBlocking())
    val isAdminCapable: StateFlow<Boolean> = _isAdminCapable.asStateFlow()

    private val _canRequestAssets = MutableStateFlow(preferences.getCanRequestAssetsBlocking())
    val canRequestAssets: StateFlow<Boolean> = _canRequestAssets.asStateFlow()

    private val _hasDetectedMode = MutableStateFlow(preferences.getHasDetectedAppModeBlocking())
    val hasDetectedMode: StateFlow<Boolean> = _hasDetectedMode.asStateFlow()

    val isUserMode: Boolean get() = _current.value == AppMode.User
    val isAdminMode: Boolean get() = _current.value == AppMode.Admin

    val currentFlow: Flow<AppMode?> = preferences.appMode.map { AppMode.fromRaw(it) }

    fun migrateAdminCapableIfNeeded() {
        if (_current.value == AppMode.Admin && !_isAdminCapable.value) {
            setAdminCapable(true)
        }
    }

    fun clear() {
        setCurrent(null)
        setCanRequestAssets(false)
        setHasDetectedMode(false)
        setAdminCapable(false)
    }

    /** Clear capability after URL/token change; keep shell mode. */
    fun clearForServerChange() {
        setCanRequestAssets(false)
        setAdminCapable(false)
    }

    /** First detection sets mode; later only updates capability. */
    fun applyDetection(detectedMode: AppMode, canRequestAssets: Boolean) {
        val wasDetected = _hasDetectedMode.value
        val previousMode = _current.value
        setAdminCapable(detectedMode == AppMode.Admin)
        setCanRequestAssets(canRequestAssets)
        setHasDetectedMode(true)

        when {
            !wasDetected -> setCurrent(detectedMode)
            !_isAdminCapable.value -> setCurrent(AppMode.User)
            previousMode == null -> setCurrent(detectedMode)
        }
    }

    fun apply(mode: AppMode, canRequestAssets: Boolean) {
        applyDetection(detectedMode = mode, canRequestAssets = canRequestAssets)
        setCurrent(mode)
        setAdminCapable(mode == AppMode.Admin)
    }

    fun setActiveMode(mode: AppMode) {
        if (mode == AppMode.Admin && !_isAdminCapable.value) return
        setCurrent(mode)
    }

    private fun setCurrent(mode: AppMode?) {
        _current.value = mode
        runBlocking { preferences.setAppMode(mode?.rawValue) }
    }

    private fun setAdminCapable(value: Boolean) {
        _isAdminCapable.value = value
        runBlocking { preferences.setApiIsAdminCapable(value) }
    }

    private fun setCanRequestAssets(value: Boolean) {
        _canRequestAssets.value = value
        runBlocking { preferences.setCanRequestAssets(value) }
    }

    private fun setHasDetectedMode(value: Boolean) {
        _hasDetectedMode.value = value
        runBlocking { preferences.setHasDetectedAppMode(value) }
    }
}

data class AppModeCheckProgress(
    val connection: StepState = StepState.Pending,
    val rights: StepState = StepState.Pending,
    val detectedMode: AppMode? = null,
) {
    sealed class StepState {
        data object Pending : StepState()
        data object Running : StepState()
        data object Success : StepState()
        data class Failure(val message: String? = null) : StepState()
    }

    val isComplete: Boolean
        get() = connection is StepState.Failure ||
            rights is StepState.Failure ||
            (connection is StepState.Success && rights is StepState.Success)

    val succeeded: Boolean
        get() = connection is StepState.Success && rights is StepState.Success
}
