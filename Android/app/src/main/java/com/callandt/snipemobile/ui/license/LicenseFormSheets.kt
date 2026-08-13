package com.callandt.snipemobile.ui.license

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
import com.callandt.snipemobile.data.model.License
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
fun AddLicenseSheet(
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onCreated: (Int?) -> Unit = {},
) {
    LicenseFormSheet(
        viewModel = viewModel,
        title = L10n.string("new_license"),
        saveLabel = L10n.string("create"),
        existing = null,
        onDismiss = onDismiss,
        onSaved = onCreated,
    )
}

@Composable
fun EditLicenseSheet(
    license: License,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    LicenseFormSheet(
        viewModel = viewModel,
        title = L10n.string("mgmt_edit_title", L10n.string("category_type_license")),
        saveLabel = L10n.string("save"),
        existing = license,
        onDismiss = onDismiss,
        onSaved = { onSaved() },
    )
}

@Composable
private fun LicenseFormSheet(
    viewModel: AppViewModel,
    title: String,
    saveLabel: String,
    existing: License?,
    onDismiss: () -> Unit,
    onSaved: (Int?) -> Unit,
) {
    val categories by viewModel.categories.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val manufacturers by viewModel.manufacturers.collectAsState()
    val suppliers by viewModel.suppliers.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var name by remember(existing?.id) { mutableStateOf(existing?.decodedName.orEmpty()) }
    var productKey by remember(existing?.id) { mutableStateOf(existing?.decodedProductKey.orEmpty()) }
    var seatsText by remember(existing?.id) { mutableStateOf((existing?.seats ?: 1).toString()) }
    var minAmtText by remember(existing?.id) { mutableStateOf(existing?.minAmt?.toString().orEmpty()) }
    var licensedToName by remember(existing?.id) { mutableStateOf(existing?.decodedLicenseName.orEmpty()) }
    var licensedToEmail by remember(existing?.id) { mutableStateOf(existing?.decodedLicenseEmail.orEmpty()) }
    var orderNumber by remember(existing?.id) { mutableStateOf(existing?.orderNumber.orEmpty()) }
    var purchaseOrder by remember(existing?.id) { mutableStateOf(existing?.purchaseOrder.orEmpty()) }
    var purchaseCost by remember(existing?.id) { mutableStateOf(existing?.purchaseCost.orEmpty()) }
    var notes by remember(existing?.id) { mutableStateOf(existing?.decodedNotes.orEmpty()) }
    var purchaseDateText by remember(existing?.id) {
        mutableStateOf(existing?.purchaseDate?.date?.take(10).orEmpty())
    }
    var expirationDateText by remember(existing?.id) {
        mutableStateOf(existing?.expirationDate?.date?.take(10).orEmpty())
    }
    var terminationDateText by remember(existing?.id) {
        mutableStateOf(existing?.terminationDate?.date?.take(10).orEmpty())
    }
    var hasPurchaseDate by remember(existing?.id) {
        mutableStateOf(!existing?.purchaseDate?.date.isNullOrBlank())
    }
    var hasExpirationDate by remember(existing?.id) {
        mutableStateOf(!existing?.expirationDate?.date.isNullOrBlank())
    }
    var hasTerminationDate by remember(existing?.id) {
        mutableStateOf(!existing?.terminationDate?.date.isNullOrBlank())
    }
    var reassignable by remember(existing?.id) { mutableStateOf(existing?.reassignable ?: true) }
    var maintained by remember(existing?.id) { mutableStateOf(existing?.maintained ?: false) }
    var selectedCategoryId by remember(existing?.id) { mutableIntStateOf(existing?.category?.id ?: 0) }
    var selectedCompanyId by remember(existing?.id) { mutableIntStateOf(existing?.company?.id ?: 0) }
    var selectedManufacturerId by remember(existing?.id) { mutableIntStateOf(existing?.manufacturer?.id ?: 0) }
    var selectedSupplierId by remember(existing?.id) { mutableIntStateOf(existing?.supplier?.id ?: 0) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val licenseCategories = remember(categories) { viewModel.apiClient.categoriesFor("license") }
    val seats = maxOf(1, seatsText.trim().toIntOrNull() ?: 1)
    val canSave = name.trim().isNotEmpty() && selectedCategoryId > 0 && seats >= 1

    LaunchedEffect(Unit) {
        if (categories.isEmpty()) viewModel.apiClient.fetchCategories()
        if (companies.isEmpty()) viewModel.apiClient.fetchCompanies()
        if (manufacturers.isEmpty()) viewModel.apiClient.fetchManufacturers()
        if (suppliers.isEmpty()) viewModel.apiClient.fetchSuppliers()
    }

    fun buildBody(): Map<String, Any?> {
        val minAmt = minAmtText.trim().toIntOrNull() ?: 0
        val body = mutableMapOf<String, Any?>(
            "name" to name.trim(),
            "seats" to seats,
            "reassignable" to if (reassignable) 1 else 0,
            "maintained" to if (maintained) 1 else 0,
        )
        if (selectedCategoryId > 0) body["category_id"] = selectedCategoryId
        if (minAmt > 0) body["min_amt"] = minAmt
        body["serial"] = productKey.trim()
        licensedToName.trim().takeIf { it.isNotEmpty() }?.let { body["license_name"] = it }
        licensedToEmail.trim().takeIf { it.isNotEmpty() }?.let { body["license_email"] = it }
        orderNumber.trim().takeIf { it.isNotEmpty() }?.let { body["order_number"] = it }
        purchaseOrder.trim().takeIf { it.isNotEmpty() }?.let { body["purchase_order"] = it }
        val normalizedCost = normalizeDecimalForApi(purchaseCost)
        if (normalizedCost != null) {
            body["purchase_cost"] = normalizedCost
        } else if (existing != null) {
            body["purchase_cost"] = null
        }
        body["purchase_date"] = if (hasPurchaseDate) {
            parseApiDate(purchaseDateText)?.let { formatApiDate(it) }
        } else null
        body["expiration_date"] = if (hasExpirationDate) {
            parseApiDate(expirationDateText)?.let { formatApiDate(it) }
        } else null
        body["termination_date"] = if (hasTerminationDate) {
            parseApiDate(terminationDateText)?.let { formatApiDate(it) }
        } else null
        if (selectedManufacturerId > 0) body["manufacturer_id"] = selectedManufacturerId
        if (selectedSupplierId > 0) body["supplier_id"] = selectedSupplierId
        if (selectedCompanyId > 0) body["company_id"] = selectedCompanyId
        notes.trim().takeIf { it.isNotEmpty() }?.let { body["notes"] = it }
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
                    var createdId: Int? = null
                    val success = if (existing == null) {
                        val result = viewModel.apiClient.createLicense(body)
                        if (!result.success) {
                            errorMessage = result.message ?: lastApiMessage ?: L10n.string("create_failed")
                        } else {
                            createdId = result.id
                            createdId?.let { viewModel.apiClient.fetchLicenseDetails(it) }
                        }
                        result.success
                    } else {
                        val error = viewModel.apiClient.updateLicense(existing.id, body)
                        if (error != null) errorMessage = error
                        error == null
                    }
                    isSaving = false
                    if (success) {
                        viewModel.syncInBackground()
                        onSaved(createdId ?: existing?.id)
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
            OutlinedTextField(
                value = productKey,
                onValueChange = { productKey = it },
                label = { Text(L10n.string("product_key")) },
                modifier = Modifier.fillMaxWidth(),
            )
            SearchablePickerField(
                label = L10n.fieldLabel("category", required = true),
                items = licenseCategories.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedCategoryId.takeIf { it > 0 },
                onSelected = { selectedCategoryId = it.id },
            )
            SearchablePickerField(
                label = L10n.string("manufacturer"),
                items = manufacturers.map { PickerItem(it.id, it.name) },
                selectedId = selectedManufacturerId.takeIf { it > 0 },
                onSelected = { selectedManufacturerId = it.id },
            )
            SearchablePickerField(
                label = L10n.string("company"),
                items = companies.map { PickerItem(it.id, it.name) },
                selectedId = selectedCompanyId.takeIf { it > 0 },
                onSelected = { selectedCompanyId = it.id },
            )

            FormSectionTitle(L10n.string("seats"))
            OutlinedTextField(
                value = seatsText,
                onValueChange = { seatsText = it.filter { ch -> ch.isDigit() } },
                label = { Text(L10n.fieldLabel("seats", required = true)) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = minAmtText,
                onValueChange = { minAmtText = it.filter { ch -> ch.isDigit() } },
                label = { Text(L10n.string("minimum_amount")) },
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("reassignable"), modifier = Modifier.weight(1f))
                Switch(checked = reassignable, onCheckedChange = { reassignable = it })
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("maintained"), modifier = Modifier.weight(1f))
                Switch(checked = maintained, onCheckedChange = { maintained = it })
            }

            FormSectionTitle(L10n.string("licensed_to"))
            OutlinedTextField(
                value = licensedToName,
                onValueChange = { licensedToName = it },
                label = { Text(L10n.string("license_to_name")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = licensedToEmail,
                onValueChange = { licensedToEmail = it },
                label = { Text(L10n.string("license_to_email")) },
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
                value = purchaseOrder,
                onValueChange = { purchaseOrder = it },
                label = { Text(L10n.string("purchase_order")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = purchaseCost,
                onValueChange = { purchaseCost = it },
                label = { Text(L10n.string("purchase_price")) },
                modifier = Modifier.fillMaxWidth(),
            )
            SearchablePickerField(
                label = L10n.string("supplier"),
                items = suppliers.map { PickerItem(it.id, it.name) },
                selectedId = selectedSupplierId.takeIf { it > 0 },
                onSelected = { selectedSupplierId = it.id },
            )
            DateToggleRow(L10n.string("purchase_date"), hasPurchaseDate, { hasPurchaseDate = it })
            if (hasPurchaseDate) {
                OutlinedTextField(
                    value = purchaseDateText,
                    onValueChange = { purchaseDateText = it },
                    label = { Text(L10n.string("set_purchase_date")) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            DateToggleRow(L10n.string("expiration_date"), hasExpirationDate, { hasExpirationDate = it })
            if (hasExpirationDate) {
                OutlinedTextField(
                    value = expirationDateText,
                    onValueChange = { expirationDateText = it },
                    label = { Text(L10n.string("expiration_date")) },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            DateToggleRow(L10n.string("termination_date"), hasTerminationDate, { hasTerminationDate = it })
            if (hasTerminationDate) {
                OutlinedTextField(
                    value = terminationDateText,
                    onValueChange = { terminationDateText = it },
                    label = { Text(L10n.string("termination_date")) },
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

@Composable
private fun DateToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
