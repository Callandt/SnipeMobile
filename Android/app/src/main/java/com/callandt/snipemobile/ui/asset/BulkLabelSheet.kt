package com.callandt.snipemobile.ui.asset

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

/** Bulk label PDF generation. */
@Composable
fun BulkLabelSheet(
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val assets by viewModel.assets.collectAsState()

    var selectedAssetIds by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var showAssetPicker by remember { mutableStateOf(false) }
    var isGenerating by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val scope = rememberCoroutineScope()
    val canGenerate = selectedAssetIds.isNotEmpty() && !isGenerating

    val selectedAssets = remember(assets, selectedAssetIds) {
        assets.filter { selectedAssetIds.contains(it.id) }
            .sortedBy { it.decodedAssetTag.lowercase() }
    }

    suspend fun generate() {
        val tags = selectedAssetIds.mapNotNull { id ->
            assets.firstOrNull { it.id == id }?.decodedAssetTag?.trim()?.takeIf { it.isNotEmpty() }
        }
        if (tags.isEmpty()) {
            errorMessage = L10n.string("labels_no_asset_tags")
            return
        }
        isGenerating = true
        val bytes = viewModel.apiClient.generateAssetLabels(tags)
        isGenerating = false
        if (bytes == null) {
            errorMessage = viewModel.apiClient.lastApiMessage.value ?: L10n.string("labels_generate_failed")
            return
        }
        val file = LabelPdfSupport.writeTemporaryPdf(context, bytes, "labels")
        if (file == null || !LabelPdfSupport.openPdf(context, file)) {
            errorMessage = L10n.string("labels_generate_failed")
            return
        }
        onDismiss()
    }

    AssetFullScreenSheet(onDismiss = { if (!isGenerating) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("generate_labels"),
            saveLabel = L10n.string("labels_generate_run", selectedAssetIds.size),
            isSaving = isGenerating,
            canSave = canGenerate,
            onDismiss = { if (!isGenerating) onDismiss() },
            onSave = { scope.launch { generate() } },
        ) {
            FormSectionTitle(L10n.string("assets"))
            Text(
                L10n.string("assets_selected_count", selectedAssetIds.size),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            TextButton(onClick = { showAssetPicker = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Checklist, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("select_assets"))
            }
            if (selectedAssets.isNotEmpty()) {
                Column {
                    selectedAssets.forEach { asset ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { selectedAssetIds = selectedAssetIds - asset.id }
                                .padding(vertical = 6.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    asset.decodedModelName.ifEmpty { asset.decodedName },
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                val subtitle = listOf(asset.decodedAssetTag, asset.decodedName)
                                    .filter { it.isNotEmpty() }
                                    .joinToString(" · ")
                                if (subtitle.isNotEmpty()) {
                                    Text(
                                        subtitle,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            Icon(Icons.Filled.Close, contentDescription = L10n.string("delete"))
                        }
                    }
                    TextButton(onClick = { selectedAssetIds = emptySet() }) {
                        Text(L10n.string("clear_selection"))
                    }
                }
            }

            Text(
                L10n.string("labels_server_settings_footer"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }

    if (showAssetPicker) {
        AssetFullScreenSheet(onDismiss = { showAssetPicker = false }) {
            AssetMultiSelectScreen(
                assets = assets,
                selectedAssetIds = selectedAssetIds,
                onSelectionChange = { selectedAssetIds = it },
                onDone = { showAssetPicker = false },
            )
        }
    }

    errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(L10n.string("generate_labels")) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { errorMessage = null }) { Text(L10n.string("ok")) } },
        )
    }
}
