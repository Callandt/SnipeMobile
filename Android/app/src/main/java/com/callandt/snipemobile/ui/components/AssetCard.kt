package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.ui.util.CardKind
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetCardFields
import com.callandt.snipemobile.ui.util.assetCardLocationName
import com.callandt.snipemobile.ui.util.assetCheckedOutAssignee
import com.callandt.snipemobile.ui.util.assetCheckedOutIcon
import com.callandt.snipemobile.ui.util.assetResolvedStatus
import com.callandt.snipemobile.ui.util.resolveCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetCard(
    asset: Asset,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    showNextAuditDate: Boolean = false,
    onLongClick: (() -> Unit)? = null,
    footer: (@Composable () -> Unit)? = null,
) {
    val layouts = LocalCardLayouts.current
    val locationName = assetCardLocationName(asset)
    val assignee = assetCheckedOutAssignee(asset)
    val status = assetResolvedStatus(asset)
    val resolved = resolveCard(
        CardKind.Asset,
        layouts,
        assetCardFields(asset, locationName, status),
    )

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .then(
                        if (onLongClick != null) {
                            Modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick)
                        } else {
                            Modifier.clickable(onClick = onClick)
                        },
                    ),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CardListIcon(
                        imageVector = Icons.Default.Laptop,
                        imagePath = asset.image,
                        cacheBuster = asset.updatedAt?.datetime ?: asset.updatedAt?.date,
                    )
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        val extra = if (showNextAuditDate) {
                            val next = asset.nextAuditDate?.formatted
                                ?: asset.nextAuditDate?.localizedDisplay(includeTime = false)
                            listOfNotNull(next?.takeIf { it.isNotBlank() }?.let { "${L10n.string("next_audit_date")}: $it" })
                        } else {
                            emptyList()
                        }
                        CardLayoutHeader(resolved = resolved, extraLines = extra)
                    }
                }

                CardLayoutMeta(items = resolved.meta)

                if (assignee != null) {
                    AssetCheckedOutBanner(
                        assigneeName = assignee,
                        icon = assetCheckedOutIcon(asset),
                    )
                }
            }

            footer?.invoke()
        }
    }
}

@Composable
fun AssetCompactNameColumn(
    asset: Asset,
    modifier: Modifier = Modifier,
    titleStyle: TextStyle = MaterialTheme.typography.bodyMedium,
) {
    val layouts = LocalCardLayouts.current
    val resolved = resolveCard(CardKind.Asset, layouts, assetCardFields(asset))
    Column(modifier = modifier) {
        Text(
            text = resolved.title,
            style = titleStyle,
        )
        val subtitle = listOfNotNull(resolved.subtitle).plus(resolved.headerLines)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
        if (subtitle.isNotEmpty()) {
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetCheckedOutBanner(
    assigneeName: String,
    icon: ImageVector,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
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

    val interaction = when {
        onLongClick != null -> Modifier.combinedClickable(
            onClick = onClick ?: {},
            onLongClick = onLongClick,
        )
        onClick != null -> Modifier.clickable(onClick = onClick)
        else -> Modifier
    }
    Surface(
        modifier = Modifier.fillMaxWidth().then(interaction),
        shape = shape,
        color = accent.copy(alpha = 0.08f),
    ) {
        content()
    }
}

fun defaultCheckedOutIcon(): ImageVector = Icons.Default.Person
fun locationCheckedOutIcon(): ImageVector = Icons.Default.LocationOn
fun assetCheckedOutIconVector(): ImageVector = Icons.Default.Laptop
