package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.MaterialTheme
import com.callandt.snipemobile.ui.util.L10n

// Disabled outline is 12% and looks thin.
@Composable
fun readOnlyOutlinedTextFieldColors(): TextFieldColors {
    val scheme = MaterialTheme.colorScheme
    return OutlinedTextFieldDefaults.colors(
        disabledTextColor = scheme.onSurface,
        disabledContainerColor = Color.Transparent,
        disabledBorderColor = scheme.outline,
        disabledLeadingIconColor = scheme.onSurfaceVariant,
        disabledTrailingIconColor = scheme.onSurfaceVariant,
        disabledLabelColor = scheme.onSurfaceVariant,
        disabledPlaceholderColor = scheme.onSurfaceVariant,
    )
}

data class PickerItem(
    val id: Int,
    val title: String,
    val subtitle: String? = null,
    // Search only. Not shown.
    val searchText: String? = null,
)

@Composable
fun SearchablePickerField(
    label: String,
    items: List<PickerItem>,
    selectedId: Int?,
    modifier: Modifier = Modifier,
    placeholder: String = L10n.string("select") + "…",
    addNewLabel: String? = null,
    onAddNew: (() -> Unit)? = null,
    allowClear: Boolean = false,
    clearLabel: String? = null,
    onClear: (() -> Unit)? = null,
    onSelected: (PickerItem) -> Unit,
) {
    var showDialog by remember { mutableStateOf(false) }
    val selectedTitle = items.firstOrNull { it.id == selectedId }?.title
    val genericPlaceholder = L10n.string("select") + "…"
    val resolvedClearLabel = clearLabel ?: if (placeholder == genericPlaceholder) {
        L10n.string("mgmt_none")
    } else {
        placeholder
    }
    val canClear = onClear != null || allowClear

    Box(modifier = modifier.fillMaxWidth().clickable { showDialog = true }) {
        OutlinedTextField(
            value = selectedTitle ?: "",
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            placeholder = { Text(placeholder) },
            trailingIcon = {
                Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = false,
            colors = readOnlyOutlinedTextFieldColors(),
        )
    }

    if (showDialog) {
        val options = buildList {
            if (canClear) {
                add(OptionPickerEntry(value = "", label = resolvedClearLabel))
            }
            items.forEach { item ->
                add(
                    OptionPickerEntry(
                        value = item.id.toString(),
                        label = item.title,
                        subtitle = item.subtitle,
                        searchText = item.searchText,
                    ),
                )
            }
        }
        OptionPickerDialog(
            title = label,
            options = options,
            selectedValue = selectedId?.toString() ?: if (canClear) "" else null,
            addNewLabel = addNewLabel,
            onAddNew = onAddNew?.let { add ->
                {
                    showDialog = false
                    add()
                }
            },
            onDismiss = { showDialog = false },
            onSelected = { entry ->
                if (entry.value.isEmpty() && canClear) {
                    onClear?.invoke()
                } else {
                    val id = entry.value.toIntOrNull()
                    val item = items.firstOrNull { it.id == id }
                    if (item != null) onSelected(item)
                }
                showDialog = false
            },
        )
    }
}

@Composable
fun SearchablePickerDialog(
    title: String,
    items: List<PickerItem>,
    onDismiss: () -> Unit,
    onSelected: (PickerItem) -> Unit,
    addNewLabel: String? = null,
    onAddNew: (() -> Unit)? = null,
    allowClear: Boolean = false,
    clearLabel: String = L10n.string("mgmt_none"),
    onClear: (() -> Unit)? = null,
) {
    val options = buildList {
        if (allowClear && onClear != null) {
            add(OptionPickerEntry(value = "", label = clearLabel))
        }
        items.forEach { item ->
            add(
                OptionPickerEntry(
                    value = item.id.toString(),
                    label = item.title,
                    subtitle = item.subtitle,
                    searchText = item.searchText,
                ),
            )
        }
    }
    OptionPickerDialog(
        title = title,
        options = options,
        selectedValue = null,
        addNewLabel = addNewLabel,
        onAddNew = onAddNew,
        onDismiss = onDismiss,
        onSelected = { entry ->
            if (entry.value.isEmpty() && onClear != null) {
                onClear()
            } else {
                val id = entry.value.toIntOrNull()
                val item = items.firstOrNull { it.id == id }
                if (item != null) onSelected(item)
            }
        },
    )
}
