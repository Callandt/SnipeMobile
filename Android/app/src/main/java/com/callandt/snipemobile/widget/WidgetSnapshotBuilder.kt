package com.callandt.snipemobile.widget

import android.content.Context
import android.net.Uri
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Component
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.data.model.SnipeDataCacheSnapshot
import com.callandt.snipemobile.ui.util.AuditDateHelper
import com.callandt.snipemobile.ui.util.AuditListFilter
import com.callandt.snipemobile.widget.glance.SnipeWidgetUpdater

/** Build widget snapshot from the local cache. */
object WidgetSnapshotBuilder {
    private const val DUE_SOON_DAYS = 7

    fun update(context: Context, snapshot: SnipeDataCacheSnapshot, baseUrl: String, isConfigured: Boolean) {
        val widgetSnapshot = build(snapshot, baseUrl, isConfigured)
        WidgetSnapshotStore.save(context, widgetSnapshot)
        SnipeWidgetUpdater.requestUpdate(context)
    }

    fun clear(context: Context) {
        WidgetSnapshotStore.clear(context)
        SnipeWidgetUpdater.requestUpdate(context)
    }

    private fun build(
        snapshot: SnipeDataCacheSnapshot,
        baseUrl: String,
        isConfigured: Boolean,
    ): WidgetSnapshot {
        val assets = snapshot.assets
        val overdue = assets.filter { AuditDateHelper.isOverdue(it) }
        val dueToday = assets.filter { AuditDateHelper.isDueToday(it) }
        val dueSoon = assets.filter { AuditDateHelper.isDueSoon(it, DUE_SOON_DAYS) }
        val sortedOverdue = AuditDateHelper.filterAssets(assets, AuditListFilter.Overdue)
        val openMaintenance = snapshot.maintenances.filter { !it.isCompleted }
        val deployedCount = assets.count { it.assignedTo != null }
        val lowStock = countLowStock(snapshot.accessories, snapshot.consumables, snapshot.components)

        return WidgetSnapshot(
            isConfigured = isConfigured,
            serverHost = hostFrom(baseUrl),
            savedAtEpochMs = System.currentTimeMillis(),
            auditsOverdue = overdue.size,
            auditsDueToday = dueToday.size,
            auditsDueSoon = dueSoon.size,
            openMaintenance = openMaintenance.size,
            totalAssets = assets.size,
            deployedAssets = deployedCount,
            lowStockItems = lowStock,
            topOverdueAudits = sortedOverdue.take(8).map {
                WidgetAuditItem(it.id, it.decodedAssetTag, it.decodedName)
            },
            topOpenMaintenance = openMaintenance.take(8).map {
                WidgetMaintenanceItem(
                    id = it.id,
                    title = it.decodedTitle,
                    assetTag = it.assetTag?.takeIf { tag -> tag.isNotBlank() },
                )
            },
            topLowStockItems = buildLowStockItems(
                snapshot.accessories,
                snapshot.consumables,
                snapshot.components,
            ).take(8),
        )
    }

    private fun hostFrom(baseUrl: String): String? =
        runCatching { Uri.parse(baseUrl).host?.takeIf { it.isNotBlank() } }.getOrNull()

    private fun countLowStock(
        accessories: List<Accessory>,
        consumables: List<Consumable>,
        components: List<Component>,
    ): Int =
        accessories.count { isLowStock(it.minAmt, it.remaining) } +
            consumables.count { isLowStock(it.minAmt, it.remaining) } +
            components.count { isLowStock(it.minAmt, it.remaining) }

    private fun isLowStock(min: Int?, remaining: Int?): Boolean {
        if (min == null || remaining == null) return false
        return remaining <= min
    }

    private fun buildLowStockItems(
        accessories: List<Accessory>,
        consumables: List<Consumable>,
        components: List<Component>,
    ): List<WidgetStockItem> {
        val items = mutableListOf<WidgetStockItem>()
        accessories.filter { isLowStock(it.minAmt, it.remaining) }.forEach { item ->
            items += WidgetStockItem(
                id = "acc-${item.id}",
                name = item.decodedName,
                remaining = item.remaining ?: 0,
                kindLabel = "Accessory",
            )
        }
        consumables.filter { isLowStock(it.minAmt, it.remaining) }.forEach { item ->
            items += WidgetStockItem(
                id = "con-${item.id}",
                name = item.decodedName,
                remaining = item.remaining ?: 0,
                kindLabel = "Consumable",
            )
        }
        components.filter { isLowStock(it.minAmt, it.remaining) }.forEach { item ->
            items += WidgetStockItem(
                id = "cmp-${item.id}",
                name = item.decodedName,
                remaining = item.remaining ?: 0,
                kindLabel = "Component",
            )
        }
        return items.sortedBy { it.remaining }
    }
}
