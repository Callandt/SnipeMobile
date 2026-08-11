package com.callandt.snipemobile.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.callandt.snipemobile.MainActivity
import com.callandt.snipemobile.R
import com.callandt.snipemobile.data.cache.LocalCacheStore
import com.callandt.snipemobile.data.prefs.AppPreferences
import com.callandt.snipemobile.ui.util.AuditDateHelper
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

object AuditNotificationHelper {
    private const val CHANNEL_ID = "audit_reminders"
    private const val NOTIFICATION_ID = 7001

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            L10n.string("audit_notification_title"),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = L10n.string("audit_notifications_toggle")
        }
        context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    fun showDueTodayNotification(context: Context) {
        ensureChannel(context)
        val dueTodayCount = countDueTodayAssets(context)
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(AuditNotificationScheduler.EXTRA_AUDIT_INTENT, AuditNotificationScheduler.INTENT_OPEN_DUE_TODAY)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_bird)
            .setContentTitle(L10n.string("audit_notification_title"))
            .setContentText(L10n.string("audit_notification_body", dueTodayCount))
            .setStyle(NotificationCompat.BigTextStyle().bigText(L10n.string("audit_notification_body", dueTodayCount)))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
    }

    private fun countDueTodayAssets(context: Context): Int {
        val prefs = AppPreferences(context)
        val baseUrl = runBlocking { prefs.getBaseUrl() }
        val configured = runBlocking { prefs.getIsConfigured() }
        if (!configured || baseUrl.isBlank()) return 0
        val key = LocalCacheStore.keyForBaseUrl(baseUrl)
        val snapshot = LocalCacheStore.load(context, key) ?: return 0
        return snapshot.assets.count { AuditDateHelper.isDueToday(it) }
    }
}
