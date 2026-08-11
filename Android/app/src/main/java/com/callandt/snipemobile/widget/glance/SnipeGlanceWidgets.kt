package com.callandt.snipemobile.widget.glance

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.glance.GlanceId
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import com.callandt.snipemobile.widget.WidgetDestination
import com.callandt.snipemobile.widget.WidgetSnapshotStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

abstract class SnipeGlanceWidget(
    private val destination: WidgetDestination,
    private val responsiveSizes: Set<androidx.compose.ui.unit.DpSize> = overviewSizes,
) : GlanceAppWidget() {

    override val sizeMode: SizeMode = SizeMode.Responsive(responsiveSizes)

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val snapshot = WidgetSnapshotStore.load(context)
        provideContent {
            GlanceTheme {
                WidgetRoot(context = context, destination = destination) {
                    WidgetModeContent(
                        context = context,
                        destination = destination,
                        snapshot = snapshot,
                    )
                }
            }
        }
    }
}

class OverviewGlanceWidget : SnipeGlanceWidget(WidgetDestination.Overview)
class AuditsGlanceWidget : SnipeGlanceWidget(WidgetDestination.Audits)
class MaintenanceGlanceWidget : SnipeGlanceWidget(WidgetDestination.Maintenance)
class AssetsGlanceWidget : SnipeGlanceWidget(WidgetDestination.Assets, compactSizes)
class StockGlanceWidget : SnipeGlanceWidget(WidgetDestination.Stock)

class OverviewWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = OverviewGlanceWidget()
}

class AuditsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AuditsGlanceWidget()
}

class MaintenanceWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MaintenanceGlanceWidget()
}

class AssetsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AssetsGlanceWidget()
}

class StockWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = StockGlanceWidget()
}

object SnipeWidgetUpdater {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun requestUpdate(context: Context) {
        val appContext = context.applicationContext
        scope.launch {
            val manager = GlanceAppWidgetManager(appContext)
            listOf(
                OverviewGlanceWidget(),
                AuditsGlanceWidget(),
                MaintenanceGlanceWidget(),
                AssetsGlanceWidget(),
                StockGlanceWidget(),
            ).forEach { widget ->
                runCatching {
                    manager.getGlanceIds(widget.javaClass).forEach { id ->
                        widget.update(appContext, id)
                    }
                }
            }
        }
    }
}
