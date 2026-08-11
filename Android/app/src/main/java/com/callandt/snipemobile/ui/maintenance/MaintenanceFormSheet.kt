package com.callandt.snipemobile.ui.maintenance

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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.data.model.MaintenanceTypesMode
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.asset.FormSectionTitle
import com.callandt.snipemobile.ui.asset.formatApiDate
import com.callandt.snipemobile.ui.asset.normalizeDecimalForApi
import com.callandt.snipemobile.ui.asset.parseApiDate
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.components.StringPickerField
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch
import java.util.Date

internal val legacyMaintenanceTypes = listOf(
    "Maintenance",
    "Repair",
    "PAT Test/Electrical",
    "Upgrade",
    "Hardware Support",
    "Software Support",
)

@Composable
fun AddMaintenanceSheet(
    viewModel: AppViewModel,
    initialAssetId: Int? = null,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    MaintenanceFormSheet(
        viewModel = viewModel,
        title = L10n.string("add_maintenance"),
        saveLabel = L10n.string("save"),
        existing = null,
        initialAssetId = initialAssetId,
        onDismiss = onDismiss,
        onSaved = onSaved,
    )
}

@Composable
fun EditMaintenanceSheet(
    record: AssetMaintenance,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    MaintenanceFormSheet(
        viewModel = viewModel,
        title = L10n.string("edit_maintenance"),
        saveLabel = L10n.string("save"),
        existing = record,
        initialAssetId = record.assetId,
        onDismiss = onDismiss,
        onSaved = onSaved,
    )
}

