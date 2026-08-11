package com.callandt.snipemobile.ui.asset

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.api.UploadFile
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.StatusLabel
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.AssetStatusFilterSupport
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@Composable
fun AssetCheckinSheet(
    asset: Asset,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSuccess: () -> Unit = {},
) {
    val statusLabels by viewModel.statusLabels.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var name by remember(asset.id) { mutableStateOf(asset.decodedName) }
    var notes by remember { mutableStateOf("") }
    var selectedStatusId by remember { mutableIntStateOf(0) }
    var selectedLocationId by remember { mutableIntStateOf(0) }
    var pendingImages: List<PendingAssetImage> by remember { mutableStateOf(emptyList()) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var dismissAfterError by remember { mutableStateOf(false) }

    val statusPickerItems = remember(statusLabels) {
        val deployable = statusLabels.filter { it.isDeployableType }
        val source = deployable.ifEmpty { statusLabels }
        AssetStatusFilterSupport.sortedStatusLabels(source)
            .map { PickerItem(it.id, AssetStatusFilterSupport.displayName(it)) }
    }

    fun ensureDefaultStatus(labels: List<StatusLabel>) {
        val deployable = labels.filter { it.isDeployableType }
        val pool = deployable.ifEmpty { labels }
        val validIds = pool.map { it.id }.toSet()
        if (selectedStatusId in validIds) return
        selectedStatusId = pool.firstOrNull { AssetStatusFilterSupport.isReadyToDeployLabel(it) }?.id
            ?: pool.firstOrNull()?.id
            ?: 0
    }

    LaunchedEffect(Unit) {
        if (statusLabels.isEmpty()) viewModel.apiClient.fetchStatusLabels()
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
        ensureDefaultStatus(statusLabels)
    }

    LaunchedEffect(statusLabels) {
        if (statusLabels.isNotEmpty()) ensureDefaultStatus(statusLabels)
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("check_in_asset"),
            saveLabel = L10n.string("check_in"),
            isSaving = isSaving,
            canSave = true,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    val body = mutableMapOf<String, Any?>()
                    if (selectedStatusId > 0) body["status_id"] = selectedStatusId
                    val trimmedName = name.trim()
                    if (trimmedName.isNotEmpty() && trimmedName != asset.decodedName) {
                        body["name"] = trimmedName
                    }
                    notes.trim().takeIf { it.isNotEmpty() }?.let { body["note"] = it }
                    if (selectedLocationId > 0) body["location_id"] = selectedLocationId

                    val success = viewModel.apiClient.checkinAssetCustom(asset.id, body)
                    var photoUploadFailed = false
                    if (success && pendingImages.isNotEmpty()) {
                        val noteForFiles = notes.trim().takeIf { it.isNotEmpty() }
                            ?: L10n.string("checkin_photo_note")
                        val files = pendingImages.mapIndexed { index, image ->
                            UploadFile("checkin_${index + 1}.jpg", image.mimeType, image.bytes)
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
                        errorMessage = lastApiMessage ?: L10n.string("checkin_failed")
                    }
                }
            },
        ) {
            FormSectionTitle(L10n.string("asset_details"))
            if (statusPickerItems.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("status"),
                    items = statusPickerItems,
                    selectedId = selectedStatusId.takeIf { it > 0 },
                    placeholder = L10n.string("none"),
                    onSelected = { selectedStatusId = it.id },
                )
            }
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(L10n.string("name")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(L10n.string("notes")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
            )
            SearchablePickerField(
                label = L10n.string("location"),
                items = locations.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedLocationId.takeIf { it > 0 },
                placeholder = L10n.string("none"),
                onSelected = { selectedLocationId = it.id },
            )
            Text(
                text = L10n.string("name_help_checkin"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            AssetMultiPhotoSection(
                pendingImages = pendingImages,
                onPendingImagesChange = { pendingImages = it },
            )
        }
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = {
                val shouldDismiss = dismissAfterError
                errorMessage = null
                if (shouldDismiss) onDismiss()
            },
            title = { Text(if (dismissAfterError) L10n.string("result") else L10n.string("error")) },
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
