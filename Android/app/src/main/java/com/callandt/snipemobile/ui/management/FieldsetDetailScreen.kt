package com.callandt.snipemobile.ui.management

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Fieldset editor: rename, link/unlink fields, reorder. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FieldsetDetailScreen(
    fieldsetId: Int,
    fieldsetName: String,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
) {
    var name by remember(fieldsetId) { mutableStateOf(fieldsetName) }
    var isSavingName by remember { mutableStateOf(false) }
    var linked by remember(fieldsetId) { mutableStateOf<List<ManagementItem>>(emptyList()) }
    var isLoading by remember(fieldsetId) { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var showAddSheet by remember { mutableStateOf(false) }
    var pendingRemove by remember { mutableStateOf<ManagementItem?>(null) }
    var busyFieldId by remember { mutableStateOf<Int?>(null) }
    var isSavingOrder by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var draggedIndex by remember { mutableIntStateOf(-1) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    var orderBeforeDrag by remember { mutableStateOf<List<ManagementItem>>(emptyList()) }
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val density = LocalDensity.current
    val rowStepPx = with(density) { 62.dp.toPx() }

    val canSaveName = name.trim().isNotEmpty() && name.trim() != fieldsetName

    suspend fun load() {
        isLoading = true
        loadError = null
        val (rows, error) = viewModel.apiClient.fetchFieldsetLinkedFields(fieldsetId)
        isLoading = false
        if (rows != null) {
            linked = rows.mapNotNull { row ->
                row["id"]?.jsonPrimitive?.intOrNull?.let { ManagementItem(it, row) }
            }
        } else {
            loadError = error
        }
    }

    LaunchedEffect(fieldsetId) { load() }

    LaunchedEffect(notice) {
        notice?.let {
            snackbarHostState.showSnackbar(it)
            notice = null
        }
    }

    fun fieldName(row: JsonObject) = ManagementValue.displayString(row["name"])
    fun fieldElement(row: JsonObject): String? {
        val element = ManagementValue.scalarString(row["type"] ?: row["element"])
            .replaceFirstChar { it.uppercase() }
        return element.takeIf { it.isNotEmpty() }
    }

    suspend fun saveName() {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        isSavingName = true
        val result = viewModel.apiClient.managementUpdate("/api/v1/fieldsets", fieldsetId, mapOf("name" to trimmed))
        isSavingName = false
        notice = if (result.success) L10n.string("saved") else result.message ?: L10n.string("mgmt_save_failed")
        if (result.success) viewModel.apiClient.fetchFieldsets()
    }

    suspend fun disassociate(item: ManagementItem) {
        pendingRemove = null
        busyFieldId = item.id
        val result = viewModel.apiClient.managementCreate(
            "/api/v1/fields/${item.id}/disassociate",
            mapOf("fieldset_id" to fieldsetId),
        )
        busyFieldId = null
        if (result.success) {
            linked = linked.filterNot { it.id == item.id }
            notice = L10n.string("fieldset_field_unlinked")
        } else {
            notice = result.message ?: L10n.string("mgmt_save_failed")
        }
    }

    suspend fun persistOrder(previous: List<ManagementItem>) {
        isSavingOrder = true
        val result = viewModel.apiClient.reorderFieldsetFields(fieldsetId, linked.map { it.id })
        isSavingOrder = false
        if (result.success) {
            viewModel.apiClient.fetchFieldsets()
        } else {
            linked = previous
            notice = result.message ?: L10n.string("fieldset_reorder_failed")
        }
    }

    fun moveField(fromIndex: Int, toIndex: Int) {
        if (fromIndex == toIndex || fromIndex !in linked.indices || toIndex !in linked.indices) return
        val reordered = linked.toMutableList()
        val item = reordered.removeAt(fromIndex)
        reordered.add(toIndex, item)
        linked = reordered
    }

    fun finishDrag() {
        val previous = orderBeforeDrag
        val didChange = previous.isNotEmpty() && previous.map { it.id } != linked.map { it.id }
        draggedIndex = -1
        dragOffsetY = 0f
        orderBeforeDrag = emptyList()
        if (didChange) scope.launch { persistOrder(previous) }
    }

    AssetFullScreenSheet(onDismiss = onDismiss) {
        Scaffold(
            snackbarHost = { SnackbarHost(snackbarHostState) },
            topBar = {
                TopAppBar(
                    title = { Text(name.ifEmpty { fieldsetName }, maxLines = 1) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("close"))
                        }
                    },
                    actions = {
                        IconButton(onClick = { showAddSheet = true }) {
                            Icon(Icons.Default.Add, contentDescription = L10n.string("fieldset_add_field"))
                        }
                    },
                )
            },
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = { Text(L10n.string("name")) },
                        modifier = Modifier.weight(1f),
                        singleLine = true,
                    )
                    if (isSavingName) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    } else if (canSaveName) {
                        TextButton(onClick = { scope.launch { saveName() } }) { Text(L10n.string("save")) }
                    }
                }

                Text(
                    text = L10n.string("fieldset_linked_fields"),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )

                Box(modifier = Modifier.weight(1f)) {
                    when {
                        isLoading && linked.isEmpty() -> {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator()
                            }
                        }
                        loadError != null && linked.isEmpty() -> {
                            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text(loadError ?: L10n.string("mgmt_load_failed"))
                                    TextButton(onClick = { scope.launch { load() } }) { Text(L10n.string("retry")) }
                                }
                            }
                        }
                        linked.isEmpty() -> {
                            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                                Text(
                                    L10n.string("fieldset_no_fields_desc"),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                        else -> {
                            LazyColumn(
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                itemsIndexed(linked, key = { _, item -> item.id }) { index, item ->
                                    val isDragging = draggedIndex == index
                                    FieldsetFieldRow(
                                        title = fieldName(item.raw),
                                        subtitle = fieldElement(item.raw),
                                        isBusy = busyFieldId == item.id,
                                        isDragging = isDragging,
                                        dragEnabled = !isSavingOrder && busyFieldId == null,
                                        dragOffsetY = if (isDragging) dragOffsetY else 0f,
                                        onDragHandle = Modifier.pointerInput(index, linked.size, isSavingOrder) {
                                            if (isSavingOrder) return@pointerInput
                                            detectDragGesturesAfterLongPress(
                                                onDragStart = {
                                                    draggedIndex = index
                                                    dragOffsetY = 0f
                                                    orderBeforeDrag = linked
                                                },
                                                onDrag = { change, dragAmount ->
                                                    change.consume()
                                                    if (draggedIndex < 0) return@detectDragGesturesAfterLongPress
                                                    dragOffsetY += dragAmount.y
                                                    var current = draggedIndex
                                                    while (dragOffsetY > rowStepPx / 2 && current < linked.lastIndex) {
                                                        moveField(current, current + 1)
                                                        dragOffsetY -= rowStepPx
                                                        current++
                                                        draggedIndex = current
                                                    }
                                                    while (dragOffsetY < -rowStepPx / 2 && current > 0) {
                                                        moveField(current, current - 1)
                                                        dragOffsetY += rowStepPx
                                                        current--
                                                        draggedIndex = current
                                                    }
                                                },
                                                onDragEnd = { finishDrag() },
                                                onDragCancel = {
                                                    if (orderBeforeDrag.isNotEmpty()) linked = orderBeforeDrag
                                                    draggedIndex = -1
                                                    dragOffsetY = 0f
                                                    orderBeforeDrag = emptyList()
                                                },
                                            )
                                        },
                                        onUnlink = { pendingRemove = item },
                                    )
                                }
                                item {
                                    Text(
                                        text = L10n.string("mgmt_item_count", linked.size),
                                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (showAddSheet) {
        FieldAssociatePicker(
            fieldsetId = fieldsetId,
            alreadyLinkedIds = linked.map { it.id }.toSet(),
            viewModel = viewModel,
            onDismiss = { showAddSheet = false; scope.launch { load() } },
        )
    }

    pendingRemove?.let { item ->
        AlertDialog(
            onDismissRequest = { pendingRemove = null },
            title = { Text(L10n.string("fieldset_unlink_title", fieldName(item.raw))) },
            text = { Text(L10n.string("fieldset_unlink_message", fieldName(item.raw))) },
            confirmButton = {
                TextButton(onClick = { scope.launch { disassociate(item) } }) {
                    Text(L10n.string("fieldset_unlink"))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingRemove = null }) { Text(L10n.string("cancel")) }
            },
        )
    }
}

@Composable
private fun FieldsetFieldRow(
    title: String,
    subtitle: String?,
    isBusy: Boolean,
    isDragging: Boolean,
    dragEnabled: Boolean,
    dragOffsetY: Float,
    onDragHandle: Modifier,
    onUnlink: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .graphicsLayer {
                translationY = dragOffsetY
                alpha = if (isDragging) 0.88f else 1f
                shadowElevation = if (isDragging) 6f else 0f
            }
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.16f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.AutoMirrored.Filled.ListAlt,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(16.dp),
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Medium)
            subtitle?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (isBusy) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp))
        } else {
            Icon(
                Icons.Default.DragHandle,
                contentDescription = L10n.string("fieldset_reorder_hint"),
                tint = if (dragEnabled) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f)
                },
                modifier = onDragHandle
                    .size(32.dp)
                    .padding(4.dp),
            )
            IconButton(onClick = onUnlink, modifier = Modifier.size(32.dp)) {
                Icon(
                    Icons.Default.RemoveCircle,
                    contentDescription = L10n.string("fieldset_unlink"),
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

/** Pick an unlinked field to attach to this fieldset. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FieldAssociatePicker(
    fieldsetId: Int,
    alreadyLinkedIds: Set<Int>,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
) {
    var allFields by remember { mutableStateOf<List<ManagementItem>>(emptyList()) }
    var addedIds by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var searchQuery by remember { mutableStateOf("") }
    var busyFieldId by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope()

    fun fieldName(row: JsonObject) = ManagementValue.displayString(row["name"])
    fun fieldElement(row: JsonObject): String? {
        val element = ManagementValue.scalarString(row["type"] ?: row["element"])
            .replaceFirstChar { it.uppercase() }
        return element.takeIf { it.isNotEmpty() }
    }

    val available = remember(allFields, addedIds, searchQuery) {
        val query = searchQuery.trim().lowercase()
        allFields.filter { item ->
            if (alreadyLinkedIds.contains(item.id) || addedIds.contains(item.id)) return@filter false
            if (query.isEmpty()) return@filter true
            fieldName(item.raw).lowercase().contains(query)
        }
    }

    suspend fun load() {
        isLoading = true
        loadError = null
        val (rows, error) = viewModel.apiClient.managementFetchRows("/api/v1/fields")
        isLoading = false
        if (rows != null) {
            allFields = rows.mapNotNull { row ->
                row["id"]?.jsonPrimitive?.intOrNull?.let { ManagementItem(it, row) }
            }.sortedBy { fieldName(it.raw).lowercase() }
        } else {
            loadError = error
        }
    }

    LaunchedEffect(Unit) { load() }

    suspend fun associate(item: ManagementItem) {
        busyFieldId = item.id
        val result = viewModel.apiClient.managementCreate(
            "/api/v1/fields/${item.id}/associate",
            mapOf("fieldset_id" to fieldsetId, "order" to alreadyLinkedIds.size + addedIds.size),
        )
        busyFieldId = null
        if (result.success) addedIds = addedIds + item.id
    }

    AssetFullScreenSheet(onDismiss = onDismiss) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(L10n.string("fieldset_add_field")) },
                    actions = {
                        TextButton(onClick = onDismiss) { Text(L10n.string("close")) }
                    },
                )
            },
        ) { padding ->
            Column(modifier = Modifier.fillMaxSize().padding(padding)) {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    label = { Text(L10n.string("search")) },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                    singleLine = true,
                )
                when {
                    isLoading && allFields.isEmpty() -> {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator()
                        }
                    }
                    loadError != null && allFields.isEmpty() -> {
                        Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text(loadError ?: L10n.string("mgmt_load_failed"))
                                TextButton(onClick = { scope.launch { load() } }) { Text(L10n.string("retry")) }
                            }
                        }
                    }
                    available.isEmpty() -> {
                        Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                            Text(L10n.string("fieldset_no_available"), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    else -> {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            items(
                                items = available,
                                key = { it.id },
                            ) { item ->
                                Surface(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clip(RoundedCornerShape(12.dp)),
                                    color = MaterialTheme.colorScheme.surfaceVariant,
                                ) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable(enabled = busyFieldId != item.id) {
                                                scope.launch { associate(item) }
                                            }
                                            .padding(horizontal = 14.dp, vertical = 12.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(fieldName(item.raw), fontWeight = FontWeight.Medium)
                                            fieldElement(item.raw)?.let {
                                                Text(
                                                    it,
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                )
                                            }
                                        }
                                        if (busyFieldId == item.id) {
                                            CircularProgressIndicator(modifier = Modifier.size(20.dp))
                                        } else {
                                            Icon(
                                                Icons.Default.Add,
                                                contentDescription = L10n.string("fieldset_add_field"),
                                                tint = MaterialTheme.colorScheme.primary,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
