package com.callandt.snipemobile.ui.components

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.callandt.snipemobile.ui.util.L10n

@Composable
fun ItemCard(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    metaLines: List<String> = emptyList(),
    statusLabel: String? = null,
    imageUrl: String? = null,
    trailing: @Composable (() -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(16.dp)
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        shape = shape,
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            if (!imageUrl.isNullOrBlank()) {
                AsyncImage(
                    model = imageUrl,
                    contentDescription = null,
                    modifier = Modifier
                        .size(48.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(MaterialTheme.colorScheme.surface),
                    contentScale = ContentScale.Crop,
                )
            }
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
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                metaLines.filter { it.isNotBlank() }.forEach { line ->
                    Text(
                        text = line,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (!statusLabel.isNullOrBlank()) {
                    Text(
                        text = statusLabel,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            trailing?.invoke()
        }
    }
}

@Composable
fun StatusChip(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))
            .padding(horizontal = 8.dp, vertical = 4.dp),
    )
}

/** Tap to copy value. */
@Composable
fun DetailRow(
    label: String,
    value: String?,
    copyValue: String? = null,
) {
    if (value.isNullOrBlank()) return
    val context = LocalContext.current
    val toCopy = copyValue ?: value

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { copyDetailValue(context, toCopy) }
            .padding(vertical = 6.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

fun copyDetailValue(context: Context, value: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText("detail", value))
    Toast.makeText(context, L10n.string("copied", value), Toast.LENGTH_SHORT).show()
}
