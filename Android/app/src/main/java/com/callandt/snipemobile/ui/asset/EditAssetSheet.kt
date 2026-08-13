package com.callandt.snipemobile.ui.asset

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.api.UploadFile
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.FieldDefinition
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.resolveSnipeImageUrl
import kotlinx.coroutines.launch

@Composable
fun EditAssetSheet(
    asset: Asset,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    val models by viewModel.models.collectAsState()
    val statusLabels by viewModel.statusLabels.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val suppliers by viewModel.suppliers.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var name by remember(asset.id) { mutableStateOf(asset.decodedName) }
    var assetTag by remember(asset.id) { mutableStateOf(asset.decodedAssetTag) }
    var serial by remember(asset.id) { mutableStateOf(asset.decodedSerial) }
    var notes by remember(asset.id) { mutableStateOf(asset.decodedNotes) }
    var orderNumber by remember(asset.id) { mutableStateOf(asset.orderNumber.orEmpty()) }
    var purchaseCost by remember(asset.id) { mutableStateOf(asset.purchaseCost.orEmpty()) }
    var warrantyMonths by remember(asset.id) { mutableStateOf(asset.decodedWarrantyMonths) }
    var purchaseDateText by remember(asset.id) {
        mutableStateOf(asset.purchaseDate?.date?.trim()?.take(10).orEmpty())
    }
    var eolDateText by remember(asset.id) {
        mutableStateOf(asset.assetEolDate?.date?.trim()?.take(10).orEmpty())
    }
    var nextAuditDateText by remember(asset.id) {
        mutableStateOf(asset.nextAuditDate?.date?.trim()?.take(10).orEmpty())
    }
    var hasPurchaseDate by remember(asset.id) { mutableStateOf(purchaseDateText.isNotEmpty()) }
    var hasEolDate by remember(asset.id) { mutableStateOf(eolDateText.isNotEmpty()) }
    var hasNextAuditDate by remember(asset.id) { mutableStateOf(nextAuditDateText.isNotEmpty()) }
    var selectedStatusId by remember(asset.id) { mutableIntStateOf(asset.statusLabel.id) }
    var selectedLocationId by remember(asset.id) {
        mutableIntStateOf(asset.rtdLocation?.id ?: asset.location?.id ?: 0)
    }
    var selectedCompanyId by remember(asset.id) { mutableIntStateOf(asset.company?.id ?: 0) }
    var selectedSupplierId by remember(asset.id) { mutableIntStateOf(asset.supplier?.id ?: 0) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showCheckinWarning by remember { mutableStateOf(false) }
    var pendingImage by remember(asset.id) { mutableStateOf<PendingAssetImage?>(null) }
    var removeExistingImage by remember(asset.id) { mutableStateOf(false) }
    val existingImageUrl = remember(asset.id, asset.image, viewModel.apiClient.baseUrl) {
        resolveSnipeImageUrl(viewModel.apiClient.baseUrl, asset.image)
    }
    val customFieldValues = remember(asset.id) {
        mutableStateMapOf<String, String>().apply {
            asset.customFields?.forEach { (key, field) -> put(key, field.decodedValue) }
        }
    }
    var displayedFieldDefs by remember(asset.id) { mutableStateOf<List<FieldDefinition>>(emptyList()) }

    val modelName = asset.decodedModelName.ifEmpty {
        models.firstOrNull { it.id == asset.model?.id }?.decodedName.orEmpty()
    }
    val selectedModelRequiresSerial = remember(models, asset.model?.id) {
        models.firstOrNull { it.id == asset.model?.id }?.requiresSerial == true
    }
    val serialSatisfied = !selectedModelRequiresSerial || serial.trim().isNotEmpty()
    val isAssigned = asset.assignedTo != null
    val selectedStatusChecksInAsset = remember(statusLabels, selectedStatusId, isAssigned) {
        if (!isAssigned) return@remember false
        val label = statusLabels.firstOrNull { it.id == selectedStatusId } ?: return@remember false
        !isDeployableStatus(label)
    }

    LaunchedEffect(Unit) {
        if (models.isEmpty()) viewModel.apiClient.fetchModels()
        if (statusLabels.isEmpty()) viewModel.apiClient.fetchStatusLabels()
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
        if (companies.isEmpty()) viewModel.apiClient.fetchCompanies()
        if (suppliers.isEmpty()) viewModel.apiClient.fetchSuppliers()
    }

    LaunchedEffect(asset.id, asset.model?.id) {
        val modelId = asset.model?.id ?: return@LaunchedEffect
        if (viewModel.apiClient.fieldsets.value == null) viewModel.apiClient.fetchFieldsets()
        val fromFieldsets = viewModel.apiClient.modelFieldDefinitionsFromFieldsets(modelId)
        if (fromFieldsets.isNotEmpty()) {
            displayedFieldDefs = fromFieldsets
            fromFieldsets.forEach { d ->
                customFieldValues[d.name] = initialCustomFieldValue(customFieldValues[d.name], d.defaultValue)
            }
        }
        val fromApi = viewModel.apiClient.fetchModelFieldDefinitions(modelId)
        if (fromApi.isNotEmpty()) {
            displayedFieldDefs = fromApi
            fromApi.forEach { d ->
                customFieldValues[d.name] = initialCustomFieldValue(customFieldValues[d.name], d.defaultValue)
            }
        }
    }

    fun performSave() {
        isSaving = true
        scope.launch {
            val body = mutableMapOf<String, Any?>(
                "name" to name.trim(),
                "asset_tag" to assetTag.trim(),
                "notes" to notes.trim(),
                "order_number" to orderNumber.trim(),
            )
            if (serial.trim().isNotEmpty()) {
                body["serial"] = serial.trim()
            } else if (asset.decodedSerial.isNotBlank()) {
                body["serial"] = null
            }
            if (selectedStatusId > 0) body["status_id"] = selectedStatusId
            body["rtd_location_id"] = selectedLocationId.takeIf { it > 0 }
            if (selectedCompanyId > 0) body["company_id"] = selectedCompanyId else body["company_id"] = null
            if (selectedSupplierId > 0) body["supplier_id"] = selectedSupplierId else body["supplier_id"] = null
            normalizeDecimalForApi(purchaseCost)?.let { body["purchase_cost"] = it }
                ?: run { body["purchase_cost"] = null }
            body["purchase_date"] = if (hasPurchaseDate) {
                parseApiDate(purchaseDateText)?.let { formatApiDate(it) }
            } else {
                null
            }
            body["eol_date"] = if (hasEolDate) {
                parseApiDate(eolDateText)?.let { formatApiDate(it) }
            } else {
                null
            }
            body["next_audit_date"] = if (hasNextAuditDate) {
                parseApiDate(nextAuditDateText)?.let { formatApiDate(it) }
            } else {
                null
            }
            val digitsOnly = warrantyMonths.filter { it.isDigit() }
            body["warranty_months"] = digitsOnly.takeIf { it.isNotEmpty() }
            if (pendingImage == null && removeExistingImage) {
                body["image_delete"] = 1
            }
            customFieldValues.forEach { (key, rawValue) ->
                val trimmed = rawValue.trim()
                if (trimmed.isNotEmpty()) {
                    val apiKey = resolveCustomFieldApiKey(key, asset.customFields, displayedFieldDefs)
                    body[apiKey] = trimmed
                }
            }

            val imageUpload = pendingImage?.let { UploadFile("asset.jpg", it.mimeType, it.bytes) }
            val success = viewModel.apiClient.updateAsset(asset.id, body, imageUpload)
            isSaving = false
            if (success) {
                viewModel.syncInBackground()
                onSaved()
                onDismiss()
            } else {
                errorMessage = lastApiMessage ?: L10n.string("mgmt_save_failed")
            }
        }
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("edit_asset"),
            saveLabel = L10n.string("save"),
            isSaving = isSaving,
            canSave = serialSatisfied,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                if (selectedStatusChecksInAsset) {
                    showCheckinWarning = true
                } else {
                    performSave()
                }
            },
        ) {
            FormSectionTitle(L10n.string("general"))
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(L10n.string("name")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = assetTag,
                onValueChange = { assetTag = it },
                label = { Text(L10n.string("asset_tag")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = serial,
                onValueChange = { serial = it },
                label = {
                    Text(
                        if (selectedModelRequiresSerial) {
                            L10n.string("serial_required")
                        } else {
                            L10n.string("serial_number")
                        },
                    )
                },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            if (modelName.isNotEmpty()) {
                OutlinedTextField(
                    value = modelName,
                    onValueChange = {},
                    readOnly = true,
                    enabled = false,
                    label = { Text(L10n.string("model")) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
            }
            if (statusLabels.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("status"),
                    items = statusLabels.map { PickerItem(it.id, statusDisplayName(it)) },
                    selectedId = selectedStatusId,
                    onSelected = { selectedStatusId = it.id },
                )
            }
            SearchablePickerField(
                label = L10n.string("default_location"),
                items = locations.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedLocationId.takeIf { it > 0 },
                placeholder = L10n.string("choose_location"),
                onSelected = { selectedLocationId = it.id },
            )
            if (companies.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("company"),
                    items = companies.map { PickerItem(it.id, it.decodedName) },
                    selectedId = selectedCompanyId.takeIf { it > 0 },
                    placeholder = L10n.string("mgmt_none"),
                    onSelected = { selectedCompanyId = it.id },
                )
            }
            if (suppliers.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("supplier"),
                    items = suppliers.map { PickerItem(it.id, it.decodedName) },
                    selectedId = selectedSupplierId.takeIf { it > 0 },
                    placeholder = L10n.string("mgmt_none"),
                    onSelected = { selectedSupplierId = it.id },
                )
            }

            FormSectionTitle(L10n.string("financial"))
            OutlinedTextField(
                value = purchaseCost,
                onValueChange = { purchaseCost = it },
                label = { Text(L10n.string("purchase_cost")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = orderNumber,
                onValueChange = { orderNumber = it },
                label = { Text(L10n.string("order_number")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = warrantyMonths,
                onValueChange = { warrantyMonths = it },
                label = { Text(L10n.string("warranty_months")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("purchase_date"), modifier = Modifier.weight(1f))
                Switch(checked = hasPurchaseDate, onCheckedChange = { hasPurchaseDate = it })
            }
            if (hasPurchaseDate) {
                OutlinedTextField(
                    value = purchaseDateText,
                    onValueChange = { purchaseDateText = it },
                    label = { Text(L10n.string("set_purchase_date")) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("eol_date"), modifier = Modifier.weight(1f))
                Switch(checked = hasEolDate, onCheckedChange = { hasEolDate = it })
            }
            if (hasEolDate) {
                OutlinedTextField(
                    value = eolDateText,
                    onValueChange = { eolDateText = it },
                    label = { Text(L10n.string("set_eol_date")) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("next_audit_date"), modifier = Modifier.weight(1f))
                Switch(checked = hasNextAuditDate, onCheckedChange = { hasNextAuditDate = it })
            }
            if (hasNextAuditDate) {
                OutlinedTextField(
                    value = nextAuditDateText,
                    onValueChange = { nextAuditDateText = it },
                    label = { Text(L10n.string("set_next_audit")) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
            }

            AssetPhotoSection(
                pendingImage = pendingImage,
                onPendingImageChange = { pendingImage = it },
                existingImageUrl = existingImageUrl,
                removeExistingImage = removeExistingImage,
                onRemoveExistingImageChange = { removeExistingImage = it },
            )

            FormSectionTitle(L10n.string("notes"))
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(L10n.string("notes")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 4,
            )

            CustomFieldsFormSection(
                fieldDefs = displayedFieldDefs,
                values = customFieldValues,
                onValueChange = { key, value -> customFieldValues[key] = value },
            )
        }
    }

    if (showCheckinWarning) {
        AlertDialog(
            onDismissRequest = { showCheckinWarning = false },
            title = { Text(L10n.string("status_not_deployable_title")) },
            text = { Text(L10n.string("status_not_deployable_checkin_warning")) },
            confirmButton = {
                TextButton(onClick = {
                    showCheckinWarning = false
                    performSave()
                }) { Text(L10n.string("continue")) }
            },
            dismissButton = {
                TextButton(onClick = { showCheckinWarning = false }) { Text(L10n.string("cancel")) }
            },
        )
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(L10n.string("error")) },
            text = { Text(errorMessage.orEmpty()) },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text(L10n.string("ok")) }
            },
        )
    }
}
