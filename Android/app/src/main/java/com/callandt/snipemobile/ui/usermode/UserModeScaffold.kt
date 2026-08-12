package com.callandt.snipemobile.ui.usermode

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarDefaults
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.AccessoryCard
import com.callandt.snipemobile.ui.components.AssetCard
import com.callandt.snipemobile.ui.components.LicenseCard
import com.callandt.snipemobile.ui.detail.UserDetailScreen
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.accessoryMatchesSearch
import com.callandt.snipemobile.ui.util.assetMatchesSearch
import com.callandt.snipemobile.ui.util.licenseMatchesSearch
import kotlinx.coroutines.launch

private enum class UserModeTab(
    val titleKey: String,
    val icon: ImageVector,
) {
    Profile("user_mode_my_profile", Icons.Default.Person),
    Assets("user_mode_my_assets", Icons.Default.Laptop),
    Requests("user_mode_requests", Icons.Default.Download),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UserModeScaffold(
    viewModel: AppViewModel,
    onOpenSettings: () -> Unit,
    onAssetClick: (Int) -> Unit,
    onAccessoryClick: (Int) -> Unit,
    onLicenseClick: (Int) -> Unit,
) {
    var selectedTab by remember { mutableStateOf(UserModeTab.Profile) }
    val scope = rememberCoroutineScope()
    val isLoading by viewModel.isLoading.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val accessories by viewModel.accessories.collectAsState()
    val licenses by viewModel.licenses.collectAsState()
    val currentUser by viewModel.currentUser.collectAsState()
    val refreshError by viewModel.refreshErrorMessage.collectAsState()

    var requestableAssets by remember { mutableStateOf<List<Asset>>(emptyList()) }
    var isRefreshingRequests by remember { mutableStateOf(false) }
    var pendingRequestIds by remember { mutableStateOf(setOf<Int>()) }
    var actionError by remember { mutableStateOf<String?>(null) }
    var refreshing by remember { mutableStateOf(false) }
    var assetsSearch by remember { mutableStateOf("") }

    suspend fun reloadRequestables(reportErrors: Boolean) {
        isRefreshingRequests = true
        try {
            requestableAssets = viewModel.apiClient.fetchRequestableAssets(reportErrors = reportErrors)
        } finally {
            isRefreshingRequests = false
        }
    }

    suspend fun reloadAll(reportErrors: Boolean) {
        if (reportErrors) viewModel.clearRefreshError()
        viewModel.apiClient.fetchUserModeData(clearRefreshError = reportErrors)
        if (!reportErrors || viewModel.refreshErrorMessage.value == null) {
            reloadRequestables(reportErrors = reportErrors)
        }
    }

    LaunchedEffect(Unit) {
        reloadAll(reportErrors = true)
    }

    Scaffold(
        bottomBar = {
            NavigationBar(windowInsets = NavigationBarDefaults.windowInsets) {
                UserModeTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(L10n.string(tab.titleKey)) },
                    )
                }
            }
        },
    ) { padding ->
        Column(modifier = Modifier.padding(padding).fillMaxSize()) {
            when (selectedTab) {
                UserModeTab.Profile -> UserModeProfileTab(
                    viewModel = viewModel,
                    currentUser = currentUser,
                    isLoading = isLoading,
                    refreshing = refreshing,
                    onRefreshingChange = { refreshing = it },
                    onReload = { reportErrors -> reloadAll(reportErrors) },
                    onOpenSettings = onOpenSettings,
                )

                UserModeTab.Assets -> UserModeAssetsTab(
                    viewModel = viewModel,
                    assets = assets,
                    accessories = accessories,
                    licenses = licenses,
                    isLoading = isLoading,
                    assetsSearch = assetsSearch,
                    onAssetsSearchChange = { assetsSearch = it },
                    refreshing = refreshing,
                    onRefreshingChange = { refreshing = it },
                    onReload = { reportErrors -> reloadAll(reportErrors) },
                    onOpenSettings = onOpenSettings,
                    onAssetClick = onAssetClick,
                    onAccessoryClick = onAccessoryClick,
                    onLicenseClick = onLicenseClick,
                )

                UserModeTab.Requests -> UserModeRequestsTab(
                    viewModel = viewModel,
                    requestableAssets = requestableAssets,
                    isRefreshingRequests = isRefreshingRequests,
                    refreshing = refreshing,
                    pendingRequestIds = pendingRequestIds,
                    onPendingIdsChange = { pendingRequestIds = it },
                    onActionError = { actionError = it },
                    onRefreshingChange = { refreshing = it },
                    onReloadRequestables = { reportErrors -> reloadRequestables(reportErrors) },
                    onOpenSettings = onOpenSettings,
                    onAssetClick = onAssetClick,
                )
            }
        }
    }

    if (actionError != null) {
        AlertDialog(
            onDismissRequest = { actionError = null },
            title = { Text(L10n.string("error")) },
            text = { Text(actionError.orEmpty()) },
            confirmButton = {
                TextButton(onClick = { actionError = null }) { Text(L10n.string("ok")) }
            },
        )
    }

    if (refreshError != null) {
        val pendingWipe by viewModel.pendingUnauthorizedSessionWipe.collectAsState()
        if (!pendingWipe) {
            AlertDialog(
                onDismissRequest = { viewModel.clearRefreshError() },
                title = { Text(L10n.string("refresh_failed_title")) },
                text = { Text(refreshError.orEmpty()) },
                confirmButton = {
                    TextButton(onClick = { viewModel.clearRefreshError() }) {
                        Text(L10n.string("ok"))
                    }
                },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UserModeProfileTab(
    viewModel: AppViewModel,
    currentUser: User?,
    isLoading: Boolean,
    refreshing: Boolean,
    onRefreshingChange: (Boolean) -> Unit,
    onReload: suspend (Boolean) -> Unit,
    onOpenSettings: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                onRefreshingChange(true)
                onReload(true)
                onRefreshingChange(false)
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        if (currentUser != null) {
            UserDetailScreen(
                userId = currentUser.id,
                viewModel = viewModel,
                onBack = {},
                isReadOnly = true,
                showNavigationIcon = false,
                onOpenSettings = onOpenSettings,
            )
        } else if (isLoading) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
        } else {
            UserModeEmptyState(
                title = L10n.string("user_mode_profile_unavailable_title"),
                description = L10n.string("user_mode_profile_unavailable_desc"),
                onOpenSettings = onOpenSettings,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UserModeAssetsTab(
    viewModel: AppViewModel,
    assets: List<com.callandt.snipemobile.data.model.Asset>,
    accessories: List<com.callandt.snipemobile.data.model.Accessory>,
    licenses: List<com.callandt.snipemobile.data.model.License>,
    isLoading: Boolean,
    assetsSearch: String,
    onAssetsSearchChange: (String) -> Unit,
    refreshing: Boolean,
    onRefreshingChange: (Boolean) -> Unit,
    onReload: suspend (Boolean) -> Unit,
    onOpenSettings: () -> Unit,
    onAssetClick: (Int) -> Unit,
    onAccessoryClick: (Int) -> Unit,
    onLicenseClick: (Int) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val query = assetsSearch.trim()
    val myAssets = remember(assets, query) {
        if (query.isEmpty()) assets else assets.filter { assetMatchesSearch(it, query) }
    }
    val myAccessories = remember(accessories, query) {
        if (query.isEmpty()) accessories
        else accessories.filter { accessoryMatchesSearch(it, query) }
    }
    val myLicenses = remember(licenses, query) {
        if (query.isEmpty()) licenses
        else licenses.filter { licenseMatchesSearch(it, query) }
    }
    val hasAnyAssigned = assets.isNotEmpty() || accessories.isNotEmpty() || licenses.isNotEmpty()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("user_mode_my_assets")) },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = L10n.string("settings"))
                    }
                },
            )
        },
    ) { innerPadding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch {
                    onRefreshingChange(true)
                    onReload(true)
                    onRefreshingChange(false)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                OutlinedTextField(
                    value = assetsSearch,
                    onValueChange = onAssetsSearchChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    singleLine = true,
                    placeholder = { Text(L10n.string("search_assets")) },
                )
                AssignedCountChips(
                    assetsCount = myAssets.size,
                    accessoriesCount = myAccessories.size,
                    licensesCount = myLicenses.size,
                )
                when {
                    isLoading && !hasAnyAssigned -> {
                        Box(
                            modifier = Modifier.fillMaxSize(),
                            contentAlignment = Alignment.Center,
                        ) { CircularProgressIndicator() }
                    }
                    !hasAnyAssigned -> {
                        UserModeEmptyState(
                            title = L10n.string("user_mode_no_assets_title"),
                            description = L10n.string("user_mode_no_assets_desc"),
                            showSettings = false,
                        )
                    }
                    myAssets.isEmpty() && myAccessories.isEmpty() && myLicenses.isEmpty() -> {
                        UserModeEmptyState(
                            title = L10n.string("user_mode_no_assets_title"),
                            description = L10n.string("user_mode_no_assets_desc"),
                            showSettings = false,
                        )
                    }
                    else -> {
                        LazyColumn(
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(myAssets, key = { "a-${it.id}" }) { asset ->
                                AssetCard(asset = asset, onClick = { onAssetClick(asset.id) })
                            }
                            if (myAccessories.isNotEmpty()) {
                                item {
                                    Text(
                                        L10n.string("tab_accessories"),
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        modifier = Modifier.padding(top = 8.dp),
                                    )
                                }
                                items(myAccessories, key = { "acc-${it.id}" }) { accessory ->
                                    AccessoryCard(
                                        accessory = accessory,
                                        onClick = { onAccessoryClick(accessory.id) },
                                    )
                                }
                            }
                            if (myLicenses.isNotEmpty()) {
                                item {
                                    Text(
                                        L10n.string("tab_licenses"),
                                        style = MaterialTheme.typography.titleSmall,
                                        fontWeight = FontWeight.SemiBold,
                                        modifier = Modifier.padding(top = 8.dp),
                                    )
                                }
                                items(myLicenses, key = { "lic-${it.id}" }) { license ->
                                    LicenseCard(
                                        license = license,
                                        onClick = { onLicenseClick(license.id) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun UserModeRequestsTab(
    viewModel: AppViewModel,
    requestableAssets: List<Asset>,
    isRefreshingRequests: Boolean,
    refreshing: Boolean,
    pendingRequestIds: Set<Int>,
    onPendingIdsChange: (Set<Int>) -> Unit,
    onActionError: (String?) -> Unit,
    onRefreshingChange: (Boolean) -> Unit,
    onReloadRequestables: suspend (Boolean) -> Unit,
    onOpenSettings: () -> Unit,
    onAssetClick: (Int) -> Unit,
) {
    val scope = rememberCoroutineScope()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("user_mode_requests")) },
                actions = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = L10n.string("settings"))
                    }
                },
            )
        },
    ) { innerPadding ->
        PullToRefreshBox(
            isRefreshing = refreshing || isRefreshingRequests,
            onRefresh = {
                scope.launch {
                    onRefreshingChange(true)
                    onReloadRequestables(true)
                    onRefreshingChange(false)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                isRefreshingRequests && requestableAssets.isEmpty() -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) { CircularProgressIndicator() }
                }
                requestableAssets.isEmpty() -> {
                    UserModeEmptyState(
                        title = L10n.string("user_mode_no_requestable_title"),
                        description = L10n.string("user_mode_no_requestable_desc"),
                        showSettings = false,
                    )
                }
                else -> {
                    LazyColumn(
                        contentPadding = PaddingValues(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(requestableAssets, key = { it.id }) { asset ->
                            AssetCard(
                                asset = asset,
                                onClick = { onAssetClick(asset.id) },
                                footer = {
                                    RequestActionButton(
                                        asset = asset,
                                        isPending = pendingRequestIds.contains(asset.id),
                                        onClick = {
                                            scope.launch {
                                                onPendingIdsChange(pendingRequestIds + asset.id)
                                                val cancel = canCancelRequest(asset)
                                                val error = if (cancel) {
                                                    viewModel.apiClient.cancelAssetRequest(asset.id)
                                                } else {
                                                    viewModel.apiClient.requestAsset(asset.id)
                                                }
                                                onPendingIdsChange(pendingRequestIds - asset.id)
                                                if (error != null) {
                                                    onActionError(error)
                                                } else {
                                                    onReloadRequestables(true)
                                                }
                                            }
                                        },
                                    )
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AssignedCountChips(
    assetsCount: Int,
    accessoriesCount: Int,
    licensesCount: Int,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (assetsCount > 0) {
            CountChip(Icons.Default.Laptop, "$assetsCount ${L10n.string("tab_assets")}")
        }
        if (accessoriesCount > 0) {
            CountChip(Icons.Default.CreditCard, "$accessoriesCount ${L10n.string("tab_accessories")}")
        }
        if (licensesCount > 0) {
            CountChip(Icons.Default.Description, "$licensesCount ${L10n.string("tab_licenses")}")
        }
    }
}

@Composable
private fun CountChip(icon: ImageVector, label: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(16.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun UserModeEmptyState(
    title: String,
    description: String,
    showSettings: Boolean = true,
    onOpenSettings: (() -> Unit)? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (showSettings && onOpenSettings != null) {
            Spacer(modifier = Modifier.height(16.dp))
            TextButton(onClick = onOpenSettings) {
                Text(L10n.string("settings"))
            }
        }
    }
}

private fun canCancelRequest(asset: Asset): Boolean =
    asset.availableActions?.cancel == true

private fun canRequestAsset(asset: Asset): Boolean {
    if (canCancelRequest(asset)) return false
    return asset.availableActions?.request != false
}

@Composable
private fun RequestActionButton(
    asset: Asset,
    isPending: Boolean,
    onClick: () -> Unit,
) {
    val cancelMode = canCancelRequest(asset)
    if (!cancelMode && !canRequestAsset(asset)) return

    Button(
        onClick = onClick,
        enabled = !isPending,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 4.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (cancelMode) SnipeOrange else MaterialTheme.colorScheme.primary,
        ),
    ) {
        if (isPending) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = Color.White,
            )
        } else {
            Icon(
                imageVector = if (cancelMode) Icons.Default.Cancel else Icons.Default.Download,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Spacer(modifier = Modifier.size(8.dp))
            Text(
                if (cancelMode) {
                    L10n.string("user_mode_cancel_request_action")
                } else {
                    L10n.string("user_mode_request_action")
                },
            )
        }
    }
}
