package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.ui.util.CardKind
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.consumableCardFields
import com.callandt.snipemobile.ui.util.resolveCard

@Composable
fun ConsumableCard(
    consumable: Consumable,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val remaining = consumable.remaining
    val qty = consumable.qty
    val resolved = resolveCard(CardKind.Consumable, LocalCardLayouts.current, consumableCardFields(consumable))

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
                    imageVector = Icons.Outlined.Inventory2,
                    imagePath = consumable.image,
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    CardLayoutHeader(resolved = resolved)
                }
                if (remaining != null || qty != null) {
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
                            text = L10n.string("remaining"),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            CardLayoutMeta(items = resolved.meta)
        }
    }
}
