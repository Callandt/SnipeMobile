package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Label
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.AlternateEmail
import androidx.compose.material.icons.outlined.Badge
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Category
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Factory
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Numbers
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.util.CardKind
import com.callandt.snipemobile.ui.util.CardLayoutPreview
import com.callandt.snipemobile.ui.util.CardLayoutResolver
import com.callandt.snipemobile.ui.util.CardLayoutStore
import com.callandt.snipemobile.ui.util.CardSlotLayout
import com.callandt.snipemobile.ui.util.ResolvedCardLayout
import com.callandt.snipemobile.ui.util.ResolvedCardMeta

val LocalCardLayouts = compositionLocalOf { CardLayoutStore.Empty }

fun cardFieldIcon(name: String): ImageVector = when (name) {
    "tag" -> Icons.AutoMirrored.Outlined.Label
    "barcode" -> Icons.Outlined.QrCode
    "model" -> Icons.Default.Laptop
    "serial", "number" -> Icons.Outlined.Numbers
    "status" -> Icons.Outlined.Info
    "location" -> Icons.Outlined.Place
    "person" -> Icons.Default.Person
    "email" -> Icons.Outlined.Email
    "job" -> Icons.Outlined.Badge
    "username" -> Icons.Outlined.AlternateEmail
    "manufacturer" -> Icons.Outlined.Factory
    "category" -> Icons.Outlined.Category
    "calendar" -> Icons.Outlined.CalendarMonth
    "info" -> Icons.Outlined.Info
    "pin" -> Icons.Outlined.PushPin
    "phone" -> Icons.Outlined.Phone
    else -> Icons.Outlined.Info
}

@Composable
fun CardLayoutHeader(
    resolved: ResolvedCardLayout,
    extraLines: List<String> = emptyList(),
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (resolved.title.isNotEmpty()) {
            Text(
                text = resolved.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        resolved.subtitle?.let { subtitle ->
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        resolved.headerLines.forEach { line ->
            Text(
                text = line,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        extraLines.filter { it.isNotBlank() }.forEach { line ->
            Text(
                text = line,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
            )
        }
    }
}

@Composable
fun CardLayoutMeta(items: List<ResolvedCardMeta>) {
    if (items.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        items.forEach { item ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(
                    imageVector = cardFieldIcon(item.icon),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    text = item.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                )
            }
        }
    }
}

@Composable
fun CardLayoutPreviewCard(
    kind: CardKind,
    layout: CardSlotLayout,
    kindIcon: ImageVector,
    modifier: Modifier = Modifier,
) {
    val resolved = CardLayoutResolver.resolve(kind, layout, CardLayoutPreview.fields(kind))
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = kindIcon,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
                    modifier = Modifier.size(36.dp),
                )
                CardLayoutHeader(resolved = resolved)
            }
            CardLayoutMeta(items = resolved.meta)
        }
    }
}
