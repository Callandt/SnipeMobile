package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.util.HtmlDecoder
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeGreen
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetCheckedOutAssignee

/** Maintenance list card. */
@Composable
fun MaintenanceCard(
    record: AssetMaintenance,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    linkedAsset: Asset? = null,
    showAssetHeader: Boolean = false,
) {
    val accent = if (record.isCompleted) SnipeGreen else SnipeOrange
    val assetInfo = if (showAssetHeader) {
        MaintenanceLinkedAssetInfo.resolve(record, linkedAsset)
    } else {
        null
    }

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            if (assetInfo != null) {
                MaintenanceAssetHeader(info = assetInfo)
                HorizontalDivider(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                )
            }

            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CardListIcon(
                        imageVector = Icons.Default.Build,
                        imagePath = record.image,
                        cacheBuster = record.updatedAt?.datetime ?: record.updatedAt?.date,
                        size = 40.dp,
                        cornerRadius = 12.dp,
                        tint = accent,
                        iconBackground = accent.copy(alpha = 0.12f),
                        iconPadding = 10.dp,
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        Text(
                            text = record.decodedTitle,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        record.displayType?.takeIf { it.isNotBlank() }?.let { type ->
                            Text(
                                text = type,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                    record.cost?.takeIf { it.isNotBlank() }?.let { cost ->
                        Text(
                            text = cost,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }

                dateRangeText(record)?.let { range ->
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Default.CalendarMonth,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            text = range,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (record.isCompleted) {
                        StatusCapsule(
                            icon = Icons.Default.CheckCircle,
                            text = L10n.string("status_completed"),
                            color = SnipeGreen,
                        )
                    } else {
                        StatusCapsule(
                            icon = Icons.Default.Schedule,
                            text = L10n.string("in_progress"),
                            color = SnipeOrange,
                        )
                    }
                    if (record.isWarranty) {
                        StatusCapsule(
                            icon = Icons.Default.VerifiedUser,
                            text = L10n.string("is_warranty"),
                            color = SnipeAccent,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MaintenanceAssetHeader(info: MaintenanceLinkedAssetInfo) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CardListIcon(
            imageVector = Icons.Default.Laptop,
            imagePath = info.imagePath,
            size = 34.dp,
            cornerRadius = 10.dp,
            tint = SnipeAccent,
            iconBackground = SnipeAccent.copy(alpha = 0.12f),
            iconPadding = 8.dp,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = info.title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            info.detailLine?.let { detail ->
                Text(
                    text = detail,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        info.assignee?.let { assignee ->
            Row(
                modifier = Modifier
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.06f))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(12.dp),
                )
                Text(
                    text = assignee,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun StatusCapsule(icon: ImageVector, text: String, color: Color) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(12.dp),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
    }
}

private fun dateRangeText(record: AssetMaintenance): String? {
    val start = record.startDate?.formatted?.takeIf { it.isNotBlank() }
        ?: record.startDate?.localizedDisplay(includeTime = false)?.takeIf { it.isNotBlank() }
        ?: return null
    val end = record.completionDate?.formatted?.takeIf { it.isNotBlank() }
        ?: record.completionDate?.localizedDisplay(includeTime = false)?.takeIf { it.isNotBlank() }
    return if (end != null) {
        "$start  →  $end"
    } else {
        "$start  →  ${L10n.string("in_progress")}"
    }
}

data class MaintenanceLinkedAssetInfo(
    val title: String,
    val detailLine: String?,
    val assignee: String?,
    val imagePath: String? = null,
) {
    companion object {
        fun resolve(record: AssetMaintenance, asset: Asset?): MaintenanceLinkedAssetInfo? {
            if (asset != null) return from(asset)
            return from(record)
        }

        private fun from(asset: Asset): MaintenanceLinkedAssetInfo? {
            val model = asset.decodedModelName
            val name = asset.decodedName
            val tag = asset.decodedAssetTag
            val title = when {
                model.isNotEmpty() -> model
                name.isNotEmpty() -> name
                tag.isNotEmpty() -> tag
                else -> return null
            }
            val details = buildList {
                if (tag.isNotEmpty() && title != tag) add(L10n.string("tag_label", tag))
                if (name.isNotEmpty() && model.isNotEmpty() && name != model && title != name) add(name)
            }
            return MaintenanceLinkedAssetInfo(
                title = title,
                detailLine = details.takeIf { it.isNotEmpty() }?.joinToString(" · "),
                assignee = assetCheckedOutAssignee(asset),
                imagePath = asset.image,
            )
        }

        private fun from(record: AssetMaintenance): MaintenanceLinkedAssetInfo? {
            val tag = record.assetTag
                ?.let { HtmlDecoder.decode(it) }
                ?.takeIf { it.isNotEmpty() }
            val name = record.assetName
                ?.let { HtmlDecoder.decode(it) }
                ?.takeIf { it.isNotEmpty() }
            return when {
                name != null && tag != null && name != tag ->
                    MaintenanceLinkedAssetInfo(name, L10n.string("tag_label", tag), null)
                name != null -> MaintenanceLinkedAssetInfo(name, null, null)
                tag != null -> MaintenanceLinkedAssetInfo(tag, null, null)
                else -> null
            }
        }
    }
}
