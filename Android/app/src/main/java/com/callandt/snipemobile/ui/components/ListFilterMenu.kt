package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.ListFilter
import com.callandt.snipemobile.ui.util.ListFilterOption

@Composable
fun ListFilterMenuButton(
    filter: ListFilter,
    options: List<ListFilterOption>,
    onFilterChange: (ListFilter) -> Unit,
    showLabel: Boolean = true,
) {
    val usable = remember(options) { options.filter { it.values.isNotEmpty() } }
    if (usable.isEmpty()) return

    var expanded by remember { mutableStateOf(false) }
    var openDimension by remember { mutableStateOf<String?>(null) }

    val label = if (filter.isActive) {
        L10n.string("filter_active_count", filter.activeCount)
    } else {
        L10n.string("filter")
    }
    val tint = if (filter.isActive || showLabel) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurface
    }

    Box {
        if (showLabel) {
            TextButton(onClick = { expanded = true }) {
                Text(label, color = tint)
                Icon(
                    Icons.Default.FilterList,
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier.padding(start = 4.dp),
                )
            }
        } else {
            IconButton(onClick = { expanded = true }) {
                Icon(Icons.Default.FilterList, contentDescription = label, tint = tint)
            }
        }

        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            usable.forEach { option ->
                val current = filter.selections[option.title]
                DropdownMenuItem(
                    text = {
                        Text(
                            if (current != null) "${option.title}: $current" else option.title,
                        )
                    },
                    onClick = { openDimension = option.title },
                )
            }
            if (filter.isActive) {
                DropdownMenuItem(
                    text = { Text(L10n.string("filter_clear")) },
                    onClick = {
                        onFilterChange(filter.clear())
                        expanded = false
                    },
                )
            }
        }

        usable.forEach { option ->
            DropdownMenu(
                expanded = openDimension == option.title,
                onDismissRequest = { openDimension = null },
            ) {
                DropdownMenuItem(
                    text = { Text(L10n.string("filter_all")) },
                    onClick = {
                        onFilterChange(filter.withSelection(option.title, null))
                        openDimension = null
                        expanded = false
                    },
                )
                option.values.forEach { value ->
                    DropdownMenuItem(
                        text = { Text(value) },
                        onClick = {
                            onFilterChange(filter.withSelection(option.title, value))
                            openDimension = null
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}
