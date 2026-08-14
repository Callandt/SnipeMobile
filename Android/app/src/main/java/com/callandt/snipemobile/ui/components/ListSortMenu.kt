package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.ListSort
import com.callandt.snipemobile.ui.util.ListSortField
import com.callandt.snipemobile.ui.util.ListSortKey
import com.callandt.snipemobile.ui.util.ListSortOrder
import kotlinx.coroutines.delay

@Composable
fun <T> ListSortMenuButton(
    sort: ListSort,
    keys: List<ListSortKey<T>>,
    onSortChange: (ListSort) -> Unit,
) {
    val fields = remember(keys) { keys.map { it.field } }
    var expanded by remember { mutableStateOf(false) }
    var pendingSort by remember { mutableStateOf<ListSort?>(null) }
    val tint = MaterialTheme.colorScheme.primary
    val keyboardController = LocalSoftwareKeyboardController.current

    LaunchedEffect(expanded) {
        if (expanded) return@LaunchedEffect
        val next = pendingSort ?: return@LaunchedEffect
        pendingSort = null
        withFrameNanos { }
        delay(50)
        onSortChange(next)
    }

    Box {
        TextButton(onClick = {
            keyboardController?.hide()
            expanded = true
        }) {
            Text(L10n.string("sort"), color = tint)
            Icon(
                Icons.Default.SwapVert,
                contentDescription = null,
                tint = tint,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            SortOrderItem(
                title = sort.field.ascendingTitle,
                selected = sort.order == ListSortOrder.Ascending,
                onClick = {
                    pendingSort = sort.copy(order = ListSortOrder.Ascending)
                    expanded = false
                },
            )
            SortOrderItem(
                title = sort.field.descendingTitle,
                selected = sort.order == ListSortOrder.Descending,
                onClick = {
                    pendingSort = sort.copy(order = ListSortOrder.Descending)
                    expanded = false
                },
            )
            HorizontalDivider()
            fields.forEach { field ->
                SortFieldItem(field, sort) { newSort ->
                    pendingSort = newSort
                    expanded = false
                }
            }
        }
    }
}

@Composable
private fun SortFieldItem(
    field: ListSortField,
    sort: ListSort,
    onSortChange: (ListSort) -> Unit,
) {
    DropdownMenuItem(
        text = { Text(field.localizedTitle) },
        trailingIcon = if (sort.field == field) {
            { Icon(Icons.Default.Check, contentDescription = null) }
        } else {
            null
        },
        onClick = {
            onSortChange(
                if (sort.field == field) {
                    sort
                } else {
                    ListSort(field, field.defaultOrder)
                },
            )
        },
    )
}

@Composable
private fun SortOrderItem(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(title) },
        trailingIcon = if (selected) {
            { Icon(Icons.Default.Check, contentDescription = null) }
        } else {
            null
        },
        onClick = onClick,
    )
}
