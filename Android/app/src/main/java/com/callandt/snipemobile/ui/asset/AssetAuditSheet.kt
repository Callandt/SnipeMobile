package com.callandt.snipemobile.ui.asset

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.api.UploadFile
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

/** Single-asset audit form (location, next date, note, optional photo). */
@Composable
fun AssetAuditSheet(
    asset: Asset,
    locations: List<PickerItem>,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    var locationId by remember { mutableIntStateOf(0) }
    var updateLocation by remember { mutableStateOf(false) }
    var nextAuditDate by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var pendingImage by remember { mutableStateOf<PendingAssetImage?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("audit"),
            saveLabel = L10n.string("complete_audit"),
            isSaving = isSaving,
            canSave = !isSaving,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    val imageUpload = pendingImage?.let { UploadFile("audit.jpg", it.mimeType, it.bytes) }
                    val ok = viewModel.apiClient.auditAsset(
                        assetTag = asset.assetTag,
                        assetId = asset.id,
                        locationId = locationId.takeIf { it > 0 },
                        updateLocation = updateLocation,
                        nextAuditDate = nextAuditDate.trim().takeIf { it.isNotEmpty() },
                        note = note.trim().takeIf { it.isNotEmpty() },
                        image = imageUpload,
                    )
                    isSaving = false
                    if (ok) {
                        onSaved()
                        onDismiss()
                    }
                }
            },
        ) {
            Text(
                asset.decodedAssetTag,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            if (locations.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("location_optional"),
                    items = locations,
                    selectedId = locationId.takeIf { it > 0 },
                    placeholder = L10n.string("none"),
                    onSelected = { locationId = it.id },
                )
                if (locationId != 0) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(L10n.string("bulk_audit_update_location"), modifier = Modifier.weight(1f))
                        Switch(checked = updateLocation, onCheckedChange = { updateLocation = it })
                    }
                }
            }

            OutlinedTextField(
                value = nextAuditDate,
                onValueChange = { nextAuditDate = it },
                label = { Text(L10n.string("set_next_audit")) },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )

            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text(L10n.string("note")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 2,
            )

            AssetPhotoSection(
                pendingImage = pendingImage,
                onPendingImageChange = { pendingImage = it },
            )
        }
    }
}
