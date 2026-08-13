package com.callandt.snipemobile.ui.detail

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.AccessoryCard
import com.callandt.snipemobile.ui.components.AssetCard
import com.callandt.snipemobile.ui.components.ConsumableCard
import com.callandt.snipemobile.ui.components.DetailBarAction
import com.callandt.snipemobile.ui.components.DetailBottomBar
import com.callandt.snipemobile.ui.components.DetailEntityToolbarActions
import com.callandt.snipemobile.ui.components.DetailRow
import com.callandt.snipemobile.ui.components.DetailCardListSection
import com.callandt.snipemobile.ui.components.DetailSectionCard
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ItemCard
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.components.ItemHistoryTab
import com.callandt.snipemobile.ui.components.LicenseCard
import com.callandt.snipemobile.ui.components.userCardTitle
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.user.EditUserSheet
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

private enum class UserDetailTab(val key: String) {
    Details("asset_tab_details"),
    History("asset_tab_history"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UserDetailScreen(
    userId: Int,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenAsset: ((Int) -> Unit)? = null,
    onOpenAccessory: ((Int) -> Unit)? = null,
    onOpenLicense: ((Int) -> Unit)? = null,
    onOpenConsumable: ((Int) -> Unit)? = null,
    isReadOnly: Boolean = false,
    showNavigationIcon: Boolean = true,
    onOpenSettings: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val users by viewModel.users.collectAsState()
    val currentUser by viewModel.currentUser.collectAsState()
    val user = if (isReadOnly) {
        currentUser?.takeIf { it.id == userId } ?: users.firstOrNull { it.id == userId }
    } else {
        users.firstOrNull { it.id == userId }
    }
    val scope = rememberCoroutineScope()

    var detailUser by remember { mutableStateOf<User?>(null) }
    var userAssets by remember { mutableStateOf<List<Asset>>(emptyList()) }
    var userAccessories by remember { mutableStateOf<List<Accessory>>(emptyList()) }
    var userLicenses by remember { mutableStateOf<List<License>>(emptyList()) }
    var userConsumables by remember { mutableStateOf<List<Consumable>>(emptyList()) }
    var loadingAssigned by remember { mutableStateOf(!isReadOnly) }
    var showEdit by remember { mutableStateOf(false) }
    val deleteState = rememberEntityDeleteState()
    var tabIndex by remember { mutableIntStateOf(0) }

    fun reloadAssigned() {
        if (isReadOnly) {
            loadingAssigned = false
            return
        }
        scope.launch {
            loadingAssigned = true
            coroutineScope {
                val assetsDeferred = async { viewModel.apiClient.fetchUserAssets(userId) }
                val accessoriesDeferred = async { viewModel.apiClient.fetchUserAccessories(userId) }
                val licensesDeferred = async { viewModel.apiClient.fetchUserLicenses(userId) }
                val consumablesDeferred = async { viewModel.apiClient.fetchUserConsumables(userId) }
                userAssets = assetsDeferred.await()
                userAccessories = accessoriesDeferred.await()
                userLicenses = licensesDeferred.await()
                userConsumables = consumablesDeferred.await()
            }
            loadingAssigned = false
        }
    }

    LaunchedEffect(userId, isReadOnly, currentUser?.id) {
        if (isReadOnly) {
            detailUser = currentUser?.takeIf { it.id == userId } ?: user
            loadingAssigned = false
        } else {
            detailUser = viewModel.apiClient.fetchUserDetails(userId) ?: user
            reloadAssigned()
        }
    }

    val displayUser = detailUser ?: user
    val displayName = if (isReadOnly) {
        L10n.string("user_mode_my_profile")
    } else {
        displayUser?.let { userCardTitle(it) } ?: L10n.string("user")
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(displayName, maxLines = 1) },
                navigationIcon = {
                    if (showNavigationIcon) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                        }
                    }
                },
                actions = {
                    if (isReadOnly) {
                        if (onOpenSettings != null) {
                            IconButton(onClick = onOpenSettings) {
                                Icon(
                                    imageVector = Icons.Default.Settings,
                                    contentDescription = L10n.string("settings"),
                                )
                            }
                        }
                        IconButton(
                            onClick = {
                                val url = "${viewModel.apiClient.baseUrl.trimEnd('/')}/users/$userId"
                                runCatching {
                                    context.startActivity(
                                        Intent(Intent.ACTION_VIEW, Uri.parse(url)),
                                    )
                                }
                            },
                        ) {
                            Icon(
                                imageVector = Icons.Default.Language,
                                contentDescription = L10n.string("open_in_web"),
                            )
                        }
                    } else {
                        DetailEntityToolbarActions(
                            baseUrl = viewModel.apiClient.baseUrl,
                            webPath = "users/$userId",
                            onDeleteClick = { deleteState.requestDelete() },
                            deleteEnabled = !deleteState.isDeleting,
                        )
                    }
                },
            )
        },
        bottomBar = {
            if (!isReadOnly && displayUser != null) {
                DetailBottomBar(
                    actions = listOf(
                        DetailBarAction(L10n.string("edit"), SnipeOrange) { showEdit = true },
                    ),
                )
            }
        },
    ) { padding ->
        if (displayUser == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("no_users"))
            }
            return@Scaffold
        }

        UserDetailContent(
            user = displayUser,
            userAssets = userAssets,
            userAccessories = userAccessories,
            userLicenses = userLicenses,
            userConsumables = userConsumables,
            loadingAssigned = loadingAssigned,
            onOpenAsset = onOpenAsset,
            onOpenAccessory = onOpenAccessory,
            onOpenLicense = onOpenLicense,
            onOpenConsumable = onOpenConsumable,
            tabIndex = tabIndex,
            onTabSelected = { tabIndex = it },
            userId = userId,
            viewModel = viewModel,
            isReadOnly = isReadOnly,
            modifier = Modifier.padding(padding),
        )
    }

    if (showEdit && displayUser != null && !isReadOnly) {
        EditUserSheet(
            user = displayUser,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
            onSaved = {
                scope.launch {
                    detailUser = viewModel.apiClient.fetchUserDetails(userId) ?: displayUser
                    reloadAssigned()
                }
            },
        )
    }

    if (!isReadOnly) {
        EntityDeleteSupport(
            state = deleteState,
            confirmTitle = L10n.string("delete_item_confirm_title", displayName),
            confirmMessage = L10n.string("delete_user_confirm_message", displayName),
            onConfirmDelete = {
                deleteState.confirmDelete(
                    scope = scope,
                    delete = { viewModel.apiClient.deleteUser(userId) },
                    errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                    onSuccess = onBack,
                )
            },
        )
    }
}

