package com.callandt.snipemobile.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.location.AddLocationSheet
import com.callandt.snipemobile.ui.management.ManagementEntity
import com.callandt.snipemobile.ui.management.ManagementFormSheet
import com.callandt.snipemobile.ui.management.config
import com.callandt.snipemobile.ui.util.L10n

/** Searchable picker with optional inline create. */
@Composable
fun CreatableSearchablePickerField(
    label: String,
    items: List<PickerItem>,
    selectedId: Int?,
    viewModel: AppViewModel,
    modifier: Modifier = Modifier,
    placeholder: String = L10n.string("select") + "…",
    creatableEntity: ManagementEntity? = null,
    creatableLocation: Boolean = false,
    createDefaults: Map<String, String> = emptyMap(),
    onSelected: (PickerItem) -> Unit,
) {
    var showManagementCreate by remember { mutableStateOf(false) }
    var showLocationCreate by remember { mutableStateOf(false) }
    var pendingCreated by remember { mutableStateOf<PickerItem?>(null) }

    val canCreate = creatableEntity != null || creatableLocation
    val addNewLabel = when {
        creatableEntity != null ->
            L10n.string("mgmt_new_title", L10n.string(creatableEntity.config().singularKey))
        creatableLocation -> L10n.string("new_location")
        else -> null
    }

    val displayItems = remember(items, pendingCreated) {
        val pending = pendingCreated ?: return@remember items
        if (items.any { it.id == pending.id }) items else items + pending
    }

    SearchablePickerField(
        label = label,
        items = displayItems,
        selectedId = selectedId,
        modifier = modifier,
        placeholder = placeholder,
        addNewLabel = addNewLabel,
        onAddNew = if (canCreate) {
            {
                when {
                    creatableEntity != null -> showManagementCreate = true
                    creatableLocation -> showLocationCreate = true
                }
            }
        } else {
            null
        },
        onSelected = { item ->
            pendingCreated = null
            onSelected(item)
        },
    )

    if (showManagementCreate && creatableEntity != null) {
        ManagementFormSheet(
            entity = creatableEntity,
            viewModel = viewModel,
            existing = null,
            initialDefaults = createDefaults,
            onDismiss = { showManagementCreate = false },
            onSaved = {},
            onCreated = { newId, name ->
                if (newId != null && newId > 0) {
                    val title = name?.takeIf { it.isNotBlank() }
                        ?: items.firstOrNull { it.id == newId }?.title
                        ?: "#$newId"
                    val item = PickerItem(newId, title)
                    pendingCreated = item
                    onSelected(item)
                }
            },
        )
    }

    if (showLocationCreate) {
        AddLocationSheet(
            viewModel = viewModel,
            onDismiss = { showLocationCreate = false },
            onCreated = { newId, name ->
                if (newId != null && newId > 0) {
                    val title = name?.takeIf { it.isNotBlank() }
                        ?: items.firstOrNull { it.id == newId }?.title
                        ?: "#$newId"
                    val item = PickerItem(newId, title)
                    pendingCreated = item
                    onSelected(item)
                }
            },
        )
    }
}
