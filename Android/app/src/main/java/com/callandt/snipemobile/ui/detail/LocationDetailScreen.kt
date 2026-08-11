package com.callandt.snipemobile.ui.detail

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
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.Location
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.AccessoryCard
import com.callandt.snipemobile.ui.components.AssetCard
import com.callandt.snipemobile.ui.components.DetailBarAction
import com.callandt.snipemobile.ui.components.DetailBottomBar
import com.callandt.snipemobile.ui.components.DetailEntityToolbarActions
import com.callandt.snipemobile.ui.components.DetailRow
import com.callandt.snipemobile.ui.components.DetailSectionCard
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.UserCard
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.components.locationCardTitle
import com.callandt.snipemobile.ui.location.EditLocationSheet
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.util.HtmlDecoder
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationDetailScreen(
    locationId: Int,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenUser: ((Int) -> Unit)? = null,
    onOpenAsset: ((Int) -> Unit)? = null,
    onOpenAccessory: ((Int) -> Unit)? = null,
) {
    val locations by viewModel.locations.collectAsState()
    val users by viewModel.users.collectAsState()
    val location = locations.firstOrNull { it.id == locationId }
    val scope = rememberCoroutineScope()

    var subtab by remember { mutableIntStateOf(0) }
    var locationAssets by remember { mutableStateOf<List<Asset>>(emptyList()) }
    var locationAccessories by remember { mutableStateOf<List<Accessory>>(emptyList()) }
    var loadingAssets by remember { mutableStateOf(false) }
    var loadingAccessories by remember { mutableStateOf(false) }
    var hasLoadedAssigned by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    val deleteState = rememberEntityDeleteState()

    val usersAtLocation = remember(users, locationId) {
        users.filter { it.location?.id == locationId }
    }

    fun reloadAssigned() {
        scope.launch {
            loadingAssets = true
            loadingAccessories = true
            coroutineScope {
                val assetsDeferred = async { viewModel.apiClient.fetchLocationAssets(locationId) }
                val accessoriesDeferred = async { viewModel.apiClient.fetchLocationAccessories(locationId) }
                locationAssets = assetsDeferred.await()
                locationAccessories = accessoriesDeferred.await()
            }
            loadingAssets = false
            loadingAccessories = false
            hasLoadedAssigned = true
        }
    }

    LaunchedEffect(locationId) {
        subtab = 0
        hasLoadedAssigned = false
        reloadAssigned()
    }

    val assetsTabTitle = if (hasLoadedAssigned) {
        L10n.string("assets_count", locationAssets.size)
    } else {
        L10n.string("tab_assets")
    }
    val accessoriesTabTitle = if (hasLoadedAssigned) {
        L10n.string("accessories_count", locationAccessories.size)
    } else {
        L10n.string("tab_accessories")
    }
    val tabs = listOf(
        L10n.string("users_count", usersAtLocation.size),
        assetsTabTitle,
        accessoriesTabTitle,
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        location?.let { locationCardTitle(it) } ?: L10n.string("location"),
                        maxLines = 1,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
                actions = {
                    DetailEntityToolbarActions(
                        baseUrl = viewModel.apiClient.baseUrl,
                        webPath = "locations/$locationId",
                        onDeleteClick = { deleteState.requestDelete() },
                        deleteEnabled = !deleteState.isDeleting,
                    )
                },
            )
        },
        bottomBar = {
            if (location != null) {
                DetailBottomBar(
                    actions = listOf(
                        DetailBarAction(L10n.string("edit"), SnipeOrange) { showEdit = true },
                    ),
                )
            }
        },
    ) { padding ->
        if (location == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("no_locations"))
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            LocationAddressSection(location = location)

            TabRow(selectedTabIndex = subtab) {
                tabs.forEachIndexed { index, label ->
                    Tab(
                        selected = subtab == index,
                        onClick = { subtab = index },
                        text = { Text(label, maxLines = 1) },
                    )
                }
            }

            when (subtab) {
                0 -> LocationUsersTab(
                    users = usersAtLocation,
                    onOpenUser = onOpenUser,
                )
                1 -> LocationAssetsTab(
                    assets = locationAssets,
                    isLoading = loadingAssets,
                    onOpenAsset = onOpenAsset,
                )
                else -> LocationAccessoriesTab(
                    accessories = locationAccessories,
                    isLoading = loadingAccessories,
                    onOpenAccessory = onOpenAccessory,
                )
            }
        }
    }

    if (showEdit && location != null) {
        EditLocationSheet(
            location = location,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
            onSaved = { reloadAssigned() },
        )
    }

    val locationName = location?.let { locationCardTitle(it) } ?: locationId.toString()
    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", locationName),
        confirmMessage = L10n.string("delete_location_confirm_message", locationName),
        onConfirmDelete = {
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteLocation(locationId) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = onBack,
            )
        },
    )
}

@Composable
private fun LocationAddressSection(location: Location) {
    val rows = buildList {
        location.parent?.name?.takeIf { it.isNotBlank() }?.let {
            add(L10n.string("parent_location") to HtmlDecoder.decode(it))
        }
        location.address?.takeIf { it.isNotBlank() }?.let { add(L10n.string("address") to it) }
        location.address2?.takeIf { it.isNotBlank() }?.let { add(L10n.string("address2") to it) }
        location.zip?.takeIf { it.isNotBlank() }?.let { add(L10n.string("zip") to it) }
        location.city?.takeIf { it.isNotBlank() }?.let { add(L10n.string("city") to it) }
        location.state?.takeIf { it.isNotBlank() }?.let { add(L10n.string("state") to it) }
        location.country?.takeIf { it.isNotBlank() }?.let { add(L10n.string("country") to it) }
        location.currency?.takeIf { it.isNotBlank() }?.let { add(L10n.string("currency") to it) }
    }
    if (rows.isEmpty()) return

    DetailSectionCard(
        title = L10n.string("location_details"),
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        rows.forEach { (label, value) ->
            DetailRow(label, value)
        }
    }
}

@Composable
private fun LocationUsersTab(
    users: List<User>,
    onOpenUser: ((Int) -> Unit)?,
) {
    if (users.isEmpty()) {
        EmptyState(
            title = L10n.string("no_users"),
            message = L10n.string("no_users_location"),
        )
        return
    }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        users.forEach { user ->
            UserCard(
                user = user,
                onClick = { onOpenUser?.invoke(user.id) },
            )
        }
    }
}

@Composable
private fun LocationAssetsTab(
    assets: List<Asset>,
    isLoading: Boolean,
    onOpenAsset: ((Int) -> Unit)?,
) {
    when {
        isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        assets.isEmpty() -> EmptyState(
            title = L10n.string("no_assets"),
            message = L10n.string("no_assets_location"),
        )
        else -> Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            assets.forEach { asset ->
                AssetCard(asset = asset, onClick = { onOpenAsset?.invoke(asset.id) })
            }
        }
    }
}

@Composable
private fun LocationAccessoriesTab(
    accessories: List<Accessory>,
    isLoading: Boolean,
    onOpenAccessory: ((Int) -> Unit)?,
) {
    when {
        isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        accessories.isEmpty() -> EmptyState(
            title = L10n.string("no_accessories"),
            message = L10n.string("no_accessories_location"),
        )
        else -> Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 8.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            accessories.forEach { accessory ->
                AccessoryCard(
                    accessory = accessory,
                    onClick = { onOpenAccessory?.invoke(accessory.id) },
                )
            }
        }
    }
}
