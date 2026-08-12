package com.callandt.snipemobile.ui.consumable

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.userPickerSearchText
import com.callandt.snipemobile.ui.util.usersForNamePicker
import kotlinx.coroutines.launch

@Composable
fun ConsumableCheckoutSheet(
    consumable: Consumable,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSuccess: () -> Unit = {},
) {
    val users by viewModel.users.collectAsState()
    val currentUser by viewModel.currentUser.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()
    val pickerUsers = remember(users, currentUser) { usersForNamePicker(users, currentUser) }

    var selectedUserId by remember { mutableIntStateOf(0) }
    var note by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val canSave = selectedUserId > 0

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("check_out_to"),
            saveLabel = L10n.string("check_out"),
            isSaving = isSaving,
            canSave = canSave,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = {
                isSaving = true
                scope.launch {
                    val ok = viewModel.apiClient.checkoutConsumable(
                        consumableId = consumable.id,
                        userId = selectedUserId,
                        note = note.trim().takeIf { it.isNotEmpty() },
                    )
                    isSaving = false
                    if (ok) {
                        onSuccess()
                        onDismiss()
                    } else {
                        errorMessage = lastApiMessage ?: L10n.string("checkout_failed")
                    }
                }
            },
        ) {
            SearchablePickerField(
                label = L10n.string("select_user_short"),
                items = pickerUsers.map {
                    PickerItem(it.id, it.decodedName, searchText = userPickerSearchText(it))
                },
                selectedId = selectedUserId.takeIf { it > 0 },
                onSelected = { selectedUserId = it.id },
            )
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text(L10n.string("note")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 3,
            )
            errorMessage?.let { Text(it, color = androidx.compose.material3.MaterialTheme.colorScheme.error) }
        }
    }
}
