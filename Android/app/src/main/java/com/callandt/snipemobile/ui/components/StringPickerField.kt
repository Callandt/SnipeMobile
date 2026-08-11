package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
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

@Composable
fun StringPickerField(
    label: String,
    options: List<Pair<String, String>>,
    selectedValue: String,
    modifier: Modifier = Modifier,
    placeholder: String = L10n.string("select") + "…",
    onSelected: (String) -> Unit,
) {
    var showDialog by remember { mutableStateOf(false) }
    val selectedLabel = options.firstOrNull { it.first == selectedValue }?.second ?: selectedValue

    Box(modifier = modifier.fillMaxWidth().clickable { showDialog = true }) {
        OutlinedTextField(
            value = selectedLabel,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            placeholder = { Text(placeholder) },
            modifier = Modifier.fillMaxWidth(),
            enabled = false,
        )
    }

    if (showDialog) {
        var query by remember { mutableStateOf("") }
        val filtered = remember(options, query) {
            val q = query.trim().lowercase()
            if (q.isEmpty()) options
            else options.filter { it.second.lowercase().contains(q) }
        }
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text(label) },
            text = {
                LazyColumn(modifier = Modifier.heightIn(max = 360.dp)) {
                    item {
                        OutlinedTextField(
                            value = query,
                            onValueChange = { query = it },
                            label = { Text(L10n.string("search")) },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    items(filtered, key = { it.first }) { (value, display) ->
                        Text(
                            text = display,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    onSelected(value)
                                    showDialog = false
                                }
                                .padding(vertical = 12.dp),
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { showDialog = false }) { Text(L10n.string("close")) }
            },
        )
    }
}
