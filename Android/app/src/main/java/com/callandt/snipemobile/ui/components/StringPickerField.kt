package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.ui.util.L10n

@Composable
fun StringPickerField(
    label: String,
    options: List<Pair<String, String>>,
    selectedValue: String,
    modifier: Modifier = Modifier,
    placeholder: String = L10n.string("select") + "…",
    emptyOption: Pair<String, String>? = null,
    showLabel: Boolean = true,
    onSelected: (String) -> Unit,
) {
    var showDialog by remember { mutableStateOf(false) }
    val resolvedOptions = remember(options, emptyOption) {
        val empty = emptyOption ?: return@remember options
        if (options.any { it.first == empty.first }) options else listOf(empty) + options
    }
    val selectedLabel = resolvedOptions.firstOrNull { it.first == selectedValue }?.second
        ?: selectedValue.ifEmpty { emptyOption?.second ?: selectedValue }
    val dialogTitle = label.ifBlank { L10n.string("select") }

    Box(modifier = modifier.fillMaxWidth()) {
        OutlinedTextField(
            value = selectedLabel,
            onValueChange = {},
            readOnly = true,
            label = if (showLabel && label.isNotBlank()) {
                { Text(label) }
            } else {
                null
            },
            placeholder = { Text(placeholder) },
            trailingIcon = {
                Icon(Icons.Filled.ArrowDropDown, contentDescription = null)
            },
            modifier = Modifier.fillMaxWidth(),
            enabled = false,
            colors = readOnlyOutlinedTextFieldColors(),
        )
        Box(
            Modifier
                .matchParentSize()
                .clickable { showDialog = true },
        )
    }

    if (showDialog) {
        OptionPickerDialog(
            title = dialogTitle,
            options = resolvedOptions.map { OptionPickerEntry(value = it.first, label = it.second) },
            selectedValue = selectedValue,
            onSelected = {
                onSelected(it.value)
                showDialog = false
            },
            onDismiss = { showDialog = false },
        )
    }
}