@Composable
private fun UserDetailContent(
    user: User,
    userAssets: List<Asset>,
    userAccessories: List<Accessory>,
    userLicenses: List<License>,
    userConsumables: List<Consumable>,
    loadingAssigned: Boolean,
    onOpenAsset: ((Int) -> Unit)?,
    onOpenAccessory: ((Int) -> Unit)?,
    onOpenLicense: ((Int) -> Unit)?,
    onOpenConsumable: ((Int) -> Unit)?,
    tabIndex: Int,
    onTabSelected: (Int) -> Unit,
    userId: Int,
    viewModel: AppViewModel,
    isReadOnly: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        if (!isReadOnly) {
            TabRow(selectedTabIndex = tabIndex) {
                UserDetailTab.entries.forEachIndexed { index, tab ->
                    Tab(
                        selected = tabIndex == index,
                        onClick = { onTabSelected(index) },
                        text = { Text(L10n.string(tab.key)) },
                    )
                }
            }
        }
        when {
            isReadOnly || UserDetailTab.entries[tabIndex] == UserDetailTab.Details -> UserDetailsBody(
                user = user,
                userAssets = userAssets,
                userAccessories = userAccessories,
                userLicenses = userLicenses,
                userConsumables = userConsumables,
                loadingAssigned = loadingAssigned,
                onOpenAsset = onOpenAsset,
                onOpenAccessory = onOpenAccessory,
                onOpenLicense = onOpenLicense,
                onOpenConsumable = onOpenConsumable,
                showAssignedSections = !isReadOnly,
            )
            else -> ItemHistoryTab(
                itemType = "user",
                itemId = userId,
                viewModel = viewModel,
            )
        }
    }
}

