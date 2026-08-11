package com.callandt.snipemobile.ui.license

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
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.data.model.LicenseSeatRow
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetPickerSearchText
import com.callandt.snipemobile.ui.util.userPickerSearchText
import kotlinx.coroutines.launch

private enum class LicenseCheckoutTarget(val labelKey: String) {
    User("user"),
    Asset("asset"),
}

@Composable
fun LicenseCheckoutSheet(
    license: License,
    availableSeats: List<LicenseSeatRow>,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSuccess: () -> Unit = {},
) {
    val users by viewModel.users.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val scope = rememberCoroutineScope()

    var tabIndex by remember { mutableIntStateOf(0) }
    var selectedUserId by remember { mutableIntStateOf(0) }
    var selectedAssetId by remember { mutableIntStateOf(0) }
    var note by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val freeSeats = remember(availableSeats) {
        availableSeats.filter {
            it.assignedUser == null && it.assignedAsset == null && it.disabled != true
        }
    }
    val canSave = freeSeats.isNotEmpty() && when (tabIndex) {
        0 -> selectedUserId > 0
        else -> selectedAssetId > 0
    }

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
                val seat = freeSeats.firstOrNull()
                if (seat == null) {
                    errorMessage = L10n.string("no_free_seats")
                    return@AssetFormSheetScaffold
                }
                isSaving = true
                scope.launch {
                    val error = viewModel.apiClient.checkoutLicenseSeat(
                        licenseId = license.id,
                        seatId = seat.id,
                        userId = if (tabIndex == 0) selectedUserId.takeIf { it > 0 } else null,
                        assetId = if (tabIndex == 1) selectedAssetId.takeIf { it > 0 } else null,
                        note = note.trim().takeIf { it.isNotEmpty() },
                    )
                    isSaving = false
                    if (error == null) {
                        onSuccess()
                        onDismiss()
                    } else {
                        errorMessage = error
                    }
                }
            },
        ) {
            if (license.reassignable == false) {
                Text(
                    L10n.string("checkout_unreassignable_warning"),
                    color = androidx.compose.material3.MaterialTheme.colorScheme.error,
                )
            }
            if (freeSeats.isEmpty()) {
                Text(L10n.string("no_free_seats"))
            }
            TabRow(selectedTabIndex = tabIndex) {
                LicenseCheckoutTarget.entries.forEachIndexed { index, target ->
                    Tab(
                        selected = tabIndex == index,
                        onClick = { tabIndex = index },
                        text = { Text(L10n.string(target.labelKey)) },
                    )
                }
            }
            when (tabIndex) {
                0 -> SearchablePickerField(
                    label = L10n.string("user"),
                    items = users.map {
                        PickerItem(it.id, it.decodedName, searchText = userPickerSearchText(it))
                    },
                    selectedId = selectedUserId.takeIf { it > 0 },
                    onSelected = { selectedUserId = it.id },
                )
                else -> SearchablePickerField(
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
fun LicenseCheckinConfirmDialog(
    message: String,
    warningUnreassignable: Boolean,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(L10n.string("checkin_confirm_title")) },
        text = {
            Text(
                buildString {
                    append(message)
                    if (warningUnreassignable) {
                        append("\n\n")
                        append(L10n.string("checkin_unreassignable_warning"))
                    }
                },
            )
        },
        confirmButton = {
            androidx.compose.material3.TextButton(onClick = onConfirm) { Text(L10n.string("check_in")) }
        },
        dismissButton = {
            androidx.compose.material3.TextButton(onClick = onDismiss) { Text(L10n.string("cancel")) }
        },
    )
}
