package com.callandt.snipemobile.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.data.model.DateInfo
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.MaintenanceLinkedAssetInfo
import com.callandt.snipemobile.ui.maintenance.EditMaintenanceSheet
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeGreen
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.theme.SnipeRed
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.resolveSnipeImageUrl
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MaintenanceDetailScreen(maintenanceId: Int, viewModel: AppViewModel, onBack: () -> Unit) {
    val items by viewModel.maintenances.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current

    var currentRecord by remember(maintenanceId) {
        mutableStateOf(items.firstOrNull { it.id == maintenanceId })
    }
    var imageRefreshToken by remember(maintenanceId) { mutableIntStateOf(0) }
    var showEdit by remember { mutableStateOf(false) }
    var showComplete by remember { mutableStateOf(false) }
    var showDelete by remember { mutableStateOf(false) }
    var completeNote by remember { mutableStateOf("") }
    var isBusy by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(maintenanceId) {
        viewModel.apiClient.fetchMaintenance(maintenanceId)?.let {
            currentRecord = it
            imageRefreshToken += 1
        }
    }

    LaunchedEffect(items, maintenanceId) {
        if (currentRecord == null) {
            currentRecord = items.firstOrNull { it.id == maintenanceId }
        }
    }

    val record = currentRecord
    val linkedAsset = remember(record?.assetId, assets) {
        val id = record?.assetId
        if (id != null && id > 0) assets.firstOrNull { it.id == id } else null
    }
    val assetInfo = remember(record, linkedAsset) {
        record?.let { MaintenanceLinkedAssetInfo.resolve(it, linkedAsset) }
    }
    val imageUrl = remember(record?.image, record?.updatedAt, imageRefreshToken, viewModel.apiClient.baseUrl) {
        val item = record ?: return@remember null
        val cacheBuster = item.updatedAt?.datetime
            ?: item.updatedAt?.date
            ?: imageRefreshToken.toString()
        resolveSnipeImageUrl(viewModel.apiClient.baseUrl, item.image, cacheBuster)
    }

    fun refreshAfterMutation(id: Int) {
        scope.launch {
            viewModel.apiClient.fetchMaintenance(id)?.let {
                currentRecord = it
                imageRefreshToken += 1
            }
            viewModel.syncInBackground()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = record?.decodedTitle ?: L10n.string("maintenance"),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("close"))
                    }
                },
                actions = {
                    if (record != null) {
                        IconButton(onClick = { showEdit = true }, enabled = !isBusy) {
                            Icon(Icons.Default.Edit, contentDescription = L10n.string("edit"))
                        }
                        IconButton(onClick = { showDelete = true }, enabled = !isBusy) {
                            Icon(
                                Icons.Default.Delete,
                                contentDescription = L10n.string("delete"),
                                tint = SnipeRed,
                            )
                        }
                    }
                },
            )
        },
        bottomBar = {
            if (record != null && !record.isCompleted) {
                Surface(tonalElevation = 2.dp) {
                    Button(
                        onClick = {
                            completeNote = ""
                            showComplete = true
                        },
                        enabled = !isBusy,
                        colors = ButtonDefaults.buttonColors(containerColor = SnipeGreen),
                        modifier = Modifier
                            .fillMaxWidth()
                            .navigationBarsPadding()
                            .padding(horizontal = 20.dp, vertical = 14.dp),
                    ) {
                        Icon(
                            Icons.Default.CheckCircle,
                            contentDescription = null,
                            modifier = Modifier.padding(end = 8.dp),
                        )
                        Text(L10n.string("mark_complete"), fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        },
    ) { padding ->
        MaintenanceDetailBody(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            record = record,
            assetInfo = assetInfo,
            imageUrl = imageUrl,
            isBusy = isBusy,
            onOpenUrl = { url -> runCatching { uriHandler.openUri(url) } },
        )
    }

    if (showEdit && record != null) {
        EditMaintenanceSheet(
            record = record,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
            onSaved = {
                showEdit = false
                refreshAfterMutation(record.id)
            },
        )
    }

    if (showComplete && record != null) {
        AlertDialog(
            onDismissRequest = { if (!isBusy) showComplete = false },
            title = { Text(L10n.string("mark_complete_confirm_title")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(L10n.string("mark_complete_confirm_message"))
                    OutlinedTextField(
                        value = completeNote,
                        onValueChange = { completeNote = it },
                        label = { Text(L10n.string("note_optional")) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        isBusy = true
                        scope.launch {
                            val ok = viewModel.apiClient.completeMaintenance(
                                id = record.id,
                                note = completeNote.trim().takeIf { it.isNotEmpty() },
                            )
                            isBusy = false
                            if (ok) {
                                showComplete = false
                                completeNote = ""
                                refreshAfterMutation(record.id)
                            } else {
                                errorMessage = lastApiMessage ?: L10n.string("error")
                            }
                        }
                    },
                    enabled = !isBusy,
                ) { Text(L10n.string("mark_complete")) }
            },
            dismissButton = {
                TextButton(onClick = { showComplete = false }, enabled = !isBusy) {
                    Text(L10n.string("cancel"))
                }
            },
        )
    }

    if (showDelete && record != null) {
        AlertDialog(
            onDismissRequest = { if (!isBusy) showDelete = false },
            title = { Text(L10n.string("delete_maintenance_confirm_title")) },
            text = { Text(L10n.string("delete_maintenance_confirm_message", record.decodedTitle)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        isBusy = true
                        scope.launch {
                            val ok = viewModel.apiClient.deleteMaintenance(record.id)
                            isBusy = false
                            if (ok) {
                                showDelete = false
                                viewModel.syncInBackground()
                                onBack()
                            } else {
                                errorMessage = lastApiMessage ?: L10n.string("delete_failed")
                            }
                        }
                    },
                    enabled = !isBusy,
                ) { Text(L10n.string("delete")) }
            },
            dismissButton = {
                TextButton(onClick = { showDelete = false }, enabled = !isBusy) {
                    Text(L10n.string("cancel"))
                }
            },
        )
    }

    errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(L10n.string("error")) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text(L10n.string("ok")) }
            },
        )
    }
}

