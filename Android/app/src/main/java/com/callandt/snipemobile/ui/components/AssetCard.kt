package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.Label
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetCardLocationName
import com.callandt.snipemobile.ui.util.assetCardTitle
import com.callandt.snipemobile.ui.util.assetCheckedOutAssignee
import com.callandt.snipemobile.ui.util.assetCheckedOutIcon
import com.callandt.snipemobile.ui.util.assetResolvedStatus

/** Asset list card. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetCard(
    asset: Asset,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    showNextAuditDate: Boolean = false,
) {
    val title = assetCardTitle(asset)
    val showAssetName = asset.decodedName.isNotEmpty() && asset.decodedName != title
    val locationName = assetCardLocationName(asset)
    val assignee = assetCheckedOutAssignee(asset)
    val status = assetResolvedStatus(asset)

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
                verticalAlignment = Alignment.Top,
            ) {
                Icon(
                    imageVector = Icons.Default.Laptop,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
                    modifier = Modifier.size(36.dp),
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            text = L10n.string("tag_label", asset.decodedAssetTag),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (asset.decodedSerial.isNotEmpty()) {
                            Text(
                                text = "${L10n.string("sn_label")} ${asset.decodedSerial}",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f, fill = false),
                            )
                        }
                    }
                    if (!status.isNullOrBlank()) {
                        Text(
                            text = status,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (showNextAuditDate) {
                        val next = asset.nextAuditDate?.formatted
                            ?: asset.nextAuditDate?.localizedDisplay(includeTime = false)
                        if (!next.isNullOrBlank()) {
                            Text(
                                text = "${L10n.string("next_audit_date")}: $next",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            if (showAssetName || locationName != null) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (showAssetName) {
                        MetaIconRow(
                            icon = Icons.Outlined.Label,
                            text = asset.decodedName,
                        )
                    }
                    if (locationName != null) {
                        MetaIconRow(
                            icon = Icons.Outlined.Place,
                            text = locationName,
                        )
                    }
                }
            }

            if (assignee != null) {
                AssetCheckedOutBanner(
                    assigneeName = assignee,
                    icon = assetCheckedOutIcon(asset),
                )
            }
        }
    }
}

@Composable
private fun MetaIconRow(icon: ImageVector, text: String) {
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetCheckedOutBanner(
    assigneeName: String,
    icon: ImageVector,
    onClick: (() -> Unit)? = null,
) {
    val accent = MaterialTheme.colorScheme.primary
    val shape = RoundedCornerShape(12.dp)
    val content: @Composable () -> Unit = {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = accent,
                modifier = Modifier
                    .size(34.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(accent.copy(alpha = 0.14f))
                    .padding(8.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = L10n.string("checked_out_to"),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = assigneeName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Spacer(modifier = Modifier.width(0.dp))
        }
    }

    if (onClick != null) {
        Surface(
            onClick = onClick,
            modifier = Modifier.fillMaxWidth(),
            shape = shape,
            color = accent.copy(alpha = 0.08f),
        ) {
            content()
        }
    } else {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(accent.copy(alpha = 0.08f)),
        ) {
            content()
        }
    }
}

fun defaultCheckedOutIcon(): ImageVector = Icons.Default.Person
fun locationCheckedOutIcon(): ImageVector = Icons.Default.LocationOn
fun assetCheckedOutIconVector(): ImageVector = Icons.Default.Laptop
