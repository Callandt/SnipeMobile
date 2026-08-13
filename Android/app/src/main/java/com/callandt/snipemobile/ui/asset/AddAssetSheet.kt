package com.callandt.snipemobile.ui.asset

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedButton
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
import com.callandt.snipemobile.data.api.DellQrLink
import com.callandt.snipemobile.data.api.DellTechDirectClient
import com.callandt.snipemobile.data.api.UploadFile
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.CreatableSearchablePickerField
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.management.ManagementEntity
import com.callandt.snipemobile.ui.scanner.QrScannerMode
import com.callandt.snipemobile.ui.scanner.QrScannerScreen
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.net.URI
import java.util.Date

@Composable
fun AddAssetSheet(
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onCreated: (Int?) -> Unit = {},
    prefilledDellUrl: String? = null,
    prefilledSerial: String? = null,
) {
    val models by viewModel.models.collectAsState()
    val statusLabels by viewModel.statusLabels.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val suppliers by viewModel.suppliers.collectAsState()
    val autoFillAssetTag by viewModel.autoFillAssetTag.collectAsState()
    val enableDellQrScan by viewModel.enableDellQrScan.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var name by remember { mutableStateOf("") }
    var assetTag by remember { mutableStateOf("") }
    var serial by remember(prefilledSerial) { mutableStateOf(prefilledSerial.orEmpty()) }
    var notes by remember { mutableStateOf("") }
    var orderNumber by remember { mutableStateOf("") }
    var purchaseCost by remember { mutableStateOf("") }
    var purchaseDateText by remember { mutableStateOf("") }
    var warrantyMonths by remember { mutableStateOf("") }
    var hasPurchaseDate by remember { mutableStateOf(false) }
    var selectedModelId by remember { mutableIntStateOf(0) }
    var selectedStatusId by remember { mutableIntStateOf(0) }
    var selectedLocationId by remember { mutableIntStateOf(0) }
    var selectedCompanyId by remember { mutableIntStateOf(0) }
    var selectedSupplierId by remember { mutableIntStateOf(0) }
    var isSaving by remember { mutableStateOf(false) }
    var isFetchingDell by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showingDellScanner by remember { mutableStateOf(false) }
    var pendingImage by remember { mutableStateOf<PendingAssetImage?>(null) }
    val customFieldValues = remember { mutableStateMapOf<String, String>() }
    var displayedFieldDefs by remember { mutableStateOf<List<com.callandt.snipemobile.data.model.FieldDefinition>>(emptyList()) }

    val nextTag = remember(viewModel) { viewModel.apiClient.nextAvailableAssetTag() }
    val displayTag = if (autoFillAssetTag) {
        assetTag.trim().ifEmpty { nextTag }
    } else {
        assetTag.trim()
    }

    val selectedModelRequiresSerial = remember(models, selectedModelId) {
        models.firstOrNull { it.id == selectedModelId }?.requiresSerial == true
    }

    val canSave = displayTag.isNotEmpty() &&
        selectedModelId > 0 &&
        selectedStatusId > 0 &&
        (!selectedModelRequiresSerial || serial.trim().isNotEmpty())

    suspend fun applyDellTechDirect(serviceTag: String) {
        val clientId = viewModel.dellTechDirectClientId().trim()
        val clientSecret = viewModel.dellTechDirectClientSecret()
        if (clientId.isEmpty() || clientSecret.isEmpty() || serviceTag.isBlank()) return
        isFetchingDell = true
        runCatching {
            DellTechDirectClient.fetchWarrantyInfo(serviceTag, clientId, clientSecret)
        }.onSuccess { info ->
            info.shipDate?.let { ship ->
                hasPurchaseDate = true
                purchaseDateText = formatApiDate(ship)
            }
            info.warrantyMonths?.takeIf { it > 0 }?.let { months ->
                warrantyMonths = months.toString()
            }
        }
        isFetchingDell = false
    }

    suspend fun handleDellUrl(url: URI) {
        if (!DellQrLink.isDellUrl(url)) {
            errorMessage = L10n.string("invalid_dell_qr")
            return
        }
        val tag = DellQrLink.extractServiceTag(url)
        if (tag.isNullOrBlank()) {
            errorMessage = L10n.string("invalid_dell_qr")
            return
        }
        serial = tag
        applyDellTechDirect(tag)
    }

    LaunchedEffect(Unit) {
        if (autoFillAssetTag) assetTag = viewModel.apiClient.nextAvailableAssetTag()
        if (models.isEmpty()) viewModel.apiClient.fetchModels()
        if (statusLabels.isEmpty()) viewModel.apiClient.fetchStatusLabels()
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
        if (companies.isEmpty()) viewModel.apiClient.fetchCompanies()
        if (suppliers.isEmpty()) viewModel.apiClient.fetchSuppliers()
        if (viewModel.apiClient.fieldsets.value == null) viewModel.apiClient.fetchFieldsets()
    }

    LaunchedEffect(prefilledDellUrl) {
        val raw = prefilledDellUrl?.trim().orEmpty()
        if (raw.isNotEmpty()) {
            DellQrLink.parse(raw)?.let { handleDellUrl(it) }
        }
    }

    LaunchedEffect(serial) {
        val tag = serial.trim()
        if (tag.length < 5) return@LaunchedEffect
        val clientId = viewModel.dellTechDirectClientId().trim()
        val clientSecret = viewModel.dellTechDirectClientSecret()
        if (clientId.isEmpty() || clientSecret.isEmpty()) return@LaunchedEffect
        delay(600)
        if (serial.trim() == tag) {
            applyDellTechDirect(tag)
        }
    }

    LaunchedEffect(selectedModelId) {
        if (selectedModelId <= 0) {
            displayedFieldDefs = emptyList()
            customFieldValues.clear()
            return@LaunchedEffect
        }
        if (viewModel.apiClient.fieldsets.value == null) viewModel.apiClient.fetchFieldsets()
        val fromFieldsets = viewModel.apiClient.modelFieldDefinitionsFromFieldsets(selectedModelId)
        displayedFieldDefs = fromFieldsets
        val seeded = fromFieldsets.associate { d ->
            d.name to initialCustomFieldValue(customFieldValues[d.name], d.defaultValue)
        }
        customFieldValues.clear()
        customFieldValues.putAll(seeded)

        val fromApi = viewModel.apiClient.fetchModelFieldDefinitions(selectedModelId)
        if (fromApi.isNotEmpty()) {
            displayedFieldDefs = fromApi
            val reseeded = fromApi.associate { d ->
                d.name to initialCustomFieldValue(customFieldValues[d.name], d.defaultValue)
            }
            customFieldValues.clear()
            customFieldValues.putAll(reseeded)
        }
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("new_asset"),
            saveLabel = L10n.string("create"),
            isSaving = isSaving,
            canSave = canSave,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    val body = mutableMapOf<String, Any?>(
                        "name" to name.trim(),
                        "asset_tag" to displayTag,
                        "model_id" to selectedModelId,
                        "status_id" to selectedStatusId,
                    )
                    serial.trim().takeIf { it.isNotEmpty() }?.let { body["serial"] = it }
                    notes.trim().takeIf { it.isNotEmpty() }?.let { body["notes"] = it }
                    orderNumber.trim().takeIf { it.isNotEmpty() }?.let { body["order_number"] = it }
                    normalizeDecimalForApi(purchaseCost)?.let { body["purchase_cost"] = it }
                    if (hasPurchaseDate) {
                        parseApiDate(purchaseDateText)?.let { body["purchase_date"] = formatApiDate(it) }
                    }
                    warrantyMonths.filter { it.isDigit() }.takeIf { it.isNotEmpty() }?.let {
                        body["warranty_months"] = it
                    }
                    if (selectedLocationId > 0) body["location_id"] = selectedLocationId
                    if (selectedCompanyId > 0) body["company_id"] = selectedCompanyId
                    if (selectedSupplierId > 0) body["supplier_id"] = selectedSupplierId
                    customFieldValues.forEach { (key, rawValue) ->
                        val trimmed = rawValue.trim()
                        if (trimmed.isNotEmpty()) {
                            val apiKey = resolveCustomFieldApiKey(key, null, displayedFieldDefs)
                            body[apiKey] = trimmed
                        }
                    }

                    val imageUpload = pendingImage?.let { UploadFile("asset.jpg", it.mimeType, it.bytes) }
                    val result = viewModel.apiClient.createAsset(body, imageUpload)
                    isSaving = false
                    if (result.success) {
                        viewModel.syncInBackground()
                        onCreated(result.id)
                        onDismiss()
                    } else {
                        errorMessage = result.message ?: lastApiMessage ?: L10n.string("create_failed")
                    }
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
            if (autoFillAssetTag) {
                OutlinedTextField(
                    value = displayTag,
                    onValueChange = {},
                    readOnly = true,
                    enabled = false,
                    label = { Text(L10n.fieldLabel("asset_tag", required = true)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
            } else {
                OutlinedTextField(
                    value = assetTag,
                    onValueChange = { assetTag = it },
                    label = { Text(L10n.fieldLabel("asset_tag", required = true)) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
            }
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
            if (enableDellQrScan) {
                OutlinedButton(
                    onClick = { showingDellScanner = true },
                    enabled = !isFetchingDell,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(L10n.string("scan_dell_qr"))
                }
            }
            CreatableSearchablePickerField(
                label = L10n.fieldLabel("model", required = true),
                items = models.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedModelId.takeIf { it > 0 },
                viewModel = viewModel,
                placeholder = L10n.string("choose_model"),
                creatableEntity = ManagementEntity.Models,
                onSelected = { selectedModelId = it.id },
            )
            CreatableSearchablePickerField(
                label = L10n.fieldLabel("status", required = true),
                items = statusLabels.map { PickerItem(it.id, statusDisplayName(it)) },
                selectedId = selectedStatusId.takeIf { it > 0 },
                viewModel = viewModel,
                placeholder = L10n.string("choose_status"),
                creatableEntity = ManagementEntity.StatusLabels,
                onSelected = { selectedStatusId = it.id },
            )
            CreatableSearchablePickerField(
                label = L10n.string("default_location"),
                items = locations.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedLocationId.takeIf { it > 0 },
                viewModel = viewModel,
                placeholder = L10n.string("choose_location"),
                creatableLocation = true,
                onSelected = { selectedLocationId = it.id },
            )
            CreatableSearchablePickerField(
                label = L10n.string("company"),
                items = companies.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedCompanyId.takeIf { it > 0 },
                viewModel = viewModel,
                placeholder = L10n.string("choose_company"),
                creatableEntity = ManagementEntity.Companies,
                onSelected = { selectedCompanyId = it.id },
            )
            CreatableSearchablePickerField(
                label = L10n.string("supplier"),
                items = suppliers.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedSupplierId.takeIf { it > 0 },
                viewModel = viewModel,
                placeholder = L10n.string("choose_supplier"),
                creatableEntity = ManagementEntity.Suppliers,
                onSelected = { selectedSupplierId = it.id },
            )

            FormSectionTitle(L10n.string("purchase_warranty"))
            OutlinedTextField(
                value = orderNumber,
                onValueChange = { orderNumber = it },
                label = { Text(L10n.string("order_number")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = purchaseCost,
                onValueChange = { purchaseCost = it },
                label = { Text(L10n.string("purchase_cost")) },
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
                    placeholder = { Text(formatApiDate(Date())) },
                )
            }
            OutlinedTextField(
                value = warrantyMonths,
                onValueChange = { warrantyMonths = it },
                label = { Text(L10n.string("warranty_months")) },
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
                minLines = 3,
            )

            CustomFieldsFormSection(
                fieldDefs = displayedFieldDefs,
                values = customFieldValues,
                onValueChange = { key, value -> customFieldValues[key] = value },
                showEmptyState = false,
            )
        }
    }

    if (showingDellScanner) {
        QrScannerScreen(
            mode = QrScannerMode.Dell,
            onBack = { showingDellScanner = false },
            onLinkParsed = {},
            onDellUrlScanned = { url ->
                showingDellScanner = false
                scope.launch { handleDellUrl(url) }
            },
            onError = { message ->
                showingDellScanner = false
                errorMessage = message
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
