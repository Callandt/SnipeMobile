package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.api.SnipeApiClient
import com.callandt.snipemobile.data.model.Activity
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeGreen
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.theme.SnipeRed
import com.callandt.snipemobile.ui.util.L10n

private val TimelineDotSize = 12.dp
private val TimelineGutter = 28.dp
private val CardCorner = 14.dp

/** Activity timeline list. */
@Composable
fun ActivityTimelineList(
    activities: List<Activity>,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(horizontal = 20.dp, vertical = 24.dp),
    showItemType: Boolean = false,
    preferItemHeadline: Boolean = false,
    apiClient: SnipeApiClient? = null,
    fileObjectType: String? = null,
    fileObjectId: Int? = null,
    onFileClick: ((Activity) -> Unit)? = null,
    footer: (LazyListScope.() -> Unit)? = null,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = contentPadding,
    ) {
        itemsIndexed(activities, key = { _, activity -> activity.id }) { index, activity ->
            ActivityTimelineRow(
                activity = activity,
                isLast = index == activities.lastIndex && footer == null,
                showItemType = showItemType,
                preferItemHeadline = preferItemHeadline,
                apiClient = apiClient,
                fileObjectType = fileObjectType,
                fileObjectId = fileObjectId,
                onFileClick = onFileClick,
            )
        }
        footer?.invoke(this)
    }
}

