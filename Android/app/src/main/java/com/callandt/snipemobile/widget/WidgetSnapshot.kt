package com.callandt.snipemobile.widget

import kotlinx.serialization.Serializable

@Serializable
data class WidgetAuditItem(
    val id: Int,
    val tag: String,
    val name: String,
)

@Serializable
data class WidgetMaintenanceItem(
    val id: Int,
    val title: String,
    val assetTag: String? = null,
)

@Serializable
data class WidgetStockItem(
    val id: String,
    val name: String,
    val remaining: Int,
    val kindLabel: String,
)

@Serializable
data class WidgetSnapshot(
    val isConfigured: Boolean = false,
    val serverHost: String? = null,
    val savedAtEpochMs: Long = 0L,
    val auditsOverdue: Int = 0,
    val auditsDueToday: Int = 0,
    val auditsDueSoon: Int = 0,
    val openMaintenance: Int = 0,
    val totalAssets: Int = 0,
    val deployedAssets: Int = 0,
    val lowStockItems: Int = 0,
    val topOverdueAudits: List<WidgetAuditItem> = emptyList(),
    val topOpenMaintenance: List<WidgetMaintenanceItem> = emptyList(),
    val topLowStockItems: List<WidgetStockItem> = emptyList(),
) {
    val hasData: Boolean get() = isConfigured && totalAssets > 0
    val availableAssets: Int get() = maxOf(totalAssets - deployedAssets, 0)
    val hasActionItems: Boolean
        get() = topOverdueAudits.isNotEmpty() ||
            topOpenMaintenance.isNotEmpty() ||
            topLowStockItems.isNotEmpty()

    companion object {
        val empty = WidgetSnapshot()
    }
}

/** Persists widget data to app-private storage. */
object WidgetSnapshotStore {
    private const val FILE_NAME = "widget_snapshot.json"

    fun load(context: android.content.Context): WidgetSnapshot {
        val file = context.filesDir.resolve(FILE_NAME)
        if (!file.exists()) return WidgetSnapshot.empty
        return runCatching {
            com.callandt.snipemobile.data.model.SnipeJson.decodeFromString(
                WidgetSnapshot.serializer(),
                file.readText(),
            )
        }.getOrDefault(WidgetSnapshot.empty)
    }

    fun save(context: android.content.Context, snapshot: WidgetSnapshot) {
        runCatching {
            val data = com.callandt.snipemobile.data.model.SnipeJson.encodeToString(snapshot)
            context.filesDir.resolve(FILE_NAME).writeText(data)
        }
    }

    fun clear(context: android.content.Context) {
        context.filesDir.resolve(FILE_NAME).delete()
    }
}