@Composable
private fun MaintenanceDetailBody(
    modifier: Modifier,
    record: AssetMaintenance?,
    assetInfo: MaintenanceLinkedAssetInfo?,
    imageUrl: String?,
    isBusy: Boolean,
    onOpenUrl: (String) -> Unit,
) {
    Box(modifier = modifier) {
        if (record == null) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("no_maintenance"))
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(top = 16.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(15.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                StatusHeader(completed = record.isCompleted)

                assetInfo?.let { AssetHeaderCard(info = it) }

                if (imageUrl != null) {
                    DetailCard {
                        Text(
                            text = L10n.string("image"),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(bottom = 8.dp),
                        )
                        AsyncImage(
                            model = imageUrl,
                            contentDescription = L10n.string("image"),
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(min = 140.dp, max = 220.dp)
                                .clip(RoundedCornerShape(8.dp)),
                            contentScale = ContentScale.Fit,
                        )
                    }
                }

                DetailCard {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        record.displayType?.let {
                            StackedDetailRow(L10n.string("maintenance_type"), it)
                        }
                        record.supplier?.decodedName?.takeIf { it.isNotEmpty() }?.let {
                            StackedDetailRow(L10n.string("supplier_optional"), it)
                        }
                        dateDisplay(record.startDate)?.let {
                            StackedDetailRow(L10n.string("start_date"), it)
                        }
                        StackedDetailRow(
                            L10n.string("completion_date"),
                            dateDisplay(record.completionDate) ?: L10n.string("in_progress"),
                        )
                        record.maintenanceTime?.takeIf { it > 0 }?.let { days ->
                            StackedDetailRow(
                                L10n.string("maintenance_duration"),
                                L10n.string("maintenance_duration_days", days),
                            )
                        }
                        record.cost?.takeIf { it.isNotBlank() }?.let {
                            StackedDetailRow(L10n.string("cost"), it)
                        }
                        StackedDetailRow(
                            L10n.string("is_warranty"),
                            if (record.isWarranty) L10n.string("yes") else L10n.string("no"),
                        )
                        record.url?.takeIf { it.isNotBlank() }?.let { url ->
                            StackedLinkRow(
                                label = L10n.string("url"),
                                url = url,
                                onOpen = { onOpenUrl(url) },
                            )
                        }
                        record.responsibleParty?.decodedName?.takeIf { it.isNotEmpty() }?.let {
                            StackedDetailRow(L10n.string("responsible_party"), it)
                        }
                        record.createdBy?.decodedName?.takeIf { it.isNotEmpty() }?.let {
                            StackedDetailRow(L10n.string("created_by"), it)
                        }
                        record.completedBy?.decodedName?.takeIf { it.isNotEmpty() }?.let {
                            StackedDetailRow(L10n.string("completed_by"), it)
                        }
                        dateDisplay(record.completedAt)?.let {
                            StackedDetailRow(L10n.string("completed_date"), it)
                        }
                        dateDisplay(record.createdAt)?.let {
                            StackedDetailRow(L10n.string("created_date"), it)
                        }
                        dateDisplay(record.updatedAt)?.let {
                            StackedDetailRow(L10n.string("updated_date"), it)
                        }
                    }
                }

                if (record.decodedNotes.isNotEmpty()) {
                    DetailCard {
                        Text(
                            text = L10n.string("notes"),
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(bottom = 8.dp),
                        )
                        Text(
                            text = record.decodedNotes,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        if (isBusy) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    tonalElevation = 4.dp,
                ) {
                    CircularProgressIndicator(modifier = Modifier.padding(20.dp))
                }
            }
        }
    }
}

@Composable
private fun StatusHeader(completed: Boolean) {
    val color = if (completed) SnipeGreen else SnipeOrange
    val icon = if (completed) Icons.Default.CheckCircle else Icons.Default.Schedule
    val text = if (completed) L10n.string("status_completed") else L10n.string("in_progress")
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 14.dp, vertical = 7.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(16.dp))
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
    }
}

@Composable
private fun AssetHeaderCard(info: MaintenanceLinkedAssetInfo) {
    DetailCard {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(
                imageVector = Icons.Default.Laptop,
                contentDescription = null,
                tint = SnipeAccent,
                modifier = Modifier
                    .size(36.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(SnipeAccent.copy(alpha = 0.1f))
                    .padding(8.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = L10n.string("asset"),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = info.title,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                info.detailLine?.let { detail ->
                    Text(
                        text = detail,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        info.assignee?.let { assignee ->
            Spacer(modifier = Modifier.size(8.dp))
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.Person,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    text = L10n.string("checked_out_to"),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = assignee,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun DetailCard(content: @Composable () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            content()
        }
    }
}

@Composable
private fun StackedDetailRow(label: String, value: String) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun StackedLinkRow(label: String, url: String, onOpen: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )
        TextButton(
            onClick = onOpen,
            contentPadding = PaddingValues(0.dp),
        ) {
            Text(
                text = url,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = SnipeAccent,
            )
        }
    }
}

private fun dateDisplay(info: DateInfo?): String? {
    if (info == null) return null
    return info.formatted?.takeIf { it.isNotBlank() }
        ?: info.localizedDisplay()?.takeIf { it.isNotBlank() }
}
