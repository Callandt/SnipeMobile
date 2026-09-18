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
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.ui.util.CardKind
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.licenseCardFields
import com.callandt.snipemobile.ui.util.resolveCard

@Composable
fun LicenseCard(
    license: License,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    showSeats: Boolean = true,
) {
    val totalSeats = license.seats
    val freeSeats = license.freeSeatsCount ?: license.remaining
    val resolved = resolveCard(CardKind.License, LocalCardLayouts.current, licenseCardFields(license))

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
                    imageVector = Icons.Default.Description,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
                    modifier = Modifier.size(36.dp),
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    CardLayoutHeader(resolved = resolved)
                }
                if (showSeats && totalSeats != null && freeSeats != null) {
                    Column(horizontalAlignment = Alignment.End) {
                        Text(
                            text = "$freeSeats/$totalSeats",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = if (freeSeats <= 0) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurface,
                        )
                        Text(
                            text = L10n.string("license_seats_free"),
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
