package com.callandt.snipemobile.ui.management

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
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
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.asset.FormSectionTitle
import com.callandt.snipemobile.ui.components.CreatableSearchablePickerField
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.components.SettingsGroupedCard
import com.callandt.snipemobile.ui.components.SettingsRow
import com.callandt.snipemobile.ui.components.SettingsSectionFooter
import com.callandt.snipemobile.ui.components.StringPickerField
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

data class ManagementItem(
    val id: Int,
    val raw: JsonObject,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManagementHubScreen(
    onBack: () -> Unit,
    onOpenEntity: (ManagementEntity) -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("settings_management")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                SettingsSectionFooter(L10n.string("settings_management_footer"))
            }
            item {
                SettingsGroupedCard {
                    ManagementEntity.entries.forEach { entity ->
                        SettingsRow(
                            icon = entity.icon,
                            iconColor = entity.iconColor,
                            title = L10n.string(entity.titleKey),
                            onClick = { onOpenEntity(entity) },
                        )
                    }
                }
            }
            item {
                SettingsSectionFooter(L10n.string("mgmt_sync_footer"))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ManagementListScreen(
    entity: ManagementEntity,
    viewModel: AppViewModel,
    onBack: () -> Unit,
) {
    val config = remember(entity) { entity.config() }
    var items by remember { mutableStateOf<List<ManagementItem>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var searchQuery by remember { mutableStateOf("") }
    var showAdd by remember { mutableStateOf(false) }
    var editItem by remember { mutableStateOf<ManagementItem?>(null) }
    var openFieldset by remember { mutableStateOf<ManagementItem?>(null) }
    var pendingDelete by remember { mutableStateOf<ManagementItem?>(null) }
    var isDeleting by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var deleteError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    suspend fun load() {
        isLoading = true
        loadError = null
        val (rows, error) = viewModel.apiClient.managementFetchRows(config.path)
        isLoading = false
        if (rows != null) {
            items = rows.mapNotNull { row ->
                row["id"]?.jsonPrimitive?.intOrNull?.let { ManagementItem(it, row) }
            }.sortedBy { config.titleReader(it.raw).lowercase() }
        } else {
            loadError = error
        }
    }

    LaunchedEffect(entity) { load() }

    LaunchedEffect(notice) {
        notice?.let {
            snackbarHostState.showSnackbar(it)
            notice = null
        }
    }

    val filtered = remember(items, searchQuery) {
        val q = searchQuery.trim().lowercase()
        if (q.isEmpty()) items
        else items.filter { config.titleReader(it.raw).lowercase().contains(q) }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            SearchTopBar(
                title = L10n.string(entity.titleKey),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                onBack = onBack,
                actions = {
                    IconButton(onClick = { showAdd = true }) {
                        Icon(Icons.Default.Add, contentDescription = L10n.string("add"))
                    }
                },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { scope.launch { load() } },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            when {
                isLoading && items.isEmpty() -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                loadError != null && items.isEmpty() -> {
                    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(loadError ?: L10n.string("mgmt_load_failed"))
                            TextButton(onClick = { scope.launch { load() } }) { Text(L10n.string("retry")) }
                        }
                    }
                }
                items.isEmpty() -> {
                    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(L10n.string("mgmt_empty"), style = MaterialTheme.typography.titleMedium)
                            TextButton(onClick = { showAdd = true }) { Text(L10n.string("create")) }
                        }
                    }
                }
                else -> {
                    LazyColumn(
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        items(filtered, key = { it.id }) { item ->
                            ManagementListRow(
                                entity = entity,
                                config = config,
                                item = item,
                                onClick = {
                                    if (entity == ManagementEntity.Fieldsets) {
                                        openFieldset = item
                                    } else {
                                        editItem = item
                                    }
                                },
                                onDelete = { pendingDelete = item },
                            )
                        }
                        item {
                            Text(
                                text = L10n.string("mgmt_item_count", items.size),
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAdd) {
        ManagementFormSheet(
            entity = entity,
            viewModel = viewModel,
            existing = null,
            onDismiss = { showAdd = false },
            onSaved = { scope.launch { load(); viewModel.syncInBackground() } },
        )
    }

    editItem?.let { item ->
        ManagementFormSheet(
            entity = entity,
            viewModel = viewModel,
            existing = item,
            onDismiss = { editItem = null },
            onSaved = { scope.launch { load(); viewModel.syncInBackground() } },
        )
    }

    openFieldset?.let { item ->
        FieldsetDetailScreen(
            fieldsetId = item.id,
            fieldsetName = config.titleReader(item.raw),
            viewModel = viewModel,
            onDismiss = { openFieldset = null; scope.launch { load() } },
        )
    }

    pendingDelete?.let { item ->
        AlertDialog(
            onDismissRequest = { if (!isDeleting) pendingDelete = null },
            title = { Text(L10n.string("mgmt_delete_title", config.titleReader(item.raw))) },
            text = { Text(L10n.string("mgmt_delete_message", config.titleReader(item.raw))) },
            confirmButton = {
                TextButton(
                    onClick = {
                        isDeleting = true
                        scope.launch {
                            val result = viewModel.apiClient.managementDelete(config.path, item.id)
                            isDeleting = false
                            pendingDelete = null
                            if (result.success) {
                                items = items.filterNot { it.id == item.id }
                                notice = L10n.string("mgmt_deleted")
                                viewModel.syncInBackground()
                            } else {
                                deleteError = result.message ?: L10n.string("delete_failed")
                            }
                        }
                    },
                    enabled = !isDeleting,
                ) { Text(L10n.string("delete")) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }, enabled = !isDeleting) {
                    Text(L10n.string("cancel"))
                }
            },
        )
    }

    deleteError?.let { message ->
        AlertDialog(
            onDismissRequest = { deleteError = null },
            title = { Text(L10n.string("mgmt_delete_failed_title")) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { deleteError = null }) { Text(L10n.string("ok")) } },
        )
    }
}

@Composable
private fun ManagementListRow(
    entity: ManagementEntity,
    config: ManagementEntityConfig,
    item: ManagementItem,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(entity.iconColor.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(entity.icon, contentDescription = null, tint = entity.iconColor, modifier = Modifier.size(18.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(config.titleReader(item.raw), fontWeight = FontWeight.Medium)
            config.subtitleReader?.invoke(item.raw)?.let { subtitle ->
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        TextButton(onClick = onDelete) { Text(L10n.string("delete")) }
        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun ManagementFormSheet(
    entity: ManagementEntity,
    viewModel: AppViewModel,
    existing: ManagementItem?,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
    initialDefaults: Map<String, String> = emptyMap(),
    onCreated: (id: Int?, name: String?) -> Unit = { _, _ -> },
) {
    val config = remember(entity) { entity.config() }
    val isEdit = existing != null
    val categories by viewModel.categories.collectAsState()
    val manufacturers by viewModel.manufacturers.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val users by viewModel.users.collectAsState()
    val fieldsets by viewModel.apiClient.fieldsets.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var values by remember(existing?.id) { mutableStateOf<Map<String, String>>(emptyMap()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var loaded by remember(existing?.id) { mutableStateOf(false) }

    val visibleFields = remember(config, isEdit) {
        config.fields.filter { !(it.createOnly && isEdit) }
    }

    LaunchedEffect(existing?.id, initialDefaults) {
        loaded = false
        var row = existing?.raw
        if (existing != null) {
            viewModel.apiClient.managementFetchRow(config.path, existing.id)?.let { row = it }
        }
        val initial = mutableMapOf<String, String>()
        config.fields.forEach { field ->
            initial[field.bodyKey] = when {
                row != null -> field.currentValue(row)
                initialDefaults[field.bodyKey]?.isNotBlank() == true -> initialDefaults.getValue(field.bodyKey)
                field.defaultValue != null -> field.defaultValue
                field.kind == ManagementFieldKind.Toggle -> "0"
                else -> ""
            }
        }
        values = initial
        loaded = true
        if (categories.isEmpty()) viewModel.apiClient.fetchCategories()
        if (manufacturers.isEmpty()) viewModel.apiClient.fetchManufacturers()
        if (companies.isEmpty()) viewModel.apiClient.fetchCompanies()
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
        if (users.isEmpty()) viewModel.apiClient.fetchUsers()
        if (fieldsets == null) viewModel.apiClient.fetchFieldsets()
    }

    fun canSave(): Boolean = visibleFields.all { field ->
        if (!field.required) return@all true
        val value = values[field.bodyKey]?.trim().orEmpty()
        value.isNotEmpty()
    }

    fun buildBody(): Map<String, Any?> {
        val body = mutableMapOf<String, Any?>()
        visibleFields.forEach { field ->
            val raw = values[field.bodyKey]?.trim().orEmpty()
            when (field.kind) {
                ManagementFieldKind.Toggle -> body[field.bodyKey] = raw == "1"
                ManagementFieldKind.Number -> {
                    raw.toIntOrNull()?.let { body[field.bodyKey] = it }
                        ?: run {
                            if (isEdit && raw.isEmpty()) body[field.bodyKey] = null
                        }
                }
                ManagementFieldKind.ColorHex -> {
                    val normalized = raw.replace("#", "")
                    body[field.bodyKey] = if (normalized.isEmpty()) {
                        if (isEdit) "" else null
                    } else {
                        "#$normalized"
                    }
                }
                ManagementFieldKind.Picker -> {
                    if (raw.isNotEmpty()) {
                        body[field.bodyKey] = raw.toIntOrNull() ?: raw
                    } else if (isEdit) {
                        body[field.bodyKey] = null
                    }
                }
                else -> {
                    if (raw.isNotEmpty()) body[field.bodyKey] = raw
                    else if (isEdit) body[field.bodyKey] = ""
                }
            }
        }
        return body
    }

    if (!loaded) return

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = if (isEdit) {
                L10n.string("mgmt_edit_title", L10n.string(config.singularKey))
            } else {
                L10n.string("mgmt_new_title", L10n.string(config.singularKey))
            },
            saveLabel = if (isEdit) L10n.string("save") else L10n.string("create"),
            isSaving = isSaving,
            canSave = canSave() && !isSaving,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    val result = if (isEdit) {
                        viewModel.apiClient.managementUpdate(config.path, existing!!.id, buildBody())
                    } else {
                        viewModel.apiClient.managementCreate(config.path, buildBody())
                    }
                    isSaving = false
                    if (result.success) {
                        refreshBackingList(entity, viewModel)
                        if (!isEdit) {
                            onCreated(
                                result.id,
                                values["name"]?.trim()?.takeIf { it.isNotEmpty() },
                            )
                        }
                        onSaved()
                        onDismiss()
                    } else {
                        errorMessage = result.message ?: lastApiMessage ?: L10n.string("mgmt_save_failed")
                    }
                }
            },
        ) {
            visibleFields.forEach { field ->
                val value = values[field.bodyKey].orEmpty()
                when (field.kind) {
                    ManagementFieldKind.Text, ManagementFieldKind.Url, ManagementFieldKind.Email, ManagementFieldKind.Phone -> {
                        OutlinedTextField(
                            value = value,
                            onValueChange = { values = values + (field.bodyKey to it) },
                            label = { Text(field.displayLabel()) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    ManagementFieldKind.Number -> {
                        OutlinedTextField(
                            value = value,
                            onValueChange = { values = values + (field.bodyKey to it) },
                            label = { Text(field.displayLabel()) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    ManagementFieldKind.Multiline -> {
                        FormSectionTitle(field.displayLabel())
                        OutlinedTextField(
                            value = value,
                            onValueChange = { values = values + (field.bodyKey to it) },
                            label = { Text(field.displayLabel()) },
                            modifier = Modifier.fillMaxWidth(),
                            minLines = 3,
                        )
                    }
                    ManagementFieldKind.Toggle -> {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(field.displayLabel(), modifier = Modifier.weight(1f))
                            Switch(
                                checked = value == "1",
                                onCheckedChange = { values = values + (field.bodyKey to if (it) "1" else "0") },
                            )
                        }
                    }
                    ManagementFieldKind.ColorHex -> {
                        OutlinedTextField(
                            value = value,
                            onValueChange = { values = values + (field.bodyKey to it.uppercase()) },
                            label = { Text(field.displayLabel()) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    ManagementFieldKind.Picker -> {
                        val options = pickerOptionsForField(
                            field = field,
                            categories = categories,
                            manufacturers = manufacturers,
                            companies = companies,
                            locations = locations,
                            users = users,
                            fieldsets = fieldsets.orEmpty(),
                            existing = existing,
                        )
                        if (options.intItems.isNotEmpty() || field.pickerSource?.creatableEntity() != null || field.pickerSource?.creatableLocation() == true) {
                            val source = field.pickerSource
                            val creatable = source?.creatableEntity()
                            val locationCreate = source?.creatableLocation() == true
                            if (creatable != null || locationCreate) {
                                CreatableSearchablePickerField(
                                    label = field.displayLabel(),
                                    items = options.intItems,
                                    selectedId = value.toIntOrNull()?.takeIf { it > 0 },
                                    viewModel = viewModel,
                                    creatableEntity = creatable,
                                    creatableLocation = locationCreate,
                                    createDefaults = source?.createDefaults().orEmpty(),
                                    onSelected = { values = values + (field.bodyKey to it.id.toString()) },
                                )
                            } else {
                                SearchablePickerField(
                                    label = field.displayLabel(),
                                    items = options.intItems,
                                    selectedId = value.toIntOrNull()?.takeIf { it > 0 },
                                    onSelected = { values = values + (field.bodyKey to it.id.toString()) },
                                )
                            }
                        } else {
                            StringPickerField(
                                label = field.displayLabel(),
                                options = options.stringOptions,
                                selectedValue = value,
                                onSelected = { values = values + (field.bodyKey to it) },
                            )
                        }
                    }
                }
            }
        }
    }

    errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(L10n.string("error")) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { errorMessage = null }) { Text(L10n.string("ok")) } },
        )
    }
}

private data class PickerOptionsResult(
    val intItems: List<PickerItem>,
    val stringOptions: List<Pair<String, String>>,
)

private fun pickerOptionsForField(
    field: ManagementFormField,
    categories: List<com.callandt.snipemobile.data.model.CategoryRow>,
    manufacturers: List<com.callandt.snipemobile.data.model.Manufacturer>,
    companies: List<com.callandt.snipemobile.data.model.Company>,
    locations: List<com.callandt.snipemobile.data.model.Location>,
    users: List<com.callandt.snipemobile.data.model.User>,
    fieldsets: List<com.callandt.snipemobile.data.model.Fieldset>,
    existing: ManagementItem?,
): PickerOptionsResult {
    val nestedKey = field.bodyKey.removeSuffix("_id").takeIf { field.bodyKey.endsWith("_id") }
    val fallbackLabel = nestedKey?.let { key -> existing?.raw?.let { ManagementValue.nestedName(it, key) } }

    return when (field.pickerSource) {
        ManagementPickerSource.CategoriesAsset -> PickerOptionsResult(
            categories.filter { it.categoryType?.lowercase() == "asset" }
                .map { PickerItem(it.id, it.decodedName) },
            emptyList(),
        )
        ManagementPickerSource.Manufacturers -> PickerOptionsResult(
            manufacturers.map { PickerItem(it.id, it.decodedName) },
            emptyList(),
        )
        ManagementPickerSource.Companies -> PickerOptionsResult(
            companies.map { PickerItem(it.id, it.decodedName) },
            emptyList(),
        )
        ManagementPickerSource.Locations -> PickerOptionsResult(
            locations.map { PickerItem(it.id, it.decodedName) },
            emptyList(),
        )
        ManagementPickerSource.Users -> PickerOptionsResult(
            users.map { PickerItem(it.id, it.decodedName) },
            emptyList(),
        )
        ManagementPickerSource.Fieldsets -> PickerOptionsResult(
            fieldsets.map {
                PickerItem(
                    it.id,
                    com.callandt.snipemobile.util.HtmlDecoder.decode(it.name),
                )
            },
            emptyList(),
        )
        ManagementPickerSource.StatusType -> PickerOptionsResult(emptyList(), statusTypeOptions())
        ManagementPickerSource.CategoryType -> PickerOptionsResult(emptyList(), categoryTypeOptions())
        null -> {
            if (field.pickerOptions.isNotEmpty()) {
                PickerOptionsResult(emptyList(), field.pickerOptions)
            } else {
                val current = existing?.let { field.currentValue(it.raw) }.orEmpty()
                val options = if (current.isNotEmpty() && fallbackLabel != null) {
                    listOf(current to fallbackLabel)
                } else {
                    emptyList()
                }
                PickerOptionsResult(emptyList(), options)
            }
        }
    }
}

private suspend fun refreshBackingList(entity: ManagementEntity, viewModel: AppViewModel) {
    when (entity) {
        ManagementEntity.Companies -> viewModel.apiClient.fetchCompanies()
        ManagementEntity.Manufacturers -> viewModel.apiClient.fetchManufacturers()
        ManagementEntity.Suppliers -> viewModel.apiClient.fetchSuppliers()
        ManagementEntity.Categories -> viewModel.apiClient.fetchCategories()
        ManagementEntity.Models -> viewModel.apiClient.fetchModels()
        ManagementEntity.StatusLabels -> viewModel.apiClient.fetchStatusLabels()
        ManagementEntity.Fieldsets -> viewModel.apiClient.fetchFieldsets()
        else -> Unit
    }
}
