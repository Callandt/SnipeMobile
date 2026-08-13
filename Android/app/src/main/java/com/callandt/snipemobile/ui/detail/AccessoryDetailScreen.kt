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
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import com.callandt.snipemobile.data.model.AccessoryCheckedOutRow
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.Location
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.accessory.AccessoryCheckinConfirmDialog
import com.callandt.snipemobile.ui.accessory.AccessoryCheckoutSheet
import com.callandt.snipemobile.ui.accessory.EditAccessorySheet
import com.callandt.snipemobile.ui.components.AssetCheckedOutBanner
import com.callandt.snipemobile.ui.components.AssetCard
import com.callandt.snipemobile.ui.components.ItemHistoryTab
import com.callandt.snipemobile.ui.components.DetailBarAction
import com.callandt.snipemobile.ui.components.DetailBottomBar
import com.callandt.snipemobile.ui.components.DetailEntityToolbarActions
import com.callandt.snipemobile.ui.components.DetailRow
import com.callandt.snipemobile.ui.components.DetailCardListSection
import com.callandt.snipemobile.ui.components.DetailSectionCard
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ItemCard
import com.callandt.snipemobile.ui.components.LocationCard
import com.callandt.snipemobile.ui.components.UserCard
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.theme.SnipeGreen
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.formatPurchaseDate
import kotlinx.coroutines.launch

private enum class AccessoryDetailTab(val key: String) {
    Details("asset_tab_details"),
    History("asset_tab_history"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccessoryDetailScreen(
    accessoryId: Int,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenUser: ((Int) -> Unit)? = null,
    onOpenLocation: ((Int) -> Unit)? = null,
    onOpenAsset: ((Int) -> Unit)? = null,
) {
    val accessories by viewModel.accessories.collectAsState()
    val users by viewModel.users.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val accessory = accessories.firstOrNull { it.id == accessoryId }
    val scope = rememberCoroutineScope()

    var checkedOutRows by remember { mutableStateOf<List<AccessoryCheckedOutRow>>(emptyList()) }
    var loadingCheckedOut by remember { mutableStateOf(true) }
    var showCheckout by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    var checkinTarget by remember { mutableStateOf<AccessoryCheckedOutRow?>(null) }
    var isCheckingIn by remember { mutableStateOf(false) }
    var tabIndex by remember { mutableIntStateOf(0) }
    val deleteState = rememberEntityDeleteState()

    fun reloadCheckedOut() {
        scope.launch {
            loadingCheckedOut = true
            checkedOutRows = viewModel.apiClient.fetchAccessoryCheckedOutList(accessoryId)
            viewModel.apiClient.fetchAccessoryDetails(accessoryId)
            loadingCheckedOut = false
        }
    }

    LaunchedEffect(accessoryId) {
        reloadCheckedOut()
    }

    val displayedRows = checkedOutRows.filter { it.assignedTo?.id != null }
    val isDeployed = accessory?.statusLabel?.statusMeta?.equals("deployed", ignoreCase = true) == true
    val canCheckout = accessory?.remaining?.let { it > 0 } ?: true
    val checkinRow = displayedRows.firstOrNull { it.availableActions?.checkin == true }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(accessory?.decodedName ?: L10n.string("category_type_accessory"), maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
                actions = {
                    DetailEntityToolbarActions(
                        baseUrl = viewModel.apiClient.baseUrl,
                        webPath = "accessories/$accessoryId",
                        onDeleteClick = { deleteState.requestDelete() },
                        deleteEnabled = !deleteState.isDeleting && !isCheckingIn,
                    )
                },
            )
        },
        bottomBar = {
            if (accessory != null) {
                val actions = buildList {
                    add(
                        DetailBarAction(
                            label = L10n.string("edit"),
                            color = SnipeOrange,
                            onClick = { showEdit = true },
                        ),
                    )
                    if (isDeployed && checkinRow != null) {
                        add(
                            DetailBarAction(
                                label = L10n.string("check_in"),
                                color = SnipeGreen,
                                onClick = { checkinTarget = checkinRow },
                            ),
                        )
                    } else {
                        add(
                            DetailBarAction(
                                label = L10n.string("check_out"),
                                color = SnipeAccent,
                                enabled = canCheckout,
                                onClick = { showCheckout = true },
                            ),
                        )
                    }
                }
                DetailBottomBar(actions = actions)
            }
        },
    ) { padding ->
        if (accessory == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("accessory_not_found_id", accessoryId.toString()))
            }
            return@Scaffold
        }

        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            Column(modifier = Modifier.fillMaxSize()) {
                TabRow(selectedTabIndex = tabIndex) {
                    AccessoryDetailTab.entries.forEachIndexed { index, tab ->
                        Tab(
                            selected = tabIndex == index,
                            onClick = { tabIndex = index },
                            text = { Text(L10n.string(tab.key)) },
                        )
                    }
                }
                when (AccessoryDetailTab.entries[tabIndex]) {
                    AccessoryDetailTab.Details -> AccessoryDetailContent(
                        accessory = accessory,
                        checkedOutRows = displayedRows,
                        loadingCheckedOut = loadingCheckedOut,
                        users = users,
                        assets = assets,
                        locations = locations,
                        onCheckinRow = { checkinTarget = it },
                        onOpenUser = onOpenUser,
                        onOpenLocation = onOpenLocation,
                        onOpenAsset = onOpenAsset,
                    )
                    AccessoryDetailTab.History -> ItemHistoryTab(
                        itemType = "accessory",
                        itemId = accessoryId,
                        viewModel = viewModel,
                    )
                }
            }
            if (isCheckingIn) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
        }
    }

    if (showCheckout && accessory != null) {
        AccessoryCheckoutSheet(
            accessory = accessory,
            viewModel = viewModel,
            onDismiss = { showCheckout = false },
            onSuccess = { reloadCheckedOut() },
        )
    }

    if (showEdit && accessory != null) {
        EditAccessorySheet(
            accessory = accessory,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
            onSaved = { reloadCheckedOut() },
        )
    }

    checkinTarget?.let { row ->
        AccessoryCheckinConfirmDialog(
            assigneeName = row.assignedTo?.decodedName.orEmpty(),
            onDismiss = { checkinTarget = null },
            onConfirm = {
                val checkedoutId = row.id ?: return@AccessoryCheckinConfirmDialog
                checkinTarget = null
                isCheckingIn = true
                scope.launch {
                    viewModel.apiClient.checkinAccessory(accessoryId, checkedoutId)
                    reloadCheckedOut()
                    isCheckingIn = false
                }
            },
        )
    }

    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", accessory?.decodedName ?: accessoryId.toString()),
        confirmMessage = if (
            (accessory?.checkoutsCount ?: 0) > 0 ||
            accessory?.statusLabel?.statusMeta?.equals("deployed", ignoreCase = true) == true
        ) {
            L10n.string("delete_item_confirm_message_with_checkin", accessory?.decodedName ?: accessoryId.toString())
        } else {
            L10n.string("delete_item_confirm_message", accessory?.decodedName ?: accessoryId.toString())
        },
        onConfirmDelete = {
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteAccessory(accessoryId) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = onBack,
            )
        },
    )
}

