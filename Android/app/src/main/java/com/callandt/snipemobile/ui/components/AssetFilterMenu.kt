package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.util.AssetFilter
import com.callandt.snipemobile.ui.util.AssetFilterOptions
import com.callandt.snipemobile.ui.util.AssetStatusFilterSupport
import com.callandt.snipemobile.ui.util.AssetStatusSelection
import com.callandt.snipemobile.ui.util.L10n

private fun filterFieldLabel(fieldKey: String, value: String? = null): String {
    val label = L10n.string(fieldKey)
    return if (value != null) "$label: $value" else label
}

@Composable
fun AssetFilterMenuButton(
    filter: AssetFilter,
    options: AssetFilterOptions,
    onFilterChange: (AssetFilter) -> Unit,
    showLabel: Boolean = false,
) {
    var expanded by remember { mutableStateOf(false) }
    var statusExpanded by remember { mutableStateOf(false) }
    var categoryExpanded by remember { mutableStateOf(false) }
    var modelExpanded by remember { mutableStateOf(false) }
    var manufacturerExpanded by remember { mutableStateOf(false) }
    var locationExpanded by remember { mutableStateOf(false) }

    val label = if (filter.isActive) {
        L10n.string("filter_active_count", filter.activeCount)
    } else {
        L10n.string("filter")
    }
    val tint = if (filter.isActive) {
        androidx.compose.material3.MaterialTheme.colorScheme.primary
    } else if (showLabel) {
        androidx.compose.material3.MaterialTheme.colorScheme.primary
    } else {
        androidx.compose.material3.MaterialTheme.colorScheme.onSurface
    }

    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    fun openMenu() {
        focusManager.clearFocus()
        keyboardController?.hide()
        expanded = true
    }

    fun applyFilter(newFilter: AssetFilter) {
        focusManager.clearFocus()
        keyboardController?.hide()
        onFilterChange(newFilter)
    }

    Box {
        if (showLabel) {
            TextButton(onClick = { openMenu() }) {
                Text(label, color = tint)
                Icon(
                    Icons.Default.FilterList,
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier.padding(start = 4.dp),
                )
            }
        } else {
            IconButton(onClick = { openMenu() }) {
                Icon(
                    Icons.Default.FilterList,
                    contentDescription = label,
                    tint = tint,
                )
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            if (options.hasStatusOptions) {
                DropdownMenuItem(
                    text = {
                        Text(
                            when (val sel = filter.statusSelection) {
                                AssetStatusSelection.All -> L10n.string("status")
                                AssetStatusSelection.ReadyToDeploy -> filterFieldLabel(
                                    "status",
                                    L10n.string("status_ready_to_deploy"),
                                )
                                AssetStatusSelection.Deployed -> filterFieldLabel(
                                    "status",
                                    L10n.string("status_deployed"),
                                )
                                is AssetStatusSelection.Status -> {
                                    val label = options.statusLabels.firstOrNull { it.id == sel.id }
                                    filterFieldLabel(
                                        "status",
                                        label?.let { AssetStatusFilterSupport.displayName(it) },
                                    )
                                }
                            },
                        )
                    },
                    onClick = { statusExpanded = true },
                )
            }
            if (options.categories.isNotEmpty()) {
                DropdownMenuItem(
                    text = { Text(filterFieldLabel("category", filter.category)) },
                    onClick = { categoryExpanded = true },
                )
            }
            if (options.models.isNotEmpty()) {
                DropdownMenuItem(
                    text = { Text(filterFieldLabel("model", filter.model)) },
                    onClick = { modelExpanded = true },
                )
            }
            if (options.manufacturers.isNotEmpty()) {
                DropdownMenuItem(
                    text = { Text(filterFieldLabel("manufacturer", filter.manufacturer)) },
                    onClick = { manufacturerExpanded = true },
                )
            }
            if (options.locations.isNotEmpty()) {
                DropdownMenuItem(
                    text = { Text(filterFieldLabel("location", filter.location)) },
                    onClick = { locationExpanded = true },
                )
            }
            if (filter.isActive) {
                DropdownMenuItem(
                    text = { Text(L10n.string("filter_clear")) },
                    onClick = {
                        applyFilter(filter.clear())
                        expanded = false
                    },
                )
            }
        }

        StatusFilterSubmenu(
            expanded = statusExpanded,
            onDismiss = { statusExpanded = false },
            filter = filter,
            options = options,
            onFilterChange = { applyFilter(it) },
        )
        StringFilterSubmenu(
            expanded = categoryExpanded,
            title = L10n.string("category"),
            values = options.categories,
            current = filter.category,
            onDismiss = { categoryExpanded = false },
            onSelect = { applyFilter(filter.copy(category = it)) },
        )
        StringFilterSubmenu(
            expanded = modelExpanded,
            title = L10n.string("model"),
            values = options.models,
            current = filter.model,
            onDismiss = { modelExpanded = false },
            onSelect = { applyFilter(filter.copy(model = it)) },
        )
        StringFilterSubmenu(
            expanded = manufacturerExpanded,
            title = L10n.string("manufacturer"),
            values = options.manufacturers,
            current = filter.manufacturer,
            onDismiss = { manufacturerExpanded = false },
            onSelect = { applyFilter(filter.copy(manufacturer = it)) },
        )
        StringFilterSubmenu(
            expanded = locationExpanded,
            title = L10n.string("location"),
            values = options.locations,
            current = filter.location,
            onDismiss = { locationExpanded = false },
            onSelect = { applyFilter(filter.copy(location = it)) },
        )
    }
}

@Composable
private fun StatusFilterSubmenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    filter: AssetFilter,
    options: AssetFilterOptions,
    onFilterChange: (AssetFilter) -> Unit,
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(L10n.string("filter_all")) },
            onClick = {
                onFilterChange(filter.copy(statusSelection = AssetStatusSelection.All))
                onDismiss()
            },
        )
        if (options.showReadyToDeploy) {
            DropdownMenuItem(
                text = { Text(L10n.string("status_ready_to_deploy")) },
                onClick = {
                    onFilterChange(filter.copy(statusSelection = AssetStatusSelection.ReadyToDeploy))
                    onDismiss()
                },
            )
        }
        if (options.showDeployed) {
            DropdownMenuItem(
                text = { Text(L10n.string("status_deployed")) },
                onClick = {
                    onFilterChange(filter.copy(statusSelection = AssetStatusSelection.Deployed))
                    onDismiss()
                },
            )
        }
        options.statusLabels.forEach { label ->
            DropdownMenuItem(
                text = { Text(AssetStatusFilterSupport.displayName(label)) },
                onClick = {
                    onFilterChange(filter.copy(statusSelection = AssetStatusSelection.Status(label.id)))
                    onDismiss()
                },
            )
        }
    }
}

@Composable
private fun StringFilterSubmenu(
    expanded: Boolean,
    title: String,
    values: List<String>,
    current: String?,
    onDismiss: () -> Unit,
    onSelect: (String?) -> Unit,
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(L10n.string("filter_all")) },
            onClick = {
                onSelect(null)
                onDismiss()
            },
        )
        values.forEach { value ->
            DropdownMenuItem(
                text = { Text(value) },
                onClick = {
                    onSelect(value)
                    onDismiss()
                },
            )
        }
    }
}
