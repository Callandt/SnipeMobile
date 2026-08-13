package com.callandt.snipemobile.ui.user

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
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetFormSheetScaffold
import com.callandt.snipemobile.ui.asset.AssetFullScreenSheet
import com.callandt.snipemobile.ui.asset.FormSectionTitle
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@Composable
fun AddUserSheet(
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onCreated: (Int?) -> Unit = {},
) {
    UserFormSheet(
        viewModel = viewModel,
        title = L10n.string("new_user"),
        saveLabel = L10n.string("create"),
        existing = null,
        onDismiss = onDismiss,
        onSaved = onCreated,
    )
}

@Composable
fun EditUserSheet(
    user: User,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    UserFormSheet(
        viewModel = viewModel,
        title = L10n.string("mgmt_edit_title", L10n.string("user")),
        saveLabel = L10n.string("save"),
        existing = user,
        onDismiss = onDismiss,
        onSaved = { onSaved() },
    )
}

@Composable
private fun UserFormSheet(
    viewModel: AppViewModel,
    title: String,
    saveLabel: String,
    existing: User?,
    onDismiss: () -> Unit,
    onSaved: (Int?) -> Unit,
) {
    val locations by viewModel.locations.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()

    var firstName by remember(existing?.id) { mutableStateOf(existing?.decodedFirstName.orEmpty()) }
    var lastName by remember(existing?.id) { mutableStateOf(existing?.decodedLastName.orEmpty()) }
    var username by remember(existing?.id) { mutableStateOf(existing?.decodedUsername.orEmpty()) }
    var email by remember(existing?.id) { mutableStateOf(existing?.decodedEmail.orEmpty()) }
    var jobtitle by remember(existing?.id) { mutableStateOf(existing?.decodedJobtitle.orEmpty()) }
    var phone by remember(existing?.id) { mutableStateOf(existing?.decodedPhone.orEmpty()) }
    var employeeNumber by remember(existing?.id) { mutableStateOf(existing?.decodedEmployeeNumber.orEmpty()) }
    var notes by remember(existing?.id) { mutableStateOf(existing?.decodedNotes.orEmpty()) }
    var password by remember { mutableStateOf("") }
    var passwordConfirmation by remember { mutableStateOf("") }
    var activated by remember(existing?.id) { mutableStateOf(existing?.activated ?: true) }
    var selectedCompanyId by remember(existing?.id) { mutableIntStateOf(existing?.company?.id ?: 0) }
    var selectedLocationId by remember(existing?.id) { mutableIntStateOf(existing?.location?.id ?: 0) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val isNew = existing == null
    val canSave = firstName.trim().isNotEmpty() &&
        username.trim().isNotEmpty() &&
        (password == passwordConfirmation) &&
        (!isNew || password.isNotEmpty())

    LaunchedEffect(Unit) {
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
        if (companies.isEmpty()) viewModel.apiClient.fetchCompanies()
    }

    fun buildBody(): Map<String, Any?> {
        val body = mutableMapOf<String, Any?>(
            "first_name" to firstName.trim(),
            "username" to username.trim(),
            "activated" to if (activated) 1 else 0,
        )
        lastName.trim().takeIf { it.isNotEmpty() }?.let { body["last_name"] = it }
        email.trim().takeIf { it.isNotEmpty() }?.let { body["email"] = it }
        jobtitle.trim().takeIf { it.isNotEmpty() }?.let { body["jobtitle"] = it }
        phone.trim().takeIf { it.isNotEmpty() }?.let { body["phone"] = it }
        employeeNumber.trim().takeIf { it.isNotEmpty() }?.let { body["employee_num"] = it }
        notes.trim().takeIf { it.isNotEmpty() }?.let { body["notes"] = it }
        if (selectedCompanyId > 0) body["company_id"] = selectedCompanyId
        if (selectedLocationId > 0) body["location_id"] = selectedLocationId
        if (password.isNotEmpty()) {
            body["password"] = password
            body["password_confirmation"] = passwordConfirmation
        }
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
                        val result = viewModel.apiClient.createUser(body)
                        if (!result.success) {
                            errorMessage = result.message ?: lastApiMessage ?: L10n.string("create_failed")
                        } else {
                            createdId = result.id
                            createdId?.let { viewModel.apiClient.fetchUserDetails(it) }
                        }
                        result.success
                    } else {
                        val ok = viewModel.apiClient.updateUser(existing.id, body)
                        if (!ok) errorMessage = lastApiMessage ?: L10n.string("mgmt_save_failed")
                        ok
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
                value = firstName,
                onValueChange = { firstName = it },
                label = { Text(L10n.fieldLabel("first_name", required = true)) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = lastName,
                onValueChange = { lastName = it },
                label = { Text(L10n.string("last_name")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = username,
                onValueChange = { username = it },
                label = { Text(L10n.fieldLabel("username", required = true)) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text(L10n.string("email")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = jobtitle,
                onValueChange = { jobtitle = it },
                label = { Text(L10n.string("jobtitle")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text(L10n.string("phone")) },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = employeeNumber,
                onValueChange = { employeeNumber = it },
                label = { Text(L10n.string("employee_number")) },
                modifier = Modifier.fillMaxWidth(),
            )

            FormSectionTitle(L10n.string("organization"))
            SearchablePickerField(
                label = L10n.string("company"),
                items = companies.map { PickerItem(it.id, it.name) },
                selectedId = selectedCompanyId.takeIf { it > 0 },
                onSelected = { selectedCompanyId = it.id },
            )
            SearchablePickerField(
                label = L10n.string("location"),
                items = locations.map { PickerItem(it.id, it.decodedName) },
                selectedId = selectedLocationId.takeIf { it > 0 },
                onSelected = { selectedLocationId = it.id },
            )

            FormSectionTitle(L10n.string("security"))
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = {
                    Text(
                        if (isNew) {
                            L10n.fieldLabel("password", required = true)
                        } else {
                            L10n.string("new_password")
                        },
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = passwordConfirmation,
                onValueChange = { passwordConfirmation = it },
                label = {
                    Text(
                        if (isNew) {
                            L10n.fieldLabel("password_confirmation", required = true)
                        } else {
                            L10n.string("password_confirmation")
                        },
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("activated"), modifier = Modifier.weight(1f))
                Switch(checked = activated, onCheckedChange = { activated = it })
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
