package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.ui.util.L10n

/** Accessory list card with qty/remaining. */
@Composable
fun AccessoryCard(
    accessory: Accessory,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    showAvailability: Boolean = true,
) {
    val remaining = accessory.remaining
    val qty = accessory.qty
    val assignee = accessory.decodedAssignedToName.takeIf { it.isNotEmpty() }
    val location = accessory.decodedLocationName.takeIf { it.isNotEmpty() }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CardListIcon(
                    imageVector = Icons.Default.Usb,
                    imagePath = accessory.image,
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = accessory.decodedName,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = L10n.string("tag_label", accessory.decodedAssetTag),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (accessory.decodedManufacturerName.isNotEmpty()) {
                        Text(
                            text = accessory.decodedManufacturerName,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                if (showAvailability && (remaining != null || qty != null)) {
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = when {
                                remaining != null && qty != null -> "$remaining/$qty"
                                remaining != null -> remaining.toString()
                                else -> qty.toString()
                            },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = if (remaining == 0) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            text = L10n.string("asset_available_short"),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            if (assignee != null || location != null) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    assignee?.let {
                        AccessoryMetaRow(icon = Icons.Default.Person, text = it)
                    }
                    location?.let {
                        AccessoryMetaRow(icon = Icons.Outlined.Place, text = it)
                    }
                }
            }

            if (assignee != null) {
                AssetCheckedOutBanner(
                    assigneeName = assignee,
                    icon = Icons.Default.Person,
                )
            }
        }
    }
}

@Composable
private fun AccessoryMetaRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
            modifier = Modifier.size(18.dp),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
        )
    }
}
