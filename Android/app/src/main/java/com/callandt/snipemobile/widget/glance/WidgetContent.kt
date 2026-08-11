package com.callandt.snipemobile.widget.glance

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.glance.GlanceModifier
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.widget.WidgetDestination
import com.callandt.snipemobile.widget.WidgetSnapshot

@Composable
internal fun WidgetModeContent(
    context: Context,
    destination: WidgetDestination,
    snapshot: WidgetSnapshot,
) {
    if (!snapshot.isConfigured) {
        UnconfiguredView()
        return
    }

    val size = currentWidgetSizeClass()
    when (destination) {
        WidgetDestination.Overview -> OverviewContent(context, snapshot, size)
        WidgetDestination.Audits -> AuditsContent(context, snapshot, size)
        WidgetDestination.Maintenance -> MaintenanceContent(context, snapshot, size)
        WidgetDestination.Assets -> AssetsContent(context, snapshot, size)
        WidgetDestination.Stock -> StockContent(context, snapshot, size)
    }
}

@Composable
private fun OverviewContent(context: Context, snapshot: WidgetSnapshot, size: WidgetSizeClass) {
    val auditStats = listOf(
        WidgetStatItem(snapshot.auditsOverdue, L10n.string("audit_status_overdue"), WidgetColors.overdueProvider, WidgetDestination.Audits),
        WidgetStatItem(snapshot.auditsDueToday, L10n.string("widget_today_short"), WidgetColors.dueTodayProvider, WidgetDestination.Audits),
        WidgetStatItem(snapshot.auditsDueSoon, L10n.string("widget_soon_short"), WidgetColors.dueSoon, WidgetDestination.Audits),
    )
    val smallAudits = auditStats.take(2)
    val otherStats = listOf(
        WidgetStatItem(snapshot.openMaintenance, L10n.string("widget_maint_open_short"), WidgetColors.maintenanceProvider, WidgetDestination.Maintenance),
        WidgetStatItem(snapshot.totalAssets, L10n.string("widget_assets_total"), WidgetColors.assetsProvider, WidgetDestination.Assets),
        WidgetStatItem(snapshot.lowStockItems, L10n.string("widget_low_stock"), WidgetColors.stockProvider, WidgetDestination.Stock),
    )
    val smallOther = listOf(
        WidgetStatItem(snapshot.openMaintenance, L10n.string("widget_maint_short"), WidgetColors.maintenanceProvider, WidgetDestination.Maintenance),
        WidgetStatItem(snapshot.totalAssets, L10n.string("widget_total_short"), WidgetColors.assetsProvider, WidgetDestination.Assets),
    )

    Column(modifier = GlanceModifier.fillMaxWidth()) {
        when (size) {
            WidgetSizeClass.Small -> {
                LabeledStatStrip(context, L10n.string("widget_audits"), smallAudits, 17, compact = true)
                Spacer(GlanceModifier.height(7.dp))
                LabeledStatStrip(context, L10n.string("widget_other"), smallOther, 17, compact = true)
            }
            WidgetSizeClass.Medium -> {
                LabeledStatStrip(context, L10n.string("widget_audits"), auditStats, 22)
                Spacer(GlanceModifier.height(8.dp))
                LabeledStatStrip(context, L10n.string("widget_other"), otherStats, 22)
            }
            WidgetSizeClass.Large -> {
                LabeledStatStrip(context, L10n.string("widget_audits"), auditStats, 24)
                Spacer(GlanceModifier.height(10.dp))
                LabeledStatStrip(context, L10n.string("widget_other"), otherStats, 24)
                Spacer(GlanceModifier.height(10.dp))
                OverviewListSection(snapshot)
                HostFooter(snapshot.serverHost)
            }
        }
    }
}

@Composable
private fun OverviewListSection(snapshot: WidgetSnapshot) {
    when {
        snapshot.topOverdueAudits.isNotEmpty() -> ItemSection(
            title = L10n.string("widget_overdue_audits"),
            rows = snapshot.topOverdueAudits.map { it.tag to it.name },
            limit = 2,
        )
        snapshot.topOpenMaintenance.isNotEmpty() -> ItemSection(
            title = L10n.string("widget_open_maintenance"),
            rows = snapshot.topOpenMaintenance.map { it.title to it.assetTag },
            limit = 2,
        )
        snapshot.topLowStockItems.isNotEmpty() -> ItemSection(
            title = L10n.string("widget_low_stock"),
            rows = snapshot.topLowStockItems.map {
                it.name to L10n.string("widget_remaining_count", it.remaining)
            },
            limit = 2,
        )
        else -> EmptyStateCard(L10n.string("widget_no_urgent_actions"))
    }
}

