package com.callandt.snipemobile.widget.glance

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.widget.WidgetDestination
import com.callandt.snipemobile.widget.widgetOpenIntent
import java.text.NumberFormat
import java.util.Locale

internal enum class WidgetSizeClass { Small, Medium, Large }

@Composable
internal fun currentWidgetSizeClass(): WidgetSizeClass {
    val size = LocalSize.current
    return when {
        size.height >= 250.dp || (size.width >= 250.dp && size.height >= 200.dp) -> WidgetSizeClass.Large
        size.width >= 250.dp -> WidgetSizeClass.Medium
        else -> WidgetSizeClass.Small
    }
}

internal data class WidgetStatItem(
    val value: Int,
    val label: String,
    val color: ColorProvider,
    val destination: WidgetDestination? = null,
)

internal fun formatWidgetCount(value: Int): String =
    NumberFormat.getIntegerInstance(Locale.getDefault()).format(value)

@Composable
internal fun WidgetRoot(
    context: Context,
    destination: WidgetDestination,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetColors.pageBackground)
            .clickable(actionStartActivity(widgetOpenIntent(context, destination)))
            .padding(horizontal = 12.dp, vertical = 12.dp),
    ) {
        content()
    }
}

@Composable
internal fun UnconfiguredView() {
    Column(
        modifier = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = L10n.string("widget_connect"),
            style = TextStyle(
                color = WidgetColors.brand,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

@Composable
internal fun SectionHeader(title: String) {
    Text(
        text = title,
        style = TextStyle(
            color = WidgetColors.brand,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
        ),
        modifier = GlanceModifier.padding(bottom = 4.dp),
    )
}

@Composable
internal fun StatStrip(
    context: Context,
    items: List<WidgetStatItem>,
    valueSizeSp: Int,
    compact: Boolean = false,
) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .background(WidgetColors.cardBackground)
            .padding(vertical = if (compact) 7.dp else 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for ((index, item) in items.withIndex()) {
            var cellModifier = GlanceModifier.defaultWeight()
            if (item.destination != null) {
                cellModifier = cellModifier.clickable(
                    actionStartActivity(widgetOpenIntent(context, item.destination)),
                )
            }
            Column(
                modifier = cellModifier.padding(horizontal = 4.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = formatWidgetCount(item.value),
                    style = TextStyle(
                        color = WidgetColors.primaryText,
                        fontSize = valueSizeSp.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                    ),
                    maxLines = 1,
                )
                Spacer(GlanceModifier.height(if (compact) 2.dp else 4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Spacer(
                        modifier = GlanceModifier
                            .size(5.dp)
                            .background(item.color),
                    )
                    Spacer(GlanceModifier.width(3.dp))
                    Text(
                        text = item.label,
                        style = TextStyle(
                            color = WidgetColors.secondaryText,
                            fontSize = if (compact) 8.sp else 9.sp,
                            fontWeight = FontWeight.Medium,
                            textAlign = TextAlign.Center,
                        ),
                        maxLines = 1,
                    )
                }
            }
            if (index < items.lastIndex) {
                Spacer(
                    modifier = GlanceModifier
                        .width(1.dp)
                        .fillMaxHeight()
                        .padding(vertical = if (compact) 4.dp else 6.dp)
                        .background(WidgetColors.separator),
                )
            }
        }
    }
}

@Composable
internal fun LabeledStatStrip(
    context: Context,
    title: String,
    items: List<WidgetStatItem>,
    valueSizeSp: Int,
    compact: Boolean = false,
) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        SectionHeader(title)
        StatStrip(context, items, valueSizeSp, compact)
    }
}

@Composable
internal fun SmallMetricPanel(
    context: Context,
    title: String,
    items: List<WidgetStatItem>,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetColors.cardBackground)
            .padding(10.dp),
    ) {
        SectionHeader(title)
        items.forEachIndexed { index, item ->
            val rowModifier = if (item.destination != null) {
                GlanceModifier.clickable(actionStartActivity(widgetOpenIntent(context, item.destination)))
            } else {
                GlanceModifier
            }
            Row(
                modifier = rowModifier
                    .fillMaxWidth()
                    .padding(vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(GlanceModifier.size(6.dp).background(item.color))
                Spacer(GlanceModifier.width(7.dp))
                Text(
                    text = item.label,
                    style = TextStyle(
                        color = WidgetColors.secondaryText,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    modifier = GlanceModifier.defaultWeight(),
                    maxLines = 1,
                )
                Text(
                    text = formatWidgetCount(item.value),
                    style = TextStyle(
                        color = WidgetColors.primaryText,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    maxLines = 1,
                )
            }
            if (index < items.lastIndex) {
                Spacer(
                    GlanceModifier
                        .fillMaxWidth()
                        .height(1.dp)
                        .padding(start = 13.dp)
                        .background(WidgetColors.separator),
                )
            }
        }
    }
}

@Composable
internal fun FocusNumber(
    value: Int,
    label: String,
    caption: String,
    color: ColorProvider,
    compact: Boolean = false,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(WidgetColors.cardBackground)
            .padding(if (compact) 10.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(GlanceModifier.size(7.dp).background(color))
            Spacer(GlanceModifier.width(6.dp))
            Text(
                text = label,
                style = TextStyle(
                    color = WidgetColors.brand,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        }
        Spacer(GlanceModifier.height(4.dp))
        Text(
            text = formatWidgetCount(value),
            style = TextStyle(
                color = WidgetColors.primaryText,
                fontSize = if (compact) 30.sp else 36.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
        Text(
            text = caption,
            style = TextStyle(
                color = WidgetColors.secondaryText,
                fontSize = 11.sp,
            ),
            maxLines = 1,
        )
    }
}

@Composable
internal fun ItemSection(
    title: String,
    rows: List<Pair<String, String?>>,
    limit: Int,
) {
    if (rows.isEmpty()) return
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        Text(
            text = title.uppercase(Locale.getDefault()),
            style = TextStyle(
                color = WidgetColors.secondaryText,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
            ),
            modifier = GlanceModifier.padding(bottom = 5.dp),
        )
        Column(
            modifier = GlanceModifier
                .fillMaxWidth()
                .background(WidgetColors.cardBackground),
        ) {
            rows.take(limit).forEachIndexed { index, row ->
                Column(
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                ) {
                    Text(
                        text = row.first,
                        style = TextStyle(
                            color = WidgetColors.primaryText,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        maxLines = 1,
                    )
                    row.second?.takeIf { it.isNotBlank() }?.let { secondary ->
                        Text(
                            text = secondary,
                            style = TextStyle(
                                color = WidgetColors.secondaryText,
                                fontSize = 10.sp,
                            ),
                            maxLines = 1,
                        )
                    }
                }
                if (index < minOf(rows.size, limit) - 1) {
                    Spacer(
                        GlanceModifier
                            .fillMaxWidth()
                            .height(1.dp)
                            .padding(start = 12.dp)
                            .background(WidgetColors.separator),
                    )
                }
            }
        }
    }
}

@Composable
internal fun EmptyStateCard(message: String) {
    Text(
        text = message,
        style = TextStyle(
            color = WidgetColors.secondaryText,
            fontSize = 11.sp,
        ),
        modifier = GlanceModifier
            .fillMaxWidth()
            .background(WidgetColors.cardBackground)
            .padding(8.dp),
    )
}

@Composable
internal fun HostFooter(host: String?) {
    if (host.isNullOrBlank()) return
    Text(
        text = host,
        style = TextStyle(
            color = WidgetColors.tertiaryText,
            fontSize = 9.sp,
            textAlign = TextAlign.End,
        ),
        modifier = GlanceModifier.fillMaxWidth().padding(top = 4.dp),
        maxLines = 1,
    )
}

internal val overviewSizes = setOf(
    DpSize(110.dp, 110.dp),
    DpSize(250.dp, 110.dp),
    DpSize(250.dp, 280.dp),
)

internal val compactSizes = setOf(
    DpSize(110.dp, 110.dp),
    DpSize(250.dp, 110.dp),
)
