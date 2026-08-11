package com.callandt.snipemobile.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.callandt.snipemobile.data.prefs.AppPreferences
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

/**
 * Fires the daily audit reminder and reschedules the next alarm.
 * Also handles [Intent.ACTION_BOOT_COMPLETED] to restore the schedule after reboot.
 */
class AuditNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> AuditNotificationScheduler.rescheduleFromPreferences(context)
            AuditNotificationScheduler.ACTION_AUDIT_REMINDER -> {
                val prefs = AppPreferences(context)
                val enabled = runBlocking { prefs.auditNotificationsEnabled.first() }
                val showAudit = runBlocking { prefs.showAuditSubtab.first() }
                if (enabled && showAudit && AuditNotificationScheduler.canPostNotifications(context)) {
                    AuditNotificationHelper.showDueTodayNotification(context)
                }
                val hour = runBlocking { prefs.auditNotificationHour.first() }
                val minute = runBlocking { prefs.auditNotificationMinute.first() }
                AuditNotificationScheduler.updateSchedule(context, enabled && showAudit, hour, minute)
            }
        }
    }
}