@Composable
private fun AuditsContent(context: Context, snapshot: WidgetSnapshot, size: WidgetSizeClass) {
    val auditStats = listOf(
        WidgetStatItem(snapshot.auditsOverdue, L10n.string("audit_status_overdue"), WidgetColors.overdueProvider, WidgetDestination.Audits),
        WidgetStatItem(snapshot.auditsDueToday, L10n.string("widget_today_short"), WidgetColors.dueTodayProvider, WidgetDestination.Audits),
        WidgetStatItem(snapshot.auditsDueSoon, L10n.string("widget_soon_short"), WidgetColors.dueSoon, WidgetDestination.Audits),
    )
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        when (size) {
            WidgetSizeClass.Small -> SmallMetricPanel(context, L10n.string("widget_audits"), auditStats)
            WidgetSizeClass.Medium -> LabeledStatStrip(context, L10n.string("widget_audits"), auditStats, 24)
            WidgetSizeClass.Large -> {
                LabeledStatStrip(context, L10n.string("widget_audits"), auditStats, 28)
                if (snapshot.topOverdueAudits.isNotEmpty()) {
                    Spacer(GlanceModifier.height(8.dp))
                    ItemSection(
                        title = L10n.string("widget_overdue_audits"),
                        rows = snapshot.topOverdueAudits.map { it.tag to it.name },
                        limit = 4,
                    )
                }
                HostFooter(snapshot.serverHost)
            }
        }
    }
}

@Composable
private fun MaintenanceContent(context: Context, snapshot: WidgetSnapshot, size: WidgetSizeClass) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        when (size) {
            WidgetSizeClass.Small -> FocusNumber(
                value = snapshot.openMaintenance,
                label = L10n.string("maintenance"),
                caption = L10n.string("widget_open_tasks"),
                color = WidgetColors.maintenanceProvider,
                compact = true,
            )
            WidgetSizeClass.Medium -> FocusNumber(
                value = snapshot.openMaintenance,
                label = L10n.string("widget_maintenance_open"),
                caption = snapshot.topOpenMaintenance.firstOrNull()?.title ?: "—",
                color = WidgetColors.maintenanceProvider,
            )
            WidgetSizeClass.Large -> {
                StatStrip(
                    context = context,
                    items = listOf(
                        WidgetStatItem(
                            snapshot.openMaintenance,
                            L10n.string("widget_open_short"),
                            WidgetColors.maintenanceProvider,
                        ),
                    ),
                    valueSizeSp = 28,
                )
                Spacer(GlanceModifier.height(8.dp))
                ItemSection(
                    title = L10n.string("widget_open_tasks"),
                    rows = snapshot.topOpenMaintenance.map { it.title to it.assetTag },
                    limit = 4,
                )
                HostFooter(snapshot.serverHost)
            }
        }
    }
}

@Composable
private fun AssetsContent(context: Context, snapshot: WidgetSnapshot, size: WidgetSizeClass) {
    val stats = listOf(
        WidgetStatItem(snapshot.totalAssets, L10n.string("widget_total_short"), WidgetColors.assetsProvider),
        WidgetStatItem(snapshot.deployedAssets, L10n.string("widget_deployed_short"), WidgetColors.dueTodayProvider),
        WidgetStatItem(snapshot.availableAssets, L10n.string("widget_available_short"), WidgetColors.availableProvider),
    )
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        when (size) {
            WidgetSizeClass.Small -> FocusNumber(
                value = snapshot.totalAssets,
                label = L10n.string("widget_assets_name"),
                caption = L10n.string("widget_deployed_caption", formatWidgetCount(snapshot.deployedAssets)),
                color = WidgetColors.assetsProvider,
                compact = true,
            )
            WidgetSizeClass.Medium, WidgetSizeClass.Large -> LabeledStatStrip(
                context = context,
                title = L10n.string("widget_assets_name"),
                items = stats,
                valueSizeSp = if (size == WidgetSizeClass.Large) 26 else 22,
            )
        }
    }
}

@Composable
private fun StockContent(context: Context, snapshot: WidgetSnapshot, size: WidgetSizeClass) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        when (size) {
            WidgetSizeClass.Small -> FocusNumber(
                value = snapshot.lowStockItems,
                label = L10n.string("tab_stock"),
                caption = L10n.string("widget_low_stock"),
                color = WidgetColors.stockProvider,
                compact = true,
            )
            WidgetSizeClass.Medium -> FocusNumber(
                value = snapshot.lowStockItems,
                label = L10n.string("widget_low_stock"),
                caption = L10n.string("widget_below_minimum"),
                color = WidgetColors.stockProvider,
            )
            WidgetSizeClass.Large -> {
                StatStrip(
                    context = context,
                    items = listOf(
                        WidgetStatItem(
                            snapshot.lowStockItems,
                            L10n.string("widget_low_stock"),
                            WidgetColors.stockProvider,
                        ),
                    ),
                    valueSizeSp = 28,
                )
                Spacer(GlanceModifier.height(8.dp))
                ItemSection(
                    title = L10n.string("widget_items"),
                    rows = snapshot.topLowStockItems.map {
                        it.name to L10n.string("widget_remaining_count", it.remaining)
                    },
                    limit = 4,
                )
                HostFooter(snapshot.serverHost)
            }
        }
    }
}
