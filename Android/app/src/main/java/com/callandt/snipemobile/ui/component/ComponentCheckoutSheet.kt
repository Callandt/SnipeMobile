package com.callandt.snipemobile.ui.component

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.model.Component
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetPickerSearchText
import kotlinx.coroutines.launch

@Composable
fun ComponentCheckoutSheet(
    component: Component,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSuccess: () -> Unit = {},
) {
    val assets by viewModel.assets.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var selectedAssetId by remember { mutableIntStateOf(0) }
    var quantityText by remember { mutableStateOf("1") }
    var note by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val maxQty = maxOf(1, component.remaining ?: 1)
    val quantity = quantityText.toIntOrNull()?.coerceIn(1, maxQty) ?: 1
    val canSave = selectedAssetId > 0

    LaunchedEffect(Unit) {
        if (assets.isEmpty()) viewModel.apiClient.fetchAssets()
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("check_out"),
            saveLabel = L10n.string("check_out"),
            isSaving = isSaving,
            canSave = canSave,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    val ok = viewModel.apiClient.checkoutComponent(
                        componentId = component.id,
                        assetId = selectedAssetId,
                        quantity = quantity,
                        note = note.trim().takeIf { it.isNotEmpty() },
                    )
                    isSaving = false
                    if (ok) {
                        onSuccess()
                        onDismiss()
                    } else {
                        errorMessage = lastApiMessage ?: L10n.string("checkout_failed")
                    }
                }
            },
        ) {
            SearchablePickerField(
                label = L10n.string("select_asset_short"),
                items = assets.map {
                    PickerItem(
                        it.id,
                        "${it.decodedAssetTag} — ${it.decodedName}",
                        searchText = assetPickerSearchText(it),
                    )
                },
                selectedId = selectedAssetId.takeIf { it > 0 },
                onSelected = { selectedAssetId = it.id },
            )
            OutlinedTextField(
                value = quantityText,
                onValueChange = { input ->
                    quantityText = input.filter { ch -> ch.isDigit() }.take(4)
                },
                label = { Text("${L10n.fieldLabel("quantity", required = true)} (max $maxQty)") },
                modifier = Modifier.fillMaxWidth(),
            )
            component.remaining?.let {
                Text(
                    "${L10n.string("remaining")}: $it",
                    color = androidx.compose.material3.MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text(L10n.string("note")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
            )
            errorMessage?.let { Text(it, color = androidx.compose.material3.MaterialTheme.colorScheme.error) }
        }
    }
}

@Composable
fun ComponentCheckinConfirmDialog(
    assetName: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(L10n.string("checkin_confirm_title")) },
        text = {
            Column {
                Text(
                    if (assetName.isNotEmpty()) {
                        L10n.string("checkin_user_confirm_message", assetName)
                    } else {
                        L10n.string("checkin_generic_confirm_message")
                    },
                )
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onConfirm) { Text(L10n.string("check_in_lower")) }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text(L10n.string("cancel")) }
        },
    )
}
