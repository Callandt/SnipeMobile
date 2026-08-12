package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.util.L10n

data class PickerItem(
    val id: Int,
    val title: String,
    val subtitle: String? = null,
    /** Extra text used only for search filtering (not shown in the UI). */
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
    onClear: (() -> Unit)? = null,
    onSelected: (PickerItem) -> Unit,
) {
    var showDialog by remember { mutableStateOf(false) }
    val selectedTitle = items.firstOrNull { it.id == selectedId }?.title

    Box(modifier = modifier.fillMaxWidth().clickable { showDialog = true }) {
        OutlinedTextField(
            value = selectedTitle ?: "",
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            placeholder = { Text(placeholder) },
            modifier = Modifier.fillMaxWidth(),
            enabled = false,
        )
    }

    if (showDialog) {
        SearchablePickerDialog(
            title = label,
            items = items,
            addNewLabel = addNewLabel,
            onAddNew = onAddNew?.let { add ->
                {
                    showDialog = false
                    add()
                }
            },
            allowClear = allowClear && selectedId != null,
            onClear = {
                showDialog = false
                onClear?.invoke()
            },
            onDismiss = { showDialog = false },
            onSelected = { item ->
                onSelected(item)
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
    onClear: (() -> Unit)? = null,
) {
    var query by remember { mutableStateOf("") }
    val filtered = remember(items, query) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) items
        else items.filter {
            it.title.lowercase().contains(q) ||
                (it.subtitle?.lowercase()?.contains(q) == true) ||
                (it.searchText?.lowercase()?.contains(q) == true)
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                if (onAddNew != null && !addNewLabel.isNullOrBlank()) {
                    TextButton(
                        onClick = onAddNew,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Add, contentDescription = null)
                            Text(
                                text = addNewLabel,
                                modifier = Modifier.padding(start = 6.dp),
                            )
                        }
                    }
                }
                if (allowClear && onClear != null) {
                    TextButton(
                        onClick = onClear,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(L10n.string("clear_selection"))
                    }
                }
                LazyColumn(modifier = Modifier.heightIn(max = 360.dp)) {
                    item {
                        OutlinedTextField(
                            value = query,
                            onValueChange = { query = it },
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text(L10n.string("search") + "…") },
                            singleLine = true,
                        )
                    }
                    items(filtered, key = { it.id }) { item ->
                        Text(
                            text = buildString {
                                append(item.title)
                                if (!item.subtitle.isNullOrBlank()) append("\n${item.subtitle}")
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onSelected(item) }
                                .padding(vertical = 12.dp, horizontal = 4.dp),
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(L10n.string("close")) }
        },
    )
}
