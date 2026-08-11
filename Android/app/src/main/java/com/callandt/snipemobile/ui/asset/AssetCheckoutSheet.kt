package com.callandt.snipemobile.ui.asset

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
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
import com.callandt.snipemobile.data.api.UploadFile
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetPickerSearchText
import com.callandt.snipemobile.ui.util.locationPickerSearchText
import com.callandt.snipemobile.ui.util.userPickerSearchText
import kotlinx.coroutines.launch
import java.util.Date

private enum class AssetCheckoutTarget(val labelKey: String) {
    User("user"),
    Location("location"),
    Asset("asset"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetCheckoutSheet(
    asset: Asset,
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
    var notes by remember { mutableStateOf("") }
    var hasExpectedCheckin by remember { mutableStateOf(false) }
    var expectedCheckinDate by remember { mutableStateOf(Date()) }
    var showDatePicker by remember { mutableStateOf(false) }
    var pendingImages: List<PendingAssetImage> by remember { mutableStateOf(emptyList()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var dismissAfterError by remember { mutableStateOf(false) }

    val target = AssetCheckoutTarget.entries[tabIndex.coerceIn(0, 2)]
    val canSave = when (target) {
        AssetCheckoutTarget.User -> selectedUserId > 0
        AssetCheckoutTarget.Location -> selectedLocationId > 0
        AssetCheckoutTarget.Asset -> selectedAssetId > 0
    }

    val filteredAssets = remember(assets, asset.id) {
        assets.filter { it.id != asset.id }
            .sortedBy { it.decodedAssetTag.lowercase() }
    }

    LaunchedEffect(Unit) {
        if (assets.isEmpty()) viewModel.apiClient.fetchAssets()
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
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
                    val body = mutableMapOf<String, Any?>(
                        "name" to asset.decodedName,
                        "note" to notes.trim(),
                    )
                    if (hasExpectedCheckin) {
                        body["expected_checkin"] = formatApiDate(expectedCheckinDate)
                    }
                    when (target) {
                        AssetCheckoutTarget.User -> {
                            body["checkout_to_type"] = "user"
                            body["assigned_user"] = selectedUserId
                        }
                        AssetCheckoutTarget.Location -> {
                            body["checkout_to_type"] = "location"
                            body["assigned_location"] = selectedLocationId
                        }
                        AssetCheckoutTarget.Asset -> {
                            body["checkout_to_type"] = "asset"
                            body["assigned_asset"] = selectedAssetId
                        }
                    }

                    val success = viewModel.apiClient.checkoutAssetCustom(asset.id, body)
                    var photoUploadFailed = false
                    if (success && pendingImages.isNotEmpty()) {
                        val noteForFiles = notes.trim().takeIf { it.isNotEmpty() }
                            ?: L10n.string("checkout_photo_note")
                        val files = pendingImages.mapIndexed { index, image ->
                            UploadFile("checkout_${index + 1}.jpg", image.mimeType, image.bytes)
                        }
                        val uploaded = viewModel.apiClient.uploadAssetFiles(asset.id, files, noteForFiles)
                        photoUploadFailed = !uploaded
                    }

                    isSaving = false
                    if (success) {
                        onSuccess()
                        if (photoUploadFailed) {
                            dismissAfterError = true
                            errorMessage = lastApiMessage ?: L10n.string("photo_upload_failed")
                        } else {
                            onDismiss()
                        }
                    } else {
                        dismissAfterError = false
                        errorMessage = lastApiMessage ?: L10n.string("checkout_failed")
                    }
                }
            },
        ) {
            TabRow(selectedTabIndex = tabIndex) {
                AssetCheckoutTarget.entries.forEachIndexed { index, checkoutTarget ->
                    Tab(
                        selected = tabIndex == index,
                        onClick = { tabIndex = index },
                        text = { Text(L10n.string(checkoutTarget.labelKey)) },
                    )
                }
            }

            when (target) {
                AssetCheckoutTarget.User -> SearchablePickerField(
                    label = L10n.string("select_user_short"),
                    items = users.map {
                        PickerItem(
                            it.id,
                            it.decodedName,
                            it.decodedEmail,
                            searchText = userPickerSearchText(it),
                        )
                    },
                    selectedId = selectedUserId.takeIf { it > 0 },
                    onSelected = { selectedUserId = it.id },
                )
                AssetCheckoutTarget.Location -> SearchablePickerField(
                    label = L10n.string("select_location_short"),
                    items = locations.map {
                        PickerItem(it.id, it.decodedName, searchText = locationPickerSearchText(it))
                    },
                    selectedId = selectedLocationId.takeIf { it > 0 },
                    onSelected = { selectedLocationId = it.id },
                )
                AssetCheckoutTarget.Asset -> SearchablePickerField(
                    label = L10n.string("select_asset_short"),
                    items = filteredAssets.map {
                        PickerItem(
                            it.id,
                            it.decodedAssetTag,
                            it.decodedName,
                            searchText = assetPickerSearchText(it),
                        )
                    },
                    selectedId = selectedAssetId.takeIf { it > 0 },
                    onSelected = { selectedAssetId = it.id },
                )
            }

            FormSectionTitle(L10n.string("asset_details"))
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(L10n.string("notes")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
            )
            RowWithSwitch(
                label = L10n.string("expected_checkin"),
                checked = hasExpectedCheckin,
                onCheckedChange = { hasExpectedCheckin = it },
            )
            if (hasExpectedCheckin) {
                OutlinedTextField(
                    value = formatApiDate(expectedCheckinDate),
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(L10n.string("expected_checkin_date")) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showDatePicker = true },
                    singleLine = true,
                )
            }

            AssetMultiPhotoSection(
                pendingImages = pendingImages,
                onPendingImagesChange = { pendingImages = it },
            )
        }
    }

    if (showDatePicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = expectedCheckinDate.time,
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    datePickerState.selectedDateMillis?.let { millis ->
                        expectedCheckinDate = Date(millis)
                    }
                    showDatePicker = false
                }) { Text(L10n.string("ok")) }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) { Text(L10n.string("cancel")) }
            },
        ) {
            DatePicker(state = datePickerState)
        }
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = {
                val shouldDismiss = dismissAfterError
                errorMessage = null
                if (shouldDismiss) onDismiss()
            },
            title = { Text(L10n.string("result")) },
            text = { Text(errorMessage.orEmpty()) },
            confirmButton = {
                TextButton(onClick = {
                    val shouldDismiss = dismissAfterError
                    errorMessage = null
                    if (shouldDismiss) onDismiss()
                }) { Text(L10n.string("ok")) }
            },
        )
    }
}

@Composable
private fun RowWithSwitch(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
