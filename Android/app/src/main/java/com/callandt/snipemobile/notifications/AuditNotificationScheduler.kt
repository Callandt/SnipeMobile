package com.callandt.snipemobile.notifications

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import com.callandt.snipemobile.data.prefs.AppPreferences
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import java.util.Calendar

/** Daily audit reminder. Falls back to inexact alarms when exact isn't allowed. */
object AuditNotificationScheduler {
    const val ACTION_AUDIT_REMINDER = "com.callandt.snipemobile.AUDIT_REMINDER"
    const val EXTRA_AUDIT_INTENT = "auditIntent"
    const val INTENT_OPEN_DUE_TODAY = "openDueToday"
    private const val REQUEST_CODE = 9001
    private const val TAG = "AuditNotifScheduler"

    fun updateSchedule(context: Context, enabled: Boolean, hour: Int, minute: Int) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val pendingIntent = reminderPendingIntent(context)

        runCatching { alarmManager.cancel(pendingIntent) }
        if (!enabled) return

        val triggerAt = nextTriggerMillis(hour.coerceIn(0, 23), minute.coerceIn(0, 59))
        runCatching {
            scheduleAlarm(alarmManager, triggerAt, pendingIntent)
        }.onFailure { error ->
            Log.e(TAG, "Failed to schedule audit reminder", error)
        }
    }

    fun rescheduleFromPreferences(context: Context) {
        runCatching {
            val prefs = AppPreferences(context)
            val enabled = runBlocking { prefs.auditNotificationsEnabled.first() }
            val showAudit = runBlocking { prefs.showAuditSubtab.first() }
            val hour = runBlocking { prefs.auditNotificationHour.first() }
            val minute = runBlocking { prefs.auditNotificationMinute.first() }
            updateSchedule(context, enabled && showAudit, hour, minute)
        }.onFailure { error ->
            Log.e(TAG, "rescheduleFromPreferences failed", error)
        }
    }

    fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return false
        return alarmManager.canScheduleExactAlarms()
    }

    /** Opens system screen to grant exact-alarm permission (API 31+). */
    fun openExactAlarmSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = android.net.Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching { context.startActivity(intent) }
    }

    private fun scheduleAlarm(
        alarmManager: AlarmManager,
        triggerAt: Long,
        pendingIntent: PendingIntent,
    ) {
        val allowExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }

        if (allowExact) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } else {
                @Suppress("DEPRECATION")
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        } else {
            // Prefer inexact when exact alarms aren't allowed.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } else {
                @Suppress("DEPRECATION")
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        }
    }

    internal fun reminderPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, AuditNotificationReceiver::class.java).apply {
            action = ACTION_AUDIT_REMINDER
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    internal fun nextTriggerMillis(hour: Int, minute: Int, fromMillis: Long = System.currentTimeMillis()): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = fromMillis
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
        }
        if (cal.timeInMillis <= fromMillis) {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        }
        return cal.timeInMillis
    }
}