@Composable
fun ActivityTimelineLoading(modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator()
            Text(
                text = L10n.string("loading_history"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun ActivityTimelineEmpty(modifier: Modifier = Modifier) {
    EmptyState(
        title = L10n.string("no_history"),
        icon = Icons.Default.History,
        modifier = modifier,
    )
}

@Composable
fun ActivityTimelineRow(
    activity: Activity,
    isLast: Boolean,
    modifier: Modifier = Modifier,
    showItemType: Boolean = false,
    preferItemHeadline: Boolean = false,
    apiClient: SnipeApiClient? = null,
    fileObjectType: String? = null,
    fileObjectId: Int? = null,
    onFileClick: ((Activity) -> Unit)? = null,
) {
    val actionColor = activityActionColor(activity.actionType)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min),
        horizontalArrangement = Arrangement.spacedBy(0.dp),
    ) {
        Box(
            modifier = Modifier
                .width(TimelineGutter)
                .fillMaxHeight()
                .padding(top = 6.dp),
            contentAlignment = Alignment.TopCenter,
        ) {
            if (!isLast) {
                Box(
                    modifier = Modifier
                        .width(2.dp)
                        .fillMaxHeight()
                        .padding(top = TimelineDotSize / 2)
                        .background(SnipeAccent.copy(alpha = 0.25f), RoundedCornerShape(1.dp)),
                )
            }
            Box(
                modifier = Modifier
                    .size(TimelineDotSize)
                    .clip(CircleShape)
                    .background(actionColor)
                    .border(2.5.dp, MaterialTheme.colorScheme.background, CircleShape),
            )
        }

        ActivityTimelineCard(
            activity = activity,
            showItemType = showItemType,
            preferItemHeadline = preferItemHeadline,
            apiClient = apiClient,
            fileObjectType = fileObjectType,
            fileObjectId = fileObjectId,
            onFileClick = onFileClick,
            modifier = Modifier
                .weight(1f)
                .padding(bottom = 24.dp),
        )
    }
}

@Composable
fun ActivityTimelineCard(
    activity: Activity,
    modifier: Modifier = Modifier,
    showItemType: Boolean = false,
    preferItemHeadline: Boolean = false,
    apiClient: SnipeApiClient? = null,
    fileObjectType: String? = null,
    fileObjectId: Int? = null,
    onFileClick: ((Activity) -> Unit)? = null,
) {
    val actionColor = activityActionColor(activity.actionType)
    val whenText = activity.createdAt?.localizedDisplay(includeTime = true).orEmpty()
    val actor = activity.admin?.decodedName?.takeIf { it.isNotBlank() }
        ?: activity.createdBy?.decodedName?.takeIf { it.isNotBlank() }
    val headline = activityHeadline(activity, preferItemHeadline)
    val isCheckout = isCheckoutAction(activity.actionType)
    val targetName = activity.target?.decodedName?.takeIf { it.isNotBlank() }
    val file = activity.file

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(CardCorner))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .border(
                width = 0.5.dp,
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                shape = RoundedCornerShape(CardCorner),
            )
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = activityActionLabel(activity.actionType),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = actionColor,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .background(actionColor.copy(alpha = 0.12f))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
            )
            Spacer(Modifier.weight(1f))
            if (whenText.isNotEmpty()) {
                Text(
                    text = whenText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        val thumbType = fileObjectType ?: activity.item?.type
        val thumbId = fileObjectId ?: activity.item?.id
        val thumbClient = apiClient
        val imageFile = file?.takeIf { it.isImage }

        if (thumbClient != null && imageFile != null && thumbType != null && thumbId != null) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                SnipeFileThumbnail(
                    apiClient = thumbClient,
                    objectType = thumbType,
                    objectId = thumbId,
                    fileId = activity.id,
                    filename = imageFile.decodedFilename,
                    size = 64.dp,
                    cornerRadius = 12.dp,
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (preferItemHeadline) {
                        val itemName = activity.item?.decodedName?.takeIf { it.isNotEmpty() }
                        if (itemName != null) {
                            Text(
                                text = itemName,
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                        if (imageFile.decodedFilename.isNotEmpty()) {
                            Text(
                                text = imageFile.decodedFilename,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        if (activity.decodedNote.isNotBlank()) {
                            Text(
                                text = activity.decodedNote,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        if (activity.decodedNote.isNotBlank()) {
                            Text(
                                text = activity.decodedNote,
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium,
                                color = MaterialTheme.colorScheme.onSurface,
                            )
                        }
                        if (imageFile.decodedFilename.isNotEmpty()) {
                            Text(
                                text = imageFile.decodedFilename,
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium,
                                color = if (activity.decodedNote.isNotBlank()) {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                },
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        } else {
            Text(
                text = headline,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
                color = if (headline == L10n.string("no_details")) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
            )

            if (activity.decodedNote.isNotBlank() &&
                !headline.contains(activity.decodedNote) &&
                !(file?.isImage == true && preferItemHeadline)
            ) {
                Text(
                    text = activity.decodedNote,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        val meta = activity.logMeta.orEmpty()
        if (meta.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                meta.keys.sorted().forEach { key ->
                    val change = meta[key] ?: return@forEach
                    val prettyKey = prettifyFieldLabel(key)
                    val oldValue = change.old?.takeIf { it.isNotBlank() } ?: "–"
                    val newValue = change.new?.takeIf { it.isNotBlank() } ?: "–"
                    if (change.new != null || change.old != null) {
                        Text(
                            text = "$prettyKey: $oldValue → $newValue",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.55f))
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                        )
                    }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (actor != null) {
                MetaIconRow(icon = Icons.Default.Person, text = actor)
            }
            if (isCheckout && targetName != null) {
                val targetIcon = when (activity.target?.type?.lowercase()) {
                    "location" -> Icons.Default.LocationOn
                    else -> Icons.Default.Person
                }
                MetaIconRow(
                    icon = targetIcon,
                    text = "${L10n.string("history_to")}: $targetName",
                )
            }
            if (showItemType) {
                activity.item?.type?.takeIf { it.isNotBlank() }?.let { type ->
                    MetaIconRow(
                        icon = Icons.Default.Inventory2,
                        text = type.replaceFirstChar { it.uppercase() },
                    )
                }
            }
            if (file != null && (file.url != null || file.decodedFilename.isNotEmpty())) {
                val label = when {
                    file.isImage -> L10n.string("view_photo")
                    file.isPDF -> L10n.string("view_pdf")
                    else -> L10n.string("view_file")
                }
                val icon = when {
                    file.isImage -> Icons.Default.Image
                    file.isPDF -> Icons.Default.PictureAsPdf
                    else -> Icons.Default.Description
                }
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .clickable(enabled = onFileClick != null) {
                            onFileClick?.invoke(activity)
                        }
                        .padding(vertical = 2.dp),
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = SnipeAccent,
                    )
                    Text(
                        text = label,
                        style = MaterialTheme.typography.labelSmall,
                        color = SnipeAccent,
                    )
                }
            }
        }
    }
}

@Composable
private fun MetaIconRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
) {
    Row(
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier
                .padding(top = 1.dp)
                .size(14.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

fun activityHeadline(activity: Activity, preferItemHeadline: Boolean = false): String {
    val itemName = activity.item?.decodedName?.takeIf { it.isNotEmpty() }
    val targetName = activity.target?.decodedName?.takeIf { it.isNotEmpty() }
    val file = activity.file
    return when {
        preferItemHeadline && itemName != null && targetName != null -> "$itemName → $targetName"
        preferItemHeadline && itemName != null -> itemName
        file?.isImage == true && activity.decodedNote.isNotBlank() -> activity.decodedNote
        activity.decodedNote.isNotBlank() && !preferItemHeadline -> activity.decodedNote
        itemName != null && targetName != null -> "$itemName → $targetName"
        itemName != null -> itemName
        file?.decodedFilename?.isNotEmpty() == true -> file.decodedFilename
        activity.decodedNote.isNotBlank() -> activity.decodedNote
        targetName != null -> targetName
        else -> L10n.string("no_details")
    }
}

fun activityActionLabel(type: String): String {
    val lower = type.lowercase()
    if (L10n.isDutch) {
        return when {
            lower.contains("check") && (lower.contains("out") || lower.contains("uit")) -> "Uitgecheckt"
            lower.contains("check") && lower.contains("in") -> "Ingecheckt"
            lower.contains("upload") && lower.contains("delete") -> "Upload verwijderd"
            lower.contains("upload") -> "Geüpload"
            lower.contains("update") -> "Bijgewerkt"
            lower.contains("create") -> "Aangemaakt"
            lower.contains("delete") -> "Verwijderd"
            lower.contains("audit") -> "Audit"
            else -> type.replace('_', ' ').replaceFirstChar { it.uppercase() }
        }
    }
    return when {
        lower.contains("check") && (lower.contains("out") || lower.contains("uit")) -> L10n.string("check_out")
        lower.contains("check") && lower.contains("in") -> L10n.string("check_in")
        lower.contains("upload") && lower.contains("delete") -> L10n.string("activity_upload_deleted")
        lower.contains("upload") -> L10n.string("upload")
        lower.contains("update") -> L10n.string("updated_date")
        lower.contains("create") -> L10n.string("created_date")
        lower.contains("delete") -> L10n.string("delete")
        else -> type.replace('_', ' ').replaceFirstChar { it.uppercase() }
    }
}

fun activityActionColor(type: String): Color {
    val lower = type.lowercase()
    return when {
        lower.contains("check") && (lower.contains("out") || lower.contains("uit")) -> SnipeGreen
        lower.contains("check") && lower.contains("in") -> SnipeAccent
        lower.contains("upload") -> Color(0xFF30B0C7)
        lower.contains("update") -> SnipeOrange
        lower.contains("create") -> Color(0xFFAF52DE)
        lower.contains("delete") -> SnipeRed
        else -> Color(0xFF5856D6)
    }
}

private fun isCheckoutAction(type: String): Boolean {
    val lower = type.lowercase()
    return lower.contains("check") && (lower.contains("out") || lower.contains("uit"))
}

private fun prettifyFieldLabel(field: String): String {
    val l10nKeys = mapOf(
        "purchase_cost" to "purchase_cost",
        "book_value" to "book_value",
        "order_number" to "order_number",
        "asset_tag" to "asset_tag",
        "serial" to "serial_number",
        "model" to "model",
        "manufacturer" to "manufacturer",
        "category" to "category",
        "assigned_to" to "assigned_to",
        "location" to "location",
        "status_label" to "status",
        "name" to "name",
        "email" to "email",
        "employee_number" to "employee_number",
        "jobtitle" to "job_title",
    )
    l10nKeys[field]?.let { key ->
        val label = L10n.string(key)
        if (label != key) return label
    }
    var cleaned = field.trim()
    cleaned = cleaned.replace(Regex("""^[\s_]*snipeit[\s_]*""", RegexOption.IGNORE_CASE), "")
    cleaned = cleaned.replace(Regex("""_[0-9]+$"""), "")
    return cleaned.replace('_', ' ').replaceFirstChar { it.uppercase() }
}
