package com.callandt.snipemobile.ui.location

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
import com.callandt.snipemobile.data.model.Location
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.asset.FormSectionTitle
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@Composable
fun AddLocationSheet(
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onCreated: (id: Int?, name: String?) -> Unit = { _, _ -> },
) {
    LocationFormSheet(
        viewModel = viewModel,
        title = L10n.string("new_location"),
        saveLabel = L10n.string("create"),
        existing = null,
        onDismiss = onDismiss,
        onSaved = { id, name -> onCreated(id, name) },
    )
}

@Composable
fun EditLocationSheet(
    location: Location,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    LocationFormSheet(
        viewModel = viewModel,
        title = L10n.string("mgmt_edit_title", L10n.string("location")),
        saveLabel = L10n.string("save"),
        existing = location,
        onDismiss = onDismiss,
        onSaved = { _, _ -> onSaved() },
    )
}

@Composable
private fun LocationFormSheet(
    viewModel: AppViewModel,
    title: String,
    saveLabel: String,
    existing: Location?,
    onDismiss: () -> Unit,
    onSaved: (id: Int?, name: String?) -> Unit,
) {
    val locations by viewModel.locations.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var name by remember(existing?.id) { mutableStateOf(existing?.decodedName.orEmpty()) }
    var address by remember(existing?.id) { mutableStateOf(existing?.address.orEmpty()) }
    var address2 by remember(existing?.id) { mutableStateOf(existing?.address2.orEmpty()) }
    var city by remember(existing?.id) { mutableStateOf(existing?.city.orEmpty()) }
    var state by remember(existing?.id) { mutableStateOf(existing?.state.orEmpty()) }
    var country by remember(existing?.id) { mutableStateOf(existing?.country.orEmpty()) }
    var zip by remember(existing?.id) { mutableStateOf(existing?.zip.orEmpty()) }
    var currency by remember(existing?.id) { mutableStateOf(existing?.currency.orEmpty()) }
    var selectedParentId by remember(existing?.id) { mutableIntStateOf(existing?.parent?.id ?: 0) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val parentLocations = remember(locations, existing?.id) {
        locations.filter { it.id != existing?.id }.sortedBy { it.decodedName.lowercase() }
    }
    val canSave = name.trim().isNotEmpty()

    LaunchedEffect(Unit) {
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
    }

    fun buildBody(): Map<String, Any?> {
        val body = mutableMapOf<String, Any?>("name" to name.trim())
        address.trim().takeIf { it.isNotEmpty() }?.let { body["address"] = it }
        address2.trim().takeIf { it.isNotEmpty() }?.let { body["address2"] = it }
        city.trim().takeIf { it.isNotEmpty() }?.let { body["city"] = it }
        state.trim().takeIf { it.isNotEmpty() }?.let { body["state"] = it }
        country.trim().takeIf { it.isNotEmpty() }?.let { body["country"] = it }
        zip.trim().takeIf { it.isNotEmpty() }?.let { body["zip"] = it }
        currency.trim().takeIf { it.isNotEmpty() }?.let { body["currency"] = it }
        if (selectedParentId > 0) body["parent_id"] = selectedParentId
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
                        val result = viewModel.apiClient.createLocation(body)
                        if (!result.success) {
                            errorMessage = result.message ?: lastApiMessage ?: L10n.string("create_failed")
                        } else {
                            createdId = result.id
                            createdId?.let { viewModel.apiClient.fetchLocationDetails(it) }
                        }
                        result.success
                    } else {
                        val ok = viewModel.apiClient.updateLocation(existing.id, body)
                        if (!ok) errorMessage = lastApiMessage ?: L10n.string("mgmt_save_failed")
                        ok
                    }
                    isSaving = false
                    if (success) {
                        viewModel.syncInBackground()
                        onSaved(createdId ?: existing?.id, name.trim().takeIf { it.isNotEmpty() })
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
            if (parentLocations.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("parent_location"),
                    items = parentLocations.map { PickerItem(it.id, it.decodedName) },
                    selectedId = selectedParentId.takeIf { it > 0 },
                    onSelected = { selectedParentId = it.id },
                )
            }
            OutlinedTextField(
                value = currency,
                onValueChange = { currency = it },
                label = { Text(L10n.string("currency")) },
                modifier = Modifier.fillMaxWidth(),
            )

            FormSectionTitle(L10n.string("address"))
            OutlinedTextField(
                value = address,
                onValueChange = { address = it },
                label = { Text(L10n.string("address")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = address2,
                onValueChange = { address2 = it },
                label = { Text(L10n.string("address2")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = city,
                onValueChange = { city = it },
                label = { Text(L10n.string("city")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = state,
                onValueChange = { state = it },
                label = { Text(L10n.string("state")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = country,
                onValueChange = { country = it },
                label = { Text(L10n.string("country")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = zip,
                onValueChange = { zip = it },
                label = { Text(L10n.string("zip")) },
                modifier = Modifier.fillMaxWidth(),
            )

            errorMessage?.let { Text(it, color = androidx.compose.material3.MaterialTheme.colorScheme.error) }
        }
    }
}
