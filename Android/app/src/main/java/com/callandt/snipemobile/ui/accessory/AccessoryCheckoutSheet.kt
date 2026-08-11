package com.callandt.snipemobile.ui.accessory

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
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
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetPickerSearchText
import com.callandt.snipemobile.ui.util.locationPickerSearchText
import com.callandt.snipemobile.ui.util.userPickerSearchText
import kotlinx.coroutines.launch

private enum class AccessoryCheckoutTarget(val labelKey: String) {
    User("user"),
    Location("location"),
    Asset("asset"),
}

@Composable
fun AccessoryCheckoutSheet(
    accessory: Accessory,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSuccess: () -> Unit = {},
) {
    val users by viewModel.users.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var tabIndex by remember { mutableIntStateOf(0) }
    var selectedUserId by remember { mutableIntStateOf(0) }
    var selectedLocationId by remember { mutableIntStateOf(0) }
    var selectedAssetId by remember { mutableIntStateOf(0) }
    var note by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val target = AccessoryCheckoutTarget.entries[tabIndex.coerceIn(0, 2)]
    val canSave = when (target) {
        AccessoryCheckoutTarget.User -> selectedUserId > 0
        AccessoryCheckoutTarget.Location -> selectedLocationId > 0
        AccessoryCheckoutTarget.Asset -> selectedAssetId > 0
    }

    LaunchedEffect(Unit) {
        if (assets.isEmpty()) viewModel.apiClient.fetchAssets()
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("check_out_accessory"),
            saveLabel = L10n.string("check_out"),
            isSaving = isSaving,
            canSave = canSave,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    val body = mutableMapOf<String, Any?>("checkout_qty" to 1)
                    note.trim().takeIf { it.isNotEmpty() }?.let { body["note"] = it }
                    when (target) {
                        AccessoryCheckoutTarget.User -> {
                            body["checkout_to_type"] = "user"
                            body["assigned_user"] = selectedUserId
                        }
                        AccessoryCheckoutTarget.Location -> {
                            body["checkout_to_type"] = "location"
                            body["assigned_location"] = selectedLocationId
                        }
                        AccessoryCheckoutTarget.Asset -> {
                            body["checkout_to_type"] = "asset"
                            body["assigned_asset"] = selectedAssetId
                        }
                    }
                    val ok = viewModel.apiClient.checkoutAccessoryCustom(accessory.id, body)
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
            TabRow(selectedTabIndex = tabIndex) {
                AccessoryCheckoutTarget.entries.forEachIndexed { index, checkoutTarget ->
                    Tab(
                        selected = tabIndex == index,
                        onClick = { tabIndex = index },
                        text = { Text(L10n.string(checkoutTarget.labelKey)) },
                    )
                }
            }
            when (target) {
                AccessoryCheckoutTarget.User -> SearchablePickerField(
                    label = L10n.string("user"),
                    items = users.map {
                        PickerItem(it.id, it.decodedName, searchText = userPickerSearchText(it))
                    },
                    selectedId = selectedUserId.takeIf { it > 0 },
                    onSelected = { selectedUserId = it.id },
                )
                AccessoryCheckoutTarget.Location -> SearchablePickerField(
                    label = L10n.string("location"),
                    items = locations.map {
                        PickerItem(it.id, it.decodedName, searchText = locationPickerSearchText(it))
                    },
                    selectedId = selectedLocationId.takeIf { it > 0 },
                    onSelected = { selectedLocationId = it.id },
                )
                AccessoryCheckoutTarget.Asset -> SearchablePickerField(
                    label = L10n.string("asset"),
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
fun AccessoryCheckinConfirmDialog(
    assigneeName: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(L10n.string("checkin_confirm_title")) },
        text = {
            Column {
                Text(
                    if (assigneeName.isNotEmpty()) {
                        L10n.string("checkin_user_confirm_message", assigneeName)
                    } else {
                        L10n.string("checkin_generic_confirm_message")
                    },
                )
            }
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onConfirm) { Text(L10n.string("check_in")) }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text(L10n.string("cancel")) }
        },
    )
}
