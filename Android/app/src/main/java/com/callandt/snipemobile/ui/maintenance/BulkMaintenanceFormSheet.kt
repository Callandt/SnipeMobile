package com.callandt.snipemobile.ui.maintenance

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
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.api.UploadFile
import com.callandt.snipemobile.data.model.MaintenanceTypesMode
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.asset.AssetMultiSelectScreen
import com.callandt.snipemobile.ui.asset.AssetPhotoSection
import com.callandt.snipemobile.ui.asset.BulkAssetScannerScreen
import com.callandt.snipemobile.ui.asset.FormDateField
import com.callandt.snipemobile.ui.asset.FormSectionTitle
import com.callandt.snipemobile.ui.asset.PendingAssetImage
import com.callandt.snipemobile.ui.asset.formatApiDate
import com.callandt.snipemobile.ui.asset.normalizeDecimalForApi
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.components.StringPickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.usersForNamePicker
import kotlinx.coroutines.launch
import java.util.Date

/** Bulk maintenance for multiple assets. */
@Composable
fun BulkMaintenanceFormSheet(
    viewModel: AppViewModel,
    preselectedAssetIds: Set<Int> = emptySet(),
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    val assets by viewModel.assets.collectAsState()
    val users by viewModel.users.collectAsState()
    val currentUser by viewModel.currentUser.collectAsState()
    val suppliers by viewModel.suppliers.collectAsState()
    val maintenanceTypes by viewModel.apiClient.maintenanceTypes.collectAsState()
    val typesMode by viewModel.apiClient.maintenanceTypesMode.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()
    val pickerUsers = remember(users, currentUser) { usersForNamePicker(users, currentUser) }

    var selectedAssetIds by remember { mutableStateOf(preselectedAssetIds) }
    var showAssetPicker by remember { mutableStateOf(false) }
    var showScanner by remember { mutableStateOf(false) }

    var maintenanceTitle by remember { mutableStateOf("") }
    var selectedLegacyType by remember { mutableStateOf(legacyMaintenanceTypes.first()) }
    var selectedTypeId by remember { mutableIntStateOf(0) }
    var selectedUserId by remember { mutableIntStateOf(0) }
    var selectedSupplierId by remember { mutableIntStateOf(0) }
    var cost by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var notes by remember { mutableStateOf("") }
    var isWarranty by remember { mutableStateOf(false) }
    var startDateText by remember { mutableStateOf(formatApiDate(Date())) }
    var hasCompletionDate by remember { mutableStateOf(false) }
    var completionDateText by remember { mutableStateOf(formatApiDate(Date())) }
    var pendingImage by remember { mutableStateOf<PendingAssetImage?>(null) }

    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val usesTypeIds = typesMode == MaintenanceTypesMode.TypeIds
    val legacyOptions = remember(selectedLegacyType) {
        buildLegacyTypeOptions(selectedLegacyType, null)
    }

    val selectedAssets = remember(assets, selectedAssetIds) {
        assets.filter { selectedAssetIds.contains(it.id) }
            .sortedBy { it.decodedAssetTag.lowercase() }
    }

    LaunchedEffect(Unit) {
        if (suppliers.isEmpty()) viewModel.apiClient.fetchSuppliers()
        if (users.isEmpty()) viewModel.apiClient.fetchUsers()
        viewModel.apiClient.fetchMaintenanceTypes()
    }

    LaunchedEffect(maintenanceTypes, typesMode) {
        if (usesTypeIds && maintenanceTypes.isNotEmpty()) {
            applyTypeIdSelection(selectedTypeId = { selectedTypeId = it }, types = maintenanceTypes, record = null)
        } else if (!usesTypeIds) {
            normalizeLegacyTypeSelection(selectedLegacyType) { selectedLegacyType = it }
        }
    }

    val typeIsValid = when (typesMode) {
        MaintenanceTypesMode.TypeIds -> maintenanceTypes.isNotEmpty() && selectedTypeId > 0
        MaintenanceTypesMode.Legacy -> selectedLegacyType.trim().isNotEmpty()
        MaintenanceTypesMode.Unknown -> false
    }
    val canSave = maintenanceTitle.trim().isNotEmpty() &&
        typeIsValid &&
        selectedAssetIds.isNotEmpty() &&
        !isSaving

    fun buildSharedBody(): Map<String, Any?>? {
        val typeFields = resolveTypeFields(
            mode = typesMode,
            types = maintenanceTypes,
            selectedTypeId = selectedTypeId,
            selectedLegacyType = selectedLegacyType,
        ) ?: return null

        val body = mutableMapOf<String, Any?>(
            "name" to maintenanceTitle.trim(),
            "start_date" to startDateText.trim().take(10),
            "is_warranty" to isWarranty,
        )
        typeFields.first?.let { body["maintenance_type_id"] = it }
        typeFields.second?.let { body["asset_maintenance_type"] = it }
        normalizeDecimalForApi(cost)?.let { body["cost"] = it }
        notes.trim().takeIf { it.isNotEmpty() }?.let { body["notes"] = it }
        url.trim().takeIf { it.isNotEmpty() }?.let { body["url"] = it }
        if (selectedSupplierId > 0) body["supplier_id"] = selectedSupplierId
        if (selectedUserId > 0) body["responsible_party_id"] = selectedUserId
        if (hasCompletionDate) {
            body["completion_date"] = completionDateText.trim().take(10)
        }
        return body
    }

    suspend fun save() {
        isSaving = true
        viewModel.apiClient.fetchMaintenanceTypes()
        val sharedBody = buildSharedBody()
        if (sharedBody == null) {
            errorMessage = lastApiMessage ?: L10n.string("error")
            isSaving = false
            return
        }

        val imageUpload = pendingImage?.let { UploadFile("maintenance.jpg", it.mimeType, it.bytes) }
        var failedCount = 0
        var lastError: String? = null
        for (assetId in selectedAssetIds) {
            val body = sharedBody.toMutableMap()
            body["asset_id"] = assetId
            val ok = viewModel.apiClient.createMaintenance(body, imageUpload)
            if (!ok) {
                failedCount += 1
                lastError = viewModel.lastApiMessage.value
            }
        }

        isSaving = false
        if (failedCount == 0) {
            viewModel.syncInBackground()
            onSaved()
            onDismiss()
        } else {
            val base = L10n.string("bulk_maintenance_failed", failedCount)
            errorMessage = lastError?.let { "$base\n$it" } ?: base
        }
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("add_maintenance"),
            saveLabel = L10n.string("save"),
            isSaving = isSaving,
            canSave = canSave,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = { scope.launch { save() } },
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
            TextButton(onClick = { showScanner = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.QrCodeScanner, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("scan_assets"))
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

            FormSectionTitle(L10n.string("general"))
            OutlinedTextField(
                value = maintenanceTitle,
                onValueChange = { maintenanceTitle = it },
                label = { Text(L10n.fieldLabel("name", required = true)) },
                modifier = Modifier.fillMaxWidth(),
            )
            when (typesMode) {
                MaintenanceTypesMode.Unknown -> Text(L10n.string("loading"), modifier = Modifier.fillMaxWidth())
                MaintenanceTypesMode.TypeIds -> {
                    if (maintenanceTypes.isNotEmpty() && maintenanceTypes.any { it.id == selectedTypeId }) {
                        SearchablePickerField(
                            label = L10n.fieldLabel("maintenance_type", required = true),
                            items = maintenanceTypes.map { PickerItem(it.id, it.decodedName) },
                            selectedId = selectedTypeId.takeIf { it > 0 },
                            onSelected = { selectedTypeId = it.id },
                        )
                    } else {
                        Text(L10n.string("loading"), modifier = Modifier.fillMaxWidth())
                    }
                }
                MaintenanceTypesMode.Legacy -> {
                    StringPickerField(
                        label = L10n.fieldLabel("maintenance_type", required = true),
                        options = legacyOptions.map { it to it },
                        selectedValue = selectedLegacyType,
                        onSelected = { selectedLegacyType = it },
                    )
                }
            }

            FormSectionTitle(L10n.string("responsible_party"))
            if (users.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("responsible_party"),
                    items = pickerUsers.map { PickerItem(it.id, it.decodedName, it.decodedEmail) },
                    selectedId = selectedUserId.takeIf { it > 0 },
                    placeholder = L10n.string("none"),
                    allowClear = selectedUserId > 0,
                    onClear = { selectedUserId = 0 },
                    onSelected = { selectedUserId = it.id },
                )
            } else {
                Text(L10n.string("loading"), modifier = Modifier.fillMaxWidth())
            }

            FormSectionTitle(L10n.string("dates"))
            FormDateField(
                label = L10n.string("start_date"),
                dateText = startDateText,
                onDateTextChange = { startDateText = it },
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("set_completion_date"), modifier = Modifier.weight(1f))
                Switch(checked = hasCompletionDate, onCheckedChange = { hasCompletionDate = it })
            }
            if (hasCompletionDate) {
                FormDateField(
                    label = L10n.string("completion_date"),
                    dateText = completionDateText,
                    onDateTextChange = { completionDateText = it },
                )
            }

            FormSectionTitle(L10n.string("financial"))
            OutlinedTextField(
                value = cost,
                onValueChange = { cost = it },
                label = { Text(L10n.string("cost")) },
                modifier = Modifier.fillMaxWidth(),
            )
            if (suppliers.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("supplier_optional"),
                    items = suppliers.map { PickerItem(it.id, it.decodedName) },
                    selectedId = selectedSupplierId.takeIf { it > 0 },
                    placeholder = L10n.string("none"),
                    allowClear = selectedSupplierId > 0,
                    onClear = { selectedSupplierId = 0 },
                    onSelected = { selectedSupplierId = it.id },
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("is_warranty"), modifier = Modifier.weight(1f))
                Switch(checked = isWarranty, onCheckedChange = { isWarranty = it })
            }

            FormSectionTitle(L10n.string("url"))
            OutlinedTextField(
                value = url,
                onValueChange = { url = it },
                label = { Text(L10n.string("url")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            AssetPhotoSection(
                pendingImage = pendingImage,
                onPendingImageChange = { pendingImage = it },
            )

            FormSectionTitle(L10n.string("notes"))
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(L10n.string("notes")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 4,
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

    if (showScanner) {
        AssetFullScreenSheet(onDismiss = { showScanner = false }) {
            BulkAssetScannerScreen(
                viewModel = viewModel,
                onAssetResolved = { asset -> selectedAssetIds = selectedAssetIds + asset.id },
                onDone = { showScanner = false },
            )
        }
    }

    errorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(L10n.string("error")) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text(L10n.string("ok")) }
            },
        )
    }
}
