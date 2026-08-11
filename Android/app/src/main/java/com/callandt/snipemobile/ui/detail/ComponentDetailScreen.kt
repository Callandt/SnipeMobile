package com.callandt.snipemobile.ui.detail

import androidx.compose.foundation.clickable
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
import com.callandt.snipemobile.data.model.Component
import com.callandt.snipemobile.data.model.ComponentAssetRow
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.component.ComponentCheckinConfirmDialog
import com.callandt.snipemobile.ui.component.ComponentCheckoutSheet
import com.callandt.snipemobile.ui.component.EditComponentSheet
import com.callandt.snipemobile.ui.components.AssetCheckedOutBanner
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
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.formatPurchaseDate
import com.callandt.snipemobile.util.HtmlDecoder
import kotlinx.coroutines.launch

private enum class ComponentDetailTab(val key: String) {
    Details("asset_tab_details"),
    History("asset_tab_history"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ComponentDetailScreen(
    componentId: Int,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenAsset: ((Int) -> Unit)? = null,
) {
    val components by viewModel.components.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val component = components.firstOrNull { it.id == componentId }
    val scope = rememberCoroutineScope()

    var checkedOutRows by remember { mutableStateOf<List<ComponentAssetRow>>(emptyList()) }
    var loadingCheckedOut by remember { mutableStateOf(true) }
    var showCheckout by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    var checkinTarget by remember { mutableStateOf<ComponentAssetRow?>(null) }
    var isCheckingIn by remember { mutableStateOf(false) }
    var checkinError by remember { mutableStateOf<String?>(null) }
    val deleteState = rememberEntityDeleteState()
    var tabIndex by remember { mutableIntStateOf(0) }

    fun reloadCheckedOut() {
        scope.launch {
            loadingCheckedOut = true
            checkedOutRows = viewModel.apiClient.fetchComponentAssetsList(componentId)
            viewModel.apiClient.fetchComponentDetails(componentId)
            loadingCheckedOut = false
        }
    }

    LaunchedEffect(componentId) {
        reloadCheckedOut()
    }

    val canCheckout = component?.remaining?.let { it > 0 } ?: true

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        component?.decodedName ?: L10n.string("category_type_component"),
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
                        webPath = "components/$componentId",
                        onDeleteClick = { deleteState.requestDelete() },
                        deleteEnabled = !deleteState.isDeleting && !isCheckingIn,
                    )
                },
            )
        },
        bottomBar = {
            if (component != null) {
                DetailBottomBar(
                    actions = listOf(
                        DetailBarAction(L10n.string("edit"), SnipeOrange) { showEdit = true },
                        DetailBarAction(L10n.string("check_out"), SnipeAccent, enabled = canCheckout) { showCheckout = true },
                    ),
                )
            }
        },
    ) { padding ->
        if (component == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("component_not_found_id", componentId.toString()))
            }
            return@Scaffold
        }

        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            Column(modifier = Modifier.fillMaxSize()) {
                TabRow(selectedTabIndex = tabIndex) {
                    ComponentDetailTab.entries.forEachIndexed { index, tab ->
                        Tab(
                            selected = tabIndex == index,
                            onClick = { tabIndex = index },
                            text = { Text(L10n.string(tab.key)) },
                        )
                    }
                }
                when (ComponentDetailTab.entries[tabIndex]) {
                    ComponentDetailTab.Details -> ComponentDetailContent(
                        component = component,
                        checkedOutRows = checkedOutRows,
                        assets = assets,
                        loadingCheckedOut = loadingCheckedOut,
                        onOpenAsset = onOpenAsset,
                        onCheckin = { checkinTarget = it },
                    )
                    ComponentDetailTab.History -> ItemHistoryTab(
                        itemType = "component",
                        itemId = componentId,
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

    if (showCheckout && component != null) {
        ComponentCheckoutSheet(
            component = component,
            viewModel = viewModel,
            onDismiss = { showCheckout = false },
            onSuccess = { reloadCheckedOut() },
        )
    }

    if (showEdit && component != null) {
        EditComponentSheet(
            component = component,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
            onSaved = { reloadCheckedOut() },
        )
    }

    checkinTarget?.let { row ->
        val assetName = row.decodedAssetName.ifEmpty { row.decodedAssetTag }
        ComponentCheckinConfirmDialog(
            assetName = assetName,
            onDismiss = { checkinTarget = null },
            onConfirm = {
                val pivotId = row.assignedPivotId ?: return@ComponentCheckinConfirmDialog
                checkinTarget = null
                isCheckingIn = true
                scope.launch {
                    val error = viewModel.apiClient.checkinComponent(
                        componentId = componentId,
                        componentAssetId = pivotId,
                        quantity = row.assignedQty ?: 1,
                    )
                    if (error != null) checkinError = error
                    reloadCheckedOut()
                    isCheckingIn = false
                }
            },
        )
    }

    checkinError?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { checkinError = null },
            title = { Text(L10n.string("checkin_failed")) },
            text = { Text(message) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { checkinError = null }) {
                    Text(L10n.string("ok"))
                }
            },
        )
    }

    val componentName = component?.decodedName ?: componentId.toString()
    val hasCheckedOutRows = checkedOutRows.any { it.assignedPivotId != null }
    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", componentName),
        confirmMessage = if (hasCheckedOutRows) {
            L10n.string("delete_component_confirm_message_with_checkin", componentName)
        } else {
            L10n.string("delete_item_confirm_message", componentName)
        },
        onConfirmDelete = {
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteComponent(componentId) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = onBack,
            )
        },
    )
}