@Composable
private fun AccessoryDetailContent(
    accessory: Accessory,
    checkedOutRows: List<AccessoryCheckedOutRow>,
    loadingCheckedOut: Boolean,
    users: List<User>,
    assets: List<Asset>,
    locations: List<Location>,
    onCheckinRow: (AccessoryCheckedOutRow) -> Unit,
    onOpenUser: ((Int) -> Unit)?,
    onOpenLocation: ((Int) -> Unit)?,
    onOpenAsset: ((Int) -> Unit)?,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!accessory.image.isNullOrBlank()) {
            ItemCard(title = accessory.decodedName, imageUrl = accessory.image)
        }

        DetailSectionCard(title = L10n.string("accessory_info")) {
            DetailRow(L10n.string("name"), accessory.decodedName)
            DetailRow(L10n.string("asset_tag"), accessory.decodedAssetTag)
            accessory.modelNumber?.takeIf { it.isNotBlank() }?.let { DetailRow(L10n.string("model_number"), it) }
            accessory.statusLabel?.statusMeta?.takeIf { it.isNotBlank() }?.let { DetailRow(L10n.string("status"), it) }
            DetailRow(L10n.string("location"), accessory.decodedLocationName)
            DetailRow(L10n.string("category"), accessory.decodedCategoryName)
            DetailRow(L10n.string("company"), accessory.company?.name)
        }

        accessory.decodedNotes.takeIf { it.isNotBlank() }?.let { notes ->
            DetailSectionCard(title = L10n.string("notes")) {
                Text(notes, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        if (accessory.qty != null || accessory.minAmt != null || accessory.remaining != null ||
            accessory.checkoutsCount != null
        ) {
            DetailSectionCard(title = L10n.string("stock_usage")) {
                accessory.qty?.let { DetailRow(L10n.string("total_quantity"), it.toString()) }
                accessory.minAmt?.let { DetailRow(L10n.string("minimum_amount"), it.toString()) }
                accessory.remaining?.let { DetailRow(L10n.string("asset_available_short"), it.toString()) }
                accessory.checkoutsCount?.let { DetailRow(L10n.string("checkouts_count"), it.toString()) }
            }
        }

        DetailCardListSection(title = L10n.string("assigned_to")) {
            if (loadingCheckedOut) {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else if (checkedOutRows.isEmpty()) {
                Text(
                    L10n.string("none"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                checkedOutRows.forEach { row ->
                    AccessoryCheckedOutRowCard(
                        row = row,
                        users = users,
                        assets = assets,
                        locations = locations,
                        onCheckin = { onCheckinRow(row) }.takeIf { row.availableActions?.checkin == true },
                        onOpenUser = onOpenUser,
                        onOpenLocation = onOpenLocation,
                        onOpenAsset = onOpenAsset,
                    )
                }
                if (checkedOutRows.any { it.availableActions?.checkin == true }) {
                    Text(
                        text = L10n.string("assigned_checkin_hint"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        val hasPurchase = accessory.decodedManufacturerName.isNotEmpty() ||
            !accessory.supplier?.name.isNullOrBlank() ||
            !accessory.purchaseDate.isNullOrBlank() ||
            !accessory.purchaseCost.isNullOrBlank() ||
            !accessory.orderNumber.isNullOrBlank()
        if (hasPurchase) {
            DetailSectionCard(title = L10n.string("purchase_only")) {
                DetailRow(L10n.string("manufacturer"), accessory.decodedManufacturerName)
                DetailRow(L10n.string("supplier"), accessory.supplier?.name)
                DetailRow(L10n.string("purchase_date"), formatPurchaseDate(accessory.purchaseDate))
                DetailRow(L10n.string("purchase_price"), accessory.purchaseCost)
                DetailRow(L10n.string("order_number"), accessory.orderNumber)
            }
        }
    }
}

@Composable
private fun AccessoryCheckedOutRowCard(
    row: AccessoryCheckedOutRow,
    users: List<User>,
    assets: List<Asset>,
    locations: List<Location>,
    onOpenUser: ((Int) -> Unit)?,
    onOpenLocation: ((Int) -> Unit)?,
    onOpenAsset: ((Int) -> Unit)?,
    onCheckin: (() -> Unit)?,
) {
    val assigned = row.assignedTo ?: return
    val assigneeId = assigned.id ?: return

    when {
        assigned.isUser -> {
            val user = users.firstOrNull { it.id == assigneeId }
            if (user != null) {
                UserCard(
                    user = user,
                    onClick = { onOpenUser?.invoke(user.id) },
                    onLongClick = onCheckin,
                )
            } else {
                AssetCheckedOutBanner(
                    assigneeName = assigned.decodedName.ifEmpty { L10n.string("user") },
                    icon = Icons.Default.Person,
                    onClick = onOpenUser?.let { callback -> { callback(assigneeId) } },
                    onLongClick = onCheckin,
                )
            }
        }
        assigned.isLocation -> {
            val location = locations.firstOrNull { it.id == assigneeId }
            if (location != null) {
                LocationCard(
                    location = location,
                    onClick = { onOpenLocation?.invoke(location.id) },
                    onLongClick = onCheckin,
                )
            } else {
                AssetCheckedOutBanner(
                    assigneeName = assigned.decodedName.ifEmpty { L10n.string("location") },
                    icon = Icons.Default.LocationOn,
                    onClick = onOpenLocation?.let { callback -> { callback(assigneeId) } },
                    onLongClick = onCheckin,
                )
            }
        }
        assigned.isAsset -> {
            val asset = assets.firstOrNull { it.id == assigneeId }
            if (asset != null) {
                AssetCard(
                    asset = asset,
                    onClick = { onOpenAsset?.invoke(asset.id) },
                    onLongClick = onCheckin,
                )
            } else {
                Column {
                    AssetCheckedOutBanner(
                        assigneeName = when {
                            assigned.decodedModel.isNotEmpty() -> assigned.decodedModel
                            else -> assigned.decodedName.ifEmpty { L10n.string("asset") }
                        },
                        icon = Icons.Default.Laptop,
                        onClick = onOpenAsset?.let { callback -> { callback(assigneeId) } },
                        onLongClick = onCheckin,
                    )
                    if (assigned.decodedAssetTag.isNotEmpty()) {
                        Text(
                            text = L10n.string("tag_label", assigned.decodedAssetTag),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 4.dp, top = 4.dp),
                        )
                    }
                }
            }
        }
        else -> {
            AssetCheckedOutBanner(
                assigneeName = assigned.decodedName.ifEmpty { L10n.string("user") },
                icon = Icons.Default.Person,
                onLongClick = onCheckin,
            )
        }
    }
}
