package com.callandt.snipemobile

import android.app.Application
import com.callandt.snipemobile.data.api.SnipeApiClient
import com.callandt.snipemobile.data.prefs.AppModeStore
import com.callandt.snipemobile.data.prefs.AppPreferences
import com.callandt.snipemobile.data.secure.SecureStore
import com.callandt.snipemobile.debug.AppLog
import com.callandt.snipemobile.debug.DebugLogStore
import com.callandt.snipemobile.notifications.AuditNotificationHelper
import com.callandt.snipemobile.notifications.AuditNotificationScheduler

class SnipeMobileApp : Application() {

    lateinit var apiClient: SnipeApiClient
        private set

    lateinit var preferences: AppPreferences
        private set

    lateinit var appModeStore: AppModeStore
        private set

    lateinit var secureStore: SecureStore
        private set

    override fun onCreate() {
        super.onCreate()
        DebugLogStore.startIfNeeded()
        AppLog.info("App launch", "app")
        preferences = AppPreferences(this)
        appModeStore = AppModeStore(preferences)
        appModeStore.migrateAdminCapableIfNeeded()
        secureStore = SecureStore(this)
        apiClient = SnipeApiClient(this, preferences, appModeStore, secureStore)
        AuditNotificationHelper.ensureChannel(this)
        AuditNotificationScheduler.rescheduleFromPreferences(this)
    }
}