@Composable
private fun ComponentDetailContent(
    component: Component,
    checkedOutRows: List<ComponentAssetRow>,
    assets: List<com.callandt.snipemobile.data.model.Asset>,
    loadingCheckedOut: Boolean,
    onOpenAsset: ((Int) -> Unit)?,
    onCheckin: (ComponentAssetRow) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!component.image.isNullOrBlank()) {
            ItemCard(title = component.decodedName, imageUrl = component.image)
        }

        DetailSectionCard(title = L10n.string("component_info")) {
            DetailRow(L10n.string("name"), component.decodedName)
            DetailRow(L10n.string("serial"), component.decodedSerial)
            DetailRow(L10n.string("model_number"), component.decodedModelNumber)
            DetailRow(L10n.string("category"), component.decodedCategoryName)
            DetailRow(L10n.string("location"), component.decodedLocationName)
            DetailRow(L10n.string("company"), component.decodedCompanyName)
        }

        if (component.qty != null || component.minAmt != null || component.remaining != null) {
            DetailSectionCard(title = L10n.string("stock_usage")) {
                component.qty?.let { DetailRow(L10n.string("total_quantity"), it.toString()) }
                component.minAmt?.let { DetailRow(L10n.string("minimum_amount"), it.toString()) }
                component.remaining?.let { DetailRow(L10n.string("remaining"), it.toString()) }
            }
        }

        component.notes?.takeIf { it.isNotBlank() }?.let { notes ->
            DetailSectionCard(title = L10n.string("notes")) {
                Text(notes, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        DetailCardListSection(title = L10n.string("checked_out_to")) {
            if (loadingCheckedOut) {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else if (checkedOutRows.isEmpty()) {
                Text(L10n.string("assigned_to_none_component"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                    checkedOutRows.forEach { row ->
                        val fullAsset = row.assetId?.let { id -> assets.find { it.id == id } }
                        val title = fullAsset?.decodedName
                            ?: HtmlDecoder.decode(row.assetName ?: "")
                        val tag = fullAsset?.decodedAssetTag ?: row.decodedAssetTag
                        val qty = row.assignedQty
                        val clickModifier = row.assetId?.let { assetId ->
                            onOpenAsset?.let { callback -> Modifier.clickable { callback(assetId) } }
                        } ?: Modifier
                        Column(modifier = clickModifier) {
                            AssetCheckedOutBanner(
                                assigneeName = title.ifEmpty { tag }.ifEmpty { L10n.string("asset") },
                                icon = Icons.Default.Laptop,
                            )
                            if (tag.isNotEmpty()) {
                                Text(
                                    text = L10n.string("tag_label", tag),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(start = 4.dp, top = 4.dp),
                                )
                            }
                            if (qty != null && qty > 1) {
                                Text(
                                    text = "${L10n.string("quantity")}: $qty",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(start = 4.dp, top = 2.dp),
                                )
                            }
                            if (row.assignedPivotId != null) {
                                androidx.compose.material3.TextButton(onClick = { onCheckin(row) }) {
                                    Text(L10n.string("check_in_lower"))
            }
                        }
                    }
                }
            }
        }

        val hasPurchase = component.decodedManufacturerName.isNotEmpty() ||
            !component.supplier?.name.isNullOrBlank() ||
            !component.purchaseDate.isNullOrBlank() ||
            !component.purchaseCost.isNullOrBlank() ||
            !component.orderNumber.isNullOrBlank()
        if (hasPurchase) {
            DetailSectionCard(title = L10n.string("purchase_only")) {
                DetailRow(L10n.string("manufacturer"), component.decodedManufacturerName)
                DetailRow(L10n.string("supplier"), component.supplier?.name)
                DetailRow(L10n.string("purchase_date"), formatPurchaseDate(component.purchaseDate))
                DetailRow(L10n.string("purchase_cost"), component.purchaseCost)
                DetailRow(L10n.string("order_number"), component.orderNumber)
            }
        }
    }
}
