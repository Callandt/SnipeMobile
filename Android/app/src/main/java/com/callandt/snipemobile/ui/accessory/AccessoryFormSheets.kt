package com.callandt.snipemobile.ui.accessory

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.asset.FormSectionTitle
import com.callandt.snipemobile.ui.asset.formatApiDate
import com.callandt.snipemobile.ui.asset.normalizeDecimalForApi
import com.callandt.snipemobile.ui.asset.parseApiDate
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@Composable
fun AddAccessorySheet(
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onCreated: () -> Unit = {},
) {
    AccessoryFormSheet(
        viewModel = viewModel,
        title = L10n.string("new_accessory"),
        saveLabel = L10n.string("create"),
        existing = null,
        onDismiss = onDismiss,
        onSaved = onCreated,
    )
}

@Composable
fun EditAccessorySheet(
    accessory: Accessory,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    AccessoryFormSheet(
        viewModel = viewModel,
        title = L10n.string("edit_accessory"),
        saveLabel = L10n.string("save"),
        existing = accessory,
        onDismiss = onDismiss,
        onSaved = onSaved,
    )
}

@Composable
private fun AccessoryFormSheet(
    viewModel: AppViewModel,
    title: String,
    saveLabel: String,
    existing: Accessory?,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    val categories by viewModel.categories.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val manufacturers by viewModel.manufacturers.collectAsState()
    val suppliers by viewModel.suppliers.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var name by remember(existing?.id) { mutableStateOf(existing?.decodedName.orEmpty()) }
    var qtyText by remember(existing?.id) { mutableStateOf((existing?.qty ?: 1).toString()) }
    var minAmtText by remember(existing?.id) { mutableStateOf(existing?.minAmt?.toString().orEmpty()) }
    var modelNumber by remember(existing?.id) { mutableStateOf(existing?.modelNumber.orEmpty()) }
    var orderNumber by remember(existing?.id) { mutableStateOf(existing?.orderNumber.orEmpty()) }
    var purchaseCost by remember(existing?.id) { mutableStateOf(existing?.purchaseCost.orEmpty()) }
    var purchaseDateText by remember(existing?.id) {
        mutableStateOf(existing?.purchaseDate?.take(10).orEmpty())
    }
    var hasPurchaseDate by remember(existing?.id) {
        mutableStateOf(!existing?.purchaseDate.isNullOrBlank())
    }
    var notes by remember(existing?.id) { mutableStateOf(existing?.decodedNotes.orEmpty()) }
    var selectedCategoryId by remember(existing?.id) { mutableIntStateOf(existing?.category?.id ?: 0) }
    var selectedLocationId by remember(existing?.id) { mutableIntStateOf(existing?.location?.id ?: 0) }
    var selectedCompanyId by remember(existing?.id) { mutableIntStateOf(existing?.company?.id ?: 0) }
    var selectedManufacturerId by remember(existing?.id) { mutableIntStateOf(existing?.manufacturer?.id ?: 0) }
    var selectedSupplierId by remember(existing?.id) { mutableIntStateOf(existing?.supplier?.id ?: 0) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val accessoryCategories = remember(categories) { viewModel.apiClient.categoriesFor("accessory") }
    val categoryItems = remember(accessoryCategories) {
        accessoryCategories.map { PickerItem(it.id, it.decodedName) }
    }

    val canSave = name.trim().isNotEmpty() && selectedCategoryId > 0

    LaunchedEffect(Unit) {
        if (categories.isEmpty()) viewModel.apiClient.fetchCategories()
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
        if (companies.isEmpty()) viewModel.apiClient.fetchCompanies()
        if (manufacturers.isEmpty()) viewModel.apiClient.fetchManufacturers()
        if (suppliers.isEmpty()) viewModel.apiClient.fetchSuppliers()
    }

    fun buildBody(): Map<String, Any?> {
        val qty = maxOf(1, qtyText.trim().toIntOrNull() ?: 1)
        val minAmt = minAmtText.trim().toIntOrNull() ?: 0
        val body = mutableMapOf<String, Any?>(
            "name" to name.trim(),
            "category_id" to selectedCategoryId,
            "qty" to qty,
        )
        if (minAmt > 0) body["min_amt"] = minAmt
        modelNumber.trim().takeIf { it.isNotEmpty() }?.let { body["model_number"] = it }
        orderNumber.trim().takeIf { it.isNotEmpty() }?.let { body["order_number"] = it }
        normalizeDecimalForApi(purchaseCost)?.let { body["purchase_cost"] = it }
        if (hasPurchaseDate) {
            parseApiDate(purchaseDateText)?.let { body["purchase_date"] = formatApiDate(it) }
        }
        body["notes"] = notes.trim()
        if (selectedLocationId > 0) body["location_id"] = selectedLocationId
        if (selectedCompanyId > 0) body["company_id"] = selectedCompanyId
        if (selectedManufacturerId > 0) body["manufacturer_id"] = selectedManufacturerId
        if (selectedSupplierId > 0) body["supplier_id"] = selectedSupplierId
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
                    val body = buildBody()
                    val success = if (existing == null) {
                        val result = viewModel.apiClient.createAccessory(body)
                        if (!result.success) {
                            errorMessage = result.message ?: lastApiMessage ?: L10n.string("create_failed")
                        }
                        result.success
                    } else {
                        val ok = viewModel.apiClient.updateAccessory(existing.id, body)
                        if (!ok) errorMessage = lastApiMessage ?: L10n.string("mgmt_save_failed")
                        ok
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
            FormSectionTitle(L10n.string("general"))
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(L10n.fieldLabel("name", required = true)) },
                modifier = Modifier.fillMaxWidth(),
            )
            SearchablePickerField(
                label = L10n.fieldLabel("category", required = true),
                items = categoryItems,
                selectedId = selectedCategoryId.takeIf { it > 0 },
                onSelected = { selectedCategoryId = it.id },
            )
            OutlinedTextField(
                value = qtyText,
                onValueChange = { qtyText = it.filter { ch -> ch.isDigit() } },
                label = { Text(L10n.fieldLabel("quantity", required = true)) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = minAmtText,
                onValueChange = { minAmtText = it.filter { ch -> ch.isDigit() } },
                label = { Text(L10n.string("minimum_amount")) },
                modifier = Modifier.fillMaxWidth(),
            )
            SearchablePickerField(
                label = L10n.string("location"),
                items = locations.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedLocationId.takeIf { it > 0 },
                onSelected = { selectedLocationId = it.id },
            )
            SearchablePickerField(
                label = L10n.string("company"),
                items = companies.map { PickerItem(it.id, it.name) },
                selectedId = selectedCompanyId.takeIf { it > 0 },
                onSelected = { selectedCompanyId = it.id },
            )
            SearchablePickerField(
                label = L10n.string("manufacturer"),
                items = manufacturers.map { PickerItem(it.id, it.name) },
                selectedId = selectedManufacturerId.takeIf { it > 0 },
                onSelected = { selectedManufacturerId = it.id },
            )
            SearchablePickerField(
                label = L10n.string("supplier"),
                items = suppliers.map { PickerItem(it.id, it.name) },
                selectedId = selectedSupplierId.takeIf { it > 0 },
                onSelected = { selectedSupplierId = it.id },
            )
            OutlinedTextField(
                value = modelNumber,
                onValueChange = { modelNumber = it },
                label = { Text(L10n.string("model_number")) },
                modifier = Modifier.fillMaxWidth(),
            )

            FormSectionTitle(L10n.string("purchase_only"))
            OutlinedTextField(
                value = orderNumber,
                onValueChange = { orderNumber = it },
                label = { Text(L10n.string("order_number")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = purchaseCost,
                onValueChange = { purchaseCost = it },
                label = { Text(L10n.string("purchase_price")) },
                modifier = Modifier.fillMaxWidth(),
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
                )
            }

            FormSectionTitle(L10n.string("notes"))
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(L10n.string("notes")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
            )

            errorMessage?.let { Text(it, color = androidx.compose.material3.MaterialTheme.colorScheme.error) }
        }
    }
}