@Composable
private fun MaintenanceFormSheet(
    viewModel: AppViewModel,
    title: String,
    saveLabel: String,
    existing: AssetMaintenance?,
    initialAssetId: Int?,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    val assets by viewModel.assets.collectAsState()
    val suppliers by viewModel.suppliers.collectAsState()
    val maintenanceTypes by viewModel.apiClient.maintenanceTypes.collectAsState()
    val typesMode by viewModel.apiClient.maintenanceTypesMode.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var selectedAssetId by remember(existing?.id) { mutableIntStateOf(initialAssetId ?: 0) }
    var maintenanceTitle by remember(existing?.id) { mutableStateOf(existing?.decodedTitle.orEmpty()) }
    var selectedLegacyType by remember(existing?.id) {
        mutableStateOf(existing?.displayType ?: legacyMaintenanceTypes.first())
    }
    var selectedTypeId by remember(existing?.id) { mutableIntStateOf(0) }
    var selectedSupplierId by remember(existing?.id) { mutableIntStateOf(existing?.supplier?.id ?: 0) }
    var cost by remember(existing?.id) { mutableStateOf(existing?.cost.orEmpty()) }
    var notes by remember(existing?.id) { mutableStateOf(existing?.decodedNotes.orEmpty()) }
    var isWarranty by remember(existing?.id) { mutableStateOf(existing?.isWarranty ?: false) }
    var startDateText by remember(existing?.id) {
        mutableStateOf(existing?.startDate?.date ?: formatApiDate(Date()))
    }
    var hasCompletionDate by remember(existing?.id) {
        mutableStateOf(!existing?.completionDate?.date.isNullOrEmpty())
    }
    var completionDateText by remember(existing?.id) {
        mutableStateOf(existing?.completionDate?.date ?: formatApiDate(Date()))
    }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val isEditing = existing != null
    val usesTypeIds = typesMode == MaintenanceTypesMode.TypeIds
    val legacyOptions = remember(selectedLegacyType, existing?.displayType) {
        buildLegacyTypeOptions(selectedLegacyType, existing?.displayType)
    }

    LaunchedEffect(Unit) {
        if (suppliers.isEmpty()) viewModel.apiClient.fetchSuppliers()
        viewModel.apiClient.fetchMaintenanceTypes()
    }

    LaunchedEffect(maintenanceTypes, typesMode, existing?.id) {
        if (usesTypeIds && maintenanceTypes.isNotEmpty()) {
            applyTypeIdSelection(selectedTypeId = { selectedTypeId = it }, types = maintenanceTypes, record = existing)
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
        selectedAssetId > 0 &&
        !isSaving

    fun buildBody(): Map<String, Any?>? {
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
        if (selectedSupplierId > 0) body["supplier_id"] = selectedSupplierId
        if (hasCompletionDate) {
            body["completion_date"] = completionDateText.trim().take(10)
        } else if (isEditing) {
            body["completion_date"] = null
        }
        if (!isEditing) body["asset_id"] = selectedAssetId
        return body
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = title,
            saveLabel = saveLabel,
            isSaving = isSaving,
            canSave = canSave,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    viewModel.apiClient.fetchMaintenanceTypes()
                    val body = buildBody()
                    if (body == null) {
                        errorMessage = lastApiMessage ?: L10n.string("error")
                        isSaving = false
                        return@launch
                    }
                    val success = if (isEditing) {
                        viewModel.apiClient.updateMaintenance(existing!!.id, body).also { ok ->
                            if (!ok) errorMessage = lastApiMessage ?: L10n.string("mgmt_save_failed")
                        }
                    } else {
                        viewModel.apiClient.createMaintenance(body).also { ok ->
                            if (!ok) errorMessage = lastApiMessage ?: L10n.string("create_failed")
                        }
                    }
                    isSaving = false
                    if (success) {
                        viewModel.syncInBackground()
                        onSaved()
                        onDismiss()
                    }
                }
            },
        ) {
            if (!isEditing) {
                FormSectionTitle(L10n.string("asset"))
                SearchablePickerField(
                    label = L10n.fieldLabel("asset", required = true),
                    items = assets.map { asset ->
                        PickerItem(
                            id = asset.id,
                            title = asset.decodedName,
                            subtitle = asset.decodedAssetTag,
                        )
                    },
                    selectedId = selectedAssetId.takeIf { it > 0 },
                    onSelected = { selectedAssetId = it.id },
                )
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

            FormSectionTitle(L10n.string("dates"))
            OutlinedTextField(
                value = startDateText,
                onValueChange = { startDateText = it },
                label = { Text(L10n.string("start_date")) },
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("set_completion_date"), modifier = Modifier.weight(1f))
                Switch(checked = hasCompletionDate, onCheckedChange = { hasCompletionDate = it })
            }
            if (hasCompletionDate) {
                OutlinedTextField(
                    value = completionDateText,
                    onValueChange = { completionDateText = it },
                    label = { Text(L10n.string("completion_date")) },
                    modifier = Modifier.fillMaxWidth(),
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
                    label = L10n.string("supplier"),
                    items = suppliers.map { PickerItem(it.id, it.decodedName) },
                    selectedId = selectedSupplierId.takeIf { it > 0 },
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

internal fun buildLegacyTypeOptions(selectedType: String, recordType: String?): List<String> {
    val options = legacyMaintenanceTypes.toMutableList()
    listOfNotNull(selectedType, recordType)
        .filter { it.isNotEmpty() && !options.contains(it) }
        .forEach { options.add(it) }
    return options
}

internal fun normalizeLegacyTypeSelection(current: String, onUpdate: (String) -> Unit) {
    val options = buildLegacyTypeOptions(current, null)
    if (!options.contains(current) && options.isNotEmpty()) onUpdate(options.first())
}

internal fun applyTypeIdSelection(
    selectedTypeId: (Int) -> Unit,
    types: List<com.callandt.snipemobile.data.model.MaintenanceType>,
    record: AssetMaintenance?,
) {
    if (types.isEmpty()) return
    record?.let { r ->
        val target = (r.maintenanceType ?: r.assetMaintenanceType)?.lowercase()
        if (!target.isNullOrEmpty()) {
            types.firstOrNull {
                it.name.lowercase() == target || it.decodedName.lowercase() == target
            }?.let {
                selectedTypeId(it.id)
                return
            }
        }
    }
    types.firstOrNull()?.let { selectedTypeId(it.id) }
}

internal fun resolveTypeFields(
    mode: MaintenanceTypesMode,
    types: List<com.callandt.snipemobile.data.model.MaintenanceType>,
    selectedTypeId: Int,
    selectedLegacyType: String,
): Pair<Int?, String?>? {
    return when (mode) {
        MaintenanceTypesMode.TypeIds -> {
            if (selectedTypeId <= 0) null
            else {
                val name = types.firstOrNull { it.id == selectedTypeId }?.name
                selectedTypeId to name
            }
        }
        MaintenanceTypesMode.Legacy -> {
            val trimmed = selectedLegacyType.trim()
            if (trimmed.isEmpty()) null else null to trimmed
        }
        MaintenanceTypesMode.Unknown -> null
    }
}
