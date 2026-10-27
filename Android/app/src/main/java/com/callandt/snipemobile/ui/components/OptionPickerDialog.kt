package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.callandt.snipemobile.ui.util.L10n

data class OptionPickerEntry(
    val value: String,
    val label: String,
    val subtitle: String? = null,
    val searchText: String? = null,
)

/** Full-screen searchable option list used by every form picklist. */
@Composable
fun OptionPickerDialog(
    title: String,
    options: List<OptionPickerEntry>,
    selectedValue: String?,
    onSelected: (OptionPickerEntry) -> Unit,
    onDismiss: () -> Unit,
    addNewLabel: String? = null,
    onAddNew: (() -> Unit)? = null,
) {
    var query by remember { mutableStateOf("") }
    val keyboard = LocalSoftwareKeyboardController.current
    val filtered = remember(options, query) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) {
            options
        } else {
            options.filter {
                it.label.lowercase().contains(q) ||
                    (it.subtitle?.lowercase()?.contains(q) == true) ||
                    (it.searchText?.lowercase()?.contains(q) == true) ||
                    it.value.lowercase().contains(q)
            }
        }
    }
    val listState = rememberLazyListState()
    val selectedIndex = remember(filtered, selectedValue) {
        filtered.indexOfFirst { it.value == selectedValue }.takeIf { it >= 0 }
    }

    LaunchedEffect(selectedIndex) {
        val index = selectedIndex ?: return@LaunchedEffect
        listState.scrollToItem(index)
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .padding(16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                tonalElevation = 6.dp,
                modifier = Modifier
                    .widthIn(max = 720.dp)
                    .fillMaxWidth()
                    .fillMaxHeight(),
            ) {
                Column(
                    modifier = Modifier.padding(start = 20.dp, top = 20.dp, end = 20.dp, bottom = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(text = title, style = MaterialTheme.typography.titleLarge)

                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        label = { Text(L10n.string("search")) },
                        leadingIcon = {
                            Icon(Icons.Filled.Search, contentDescription = null)
                        },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )

                    if (onAddNew != null && !addNewLabel.isNullOrBlank()) {
                        TextButton(
                            onClick = onAddNew,
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(Icons.Default.Add, contentDescription = null)
                                Text(addNewLabel)
                            }
                        }
                        HorizontalDivider()
                    }

                    if (filtered.isEmpty()) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth(),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = L10n.string("none"),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        LazyColumn(
                            state = listState,
                            modifier = Modifier.weight(1f),
                        ) {
                            itemsIndexed(
                                filtered,
                                key = { index, option -> "$index\u0000${option.value}" },
                            ) { _, option ->
                                val selected = option.value == selectedValue
                                Column(modifier = Modifier.fillMaxWidth()) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .heightIn(min = 56.dp)
                                            .background(
                                                if (selected) {
                                                    MaterialTheme.colorScheme.secondaryContainer
                                                } else {
                                                    MaterialTheme.colorScheme.surface
                                                },
                                            )
                                            .clickable {
                                                keyboard?.hide()
                                                onSelected(option)
                                            }
                                            .padding(horizontal = 8.dp, vertical = 16.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                                    ) {
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = option.label,
                                                style = MaterialTheme.typography.bodyLarge,
                                                color = MaterialTheme.colorScheme.onSurface,
                                            )
                                            if (!option.subtitle.isNullOrBlank()) {
                                                Text(
                                                    text = option.subtitle,
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                )
                                            }
                                        }
                                        if (selected) {
                                            Icon(
                                                Icons.Filled.Check,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.primary,
                                            )
                                        }
                                    }
                                    HorizontalDivider()
                                }
                            }
                        }
                    }

                    TextButton(
                        onClick = onDismiss,
                        modifier = Modifier.align(Alignment.End),
                    ) {
                        Text(L10n.string("close"))
                    }
                }
            }
        }
    }
}
