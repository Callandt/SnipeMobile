package com.callandt.snipemobile.ui.asset

import android.view.WindowManager
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import com.callandt.snipemobile.data.model.CustomField
import com.callandt.snipemobile.data.model.FieldDefinition
import com.callandt.snipemobile.data.model.StatusLabel
import com.callandt.snipemobile.ui.components.StringPickerField
import com.callandt.snipemobile.ui.util.AssetStatusFilterSupport
import com.callandt.snipemobile.ui.util.L10n
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal fun normalizeDecimalForApi(value: String): String? {
    val trimmed = value.trim().replace(',', '.')
    if (trimmed.isEmpty()) return null
    return trimmed.toDoubleOrNull()?.toString() ?: trimmed
}

internal fun formatApiDate(date: Date): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.format(date)

internal fun parseApiDate(raw: String?): Date? {
    val trimmed = raw?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    return SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
        isLenient = false
    }.parse(trimmed.take(10))
}

internal fun statusDisplayName(label: StatusLabel): String =
    AssetStatusFilterSupport.displayName(label)

internal fun isDeployableStatus(label: StatusLabel): Boolean {
    val type = label.type?.trim()?.lowercase().orEmpty()
    if (type.isNotEmpty()) return type == "deployable"
    val meta = label.statusMeta?.trim()?.lowercase().orEmpty()
    return meta == "deployable" || meta == "ready_to_deploy" || meta.isEmpty()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AssetFormSheetScaffold(
    title: String,
    saveLabel: String,
    isSaving: Boolean,
    canSave: Boolean,
    onDismiss: () -> Unit,
    onSave: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onDismiss, enabled = !isSaving) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("cancel"))
                    }
                },
                actions = {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.padding(end = 16.dp))
                    } else {
                        TextButton(onClick = onSave, enabled = canSave) {
                            Text(saveLabel)
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(12.dp),
        ) {
            content()
        }
    }
}

@Composable
internal fun AssetFullScreenSheet(
    onDismiss: () -> Unit,
    content: @Composable () -> Unit,
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
            dismissOnBackPress = true,
            dismissOnClickOutside = false,
        ),
    ) {
        val view = LocalView.current
        SideEffect {
            val window = (view.parent as? DialogWindowProvider)?.window ?: return@SideEffect
            WindowCompat.setDecorFitsSystemWindows(window, false)
            // Full-screen dialog needs MATCH_PARENT on the window.
            window.setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
            )
        }
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
            contentColor = MaterialTheme.colorScheme.onBackground,
        ) {
            content()
        }
    }
}

@Composable
internal fun FormSectionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
    )
}

/** Prefer the existing value; otherwise use the field default. */
internal fun initialCustomFieldValue(existing: String?, defaultValue: String?): String {
    if (!existing.isNullOrBlank()) return existing
    return defaultValue?.trim().orEmpty()
}

/** API key for a custom field (existing key, then fieldset columns, then slug). */
internal fun resolveCustomFieldApiKey(
    displayName: String,
    existingAssetFields: Map<String, CustomField>?,
    fieldDefs: List<FieldDefinition>,
): String {
    existingAssetFields?.get(displayName)?.field?.takeIf { it.isNotEmpty() }?.let { return it }
    val def = fieldDefs.firstOrNull { it.name == displayName } ?: return displayName
    def.field?.takeIf { it.isNotEmpty() }?.let { return it }
    def.dbField?.takeIf { it.isNotEmpty() }?.let { return it }
    def.dbColumnName?.takeIf { it.isNotEmpty() }?.let { return it }
    def.dbColumn?.takeIf { it.isNotEmpty() }?.let { return it }
    val folded = Normalizer.normalize(def.name, Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase(Locale.US)
    val slugRaw = folded.map { ch -> if (ch.isLetterOrDigit()) ch else '_' }.joinToString("")
    val slug = slugRaw.replace(Regex("_+"), "_").trim('_')
    return "_snipeit_${slug}_${def.id}"
}

/** Editable custom fields, including orphan keys still present in [values]. */
@Composable
internal fun CustomFieldsFormSection(
    fieldDefs: List<FieldDefinition>,
    values: Map<String, String>,
    onValueChange: (String, String) -> Unit,
    showEmptyState: Boolean = true,
) {
    val extraKeys = values.keys.filter { key -> fieldDefs.none { it.name == key } }.sorted()
    if (fieldDefs.isEmpty() && extraKeys.isEmpty()) {
        if (showEmptyState) {
            FormSectionTitle(L10n.string("custom_fields"))
            Text(
                text = L10n.string("no_custom_fields"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        return
    }
    FormSectionTitle(L10n.string("custom_fields"))
    fieldDefs.forEach { fieldDef ->
        CustomFieldRow(
            label = fieldDef.name,
            type = fieldDef.type,
            options = fieldDef.fieldValuesArray,
            value = values[fieldDef.name].orEmpty(),
            onValueChange = { onValueChange(fieldDef.name, it) },
        )
    }
    extraKeys.forEach { key ->
        CustomFieldRow(
            label = key,
            type = null,
            options = null,
            value = values[key].orEmpty(),
            onValueChange = { onValueChange(key, it) },
        )
    }
}

@Composable
private fun CustomFieldRow(
    label: String,
    type: String?,
    options: List<String>?,
    value: String,
    onValueChange: (String) -> Unit,
) {
    when {
        type == "listbox" && !options.isNullOrEmpty() -> {
            val sortedOptions = options.sortedWith(String.CASE_INSENSITIVE_ORDER)
            StringPickerField(
                label = label,
                options = listOf("" to "—") + sortedOptions.map { it to it },
                selectedValue = value,
                onSelected = onValueChange,
            )
        }
        type == "checkbox" -> {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(label, modifier = Modifier.weight(1f))
                Switch(
                    checked = value == "1" || value.equals("true", ignoreCase = true),
                    onCheckedChange = { onValueChange(if (it) "1" else "0") },
                )
            }
        }
        else -> {
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                label = { Text(label) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = type != "textarea",
                minLines = if (type == "textarea") 3 else 1,
            )
        }
    }
}
