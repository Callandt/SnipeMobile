package com.callandt.snipemobile.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.callandt.snipemobile.MainActivity

enum class WidgetDestination(val path: String) {
    Overview("overview"),
    Audits("audits"),
    Maintenance("maintenance"),
    Assets("assets"),
    Stock("stock"),
    ;

    val uri: Uri get() = Uri.parse("snipemobile://widget/$path")

    companion object {
        const val EXTRA_DESTINATION = "widget_destination"

        fun fromUri(uri: Uri?): WidgetDestination? {
            if (uri == null) return null
            if (uri.scheme?.equals("snipemobile", ignoreCase = true) != true) return null
            val host = uri.host?.lowercase().orEmpty()
            if (host == "widget") {
                val segment = uri.pathSegments.lastOrNull()?.lowercase()
                return entries.firstOrNull { it.path == segment }
            }
            return entries.firstOrNull { it.path == host }
        }

        fun fromIntent(intent: Intent?): WidgetDestination? {
            intent ?: return null
            fromUri(intent.data)?.let { return it }
            val raw = intent.getStringExtra(EXTRA_DESTINATION) ?: return null
            return entries.firstOrNull { it.path == raw || it.name.equals(raw, ignoreCase = true) }
        }
    }
}

fun widgetOpenIntent(context: Context, destination: WidgetDestination): Intent =
    Intent(context, MainActivity::class.java).apply {
        action = Intent.ACTION_VIEW
        data = destination.uri
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(WidgetDestination.EXTRA_DESTINATION, destination.path)
    }