@Composable
private fun UserDetailsBody(
    user: User,
    userAssets: List<Asset>,
    userAccessories: List<Accessory>,
    userLicenses: List<License>,
    userConsumables: List<Consumable>,
    loadingAssigned: Boolean,
    onOpenAsset: ((Int) -> Unit)?,
    onOpenAccessory: ((Int) -> Unit)?,
    onOpenLicense: ((Int) -> Unit)?,
    onOpenConsumable: ((Int) -> Unit)?,
    showAssignedSections: Boolean = true,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!user.image.isNullOrBlank()) {
            ItemCard(title = userCardTitle(user), subtitle = user.decodedEmail, imageUrl = user.image)
        }

        DetailSectionCard(title = L10n.string("user_info")) {
            DetailRow(L10n.string("username"), user.decodedUsername)
            if (user.decodedFirstName.isNotBlank()) {
                DetailRow(L10n.string("first_name"), user.decodedFirstName)
            }
            if (user.decodedLastName.isNotBlank()) {
                DetailRow(L10n.string("last_name"), user.decodedLastName)
            }
            DetailRow(L10n.string("job_title"), user.decodedJobtitle)
            DetailRow(L10n.string("employee_number"), user.decodedEmployeeNumber)
            DetailRow(L10n.string("email"), user.decodedEmail)
            DetailRow(L10n.string("phone"), user.decodedPhone)
            DetailRow(L10n.string("company"), user.decodedCompanyName)
            DetailRow(L10n.string("location"), user.decodedLocationName)
            user.activated?.let { activated ->
                DetailRow(
                    L10n.string("status"),
                    if (activated) L10n.string("activated") else L10n.string("deactivated"),
                )
            }
            val groupNames = user.groups.map { it.decodedName }.filter { it.isNotEmpty() }
            if (groupNames.isNotEmpty()) {
                DetailRow(L10n.string("groups"), groupNames.joinToString(", "))
            }
            DetailRow(L10n.string("notes"), user.decodedNotes)
        }

        if (showAssignedSections) {
            if (loadingAssigned) {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else {
                if (userAssets.isNotEmpty()) {
                    DetailCardListSection(title = L10n.string("assigned_assets")) {
                        userAssets.forEach { asset ->
                            AssetCard(
                                asset = asset,
                                onClick = { onOpenAsset?.invoke(asset.id) },
                            )
                        }
                    }
                }
                if (userAccessories.isNotEmpty()) {
                    DetailCardListSection(title = L10n.string("tab_accessories")) {
                        userAccessories.forEach { accessory ->
                            AccessoryCard(
                                accessory = accessory,
                                onClick = { onOpenAccessory?.invoke(accessory.id) },
                                showAvailability = false,
                            )
                        }
                    }
                }
                if (userLicenses.isNotEmpty()) {
                    DetailCardListSection(title = L10n.string("tab_licenses")) {
                        userLicenses.forEach { license ->
                            LicenseCard(
                                license = license,
                                onClick = { onOpenLicense?.invoke(license.id) },
                            )
                        }
                    }
                }
                if (userConsumables.isNotEmpty()) {
                    DetailCardListSection(title = L10n.string("tab_consumables")) {
                        userConsumables.forEach { consumable ->
                            ConsumableCard(
                                consumable = consumable,
                                onClick = { onOpenConsumable?.invoke(consumable.id) },
                            )
                        }
                    }
                }
            }
        }
    }
}
