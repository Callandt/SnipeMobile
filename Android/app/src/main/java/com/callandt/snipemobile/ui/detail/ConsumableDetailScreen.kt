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
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.data.model.ConsumableUserRow
import com.callandt.snipemobile.ui.AppViewModel
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
import com.callandt.snipemobile.ui.consumable.ConsumableCheckoutSheet
import com.callandt.snipemobile.ui.consumable.EditConsumableSheet
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.formatPurchaseDate
import com.callandt.snipemobile.util.HtmlDecoder
import kotlinx.coroutines.launch

private enum class ConsumableDetailTab(val key: String) {
    Details("asset_tab_details"),
    History("asset_tab_history"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConsumableDetailScreen(
    consumableId: Int,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenUser: ((Int) -> Unit)? = null,
) {
    val consumables by viewModel.consumables.collectAsState()
    val users by viewModel.users.collectAsState()
    val consumable = consumables.firstOrNull { it.id == consumableId }
    val scope = rememberCoroutineScope()

    var checkedOutRows by remember { mutableStateOf<List<ConsumableUserRow>>(emptyList()) }
    var loadingCheckedOut by remember { mutableStateOf(true) }
    var showCheckout by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    val deleteState = rememberEntityDeleteState()
    var tabIndex by remember { mutableIntStateOf(0) }

    fun reloadCheckedOut() {
        scope.launch {
            loadingCheckedOut = true
            checkedOutRows = viewModel.apiClient.fetchConsumableCheckedOutList(consumableId)
            viewModel.apiClient.fetchConsumableDetails(consumableId)
            loadingCheckedOut = false
        }
    }

    LaunchedEffect(consumableId) {
        reloadCheckedOut()
    }

    val canCheckout = consumable?.remaining?.let { it > 0 } ?: true

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        consumable?.decodedName ?: L10n.string("category_type_consumable"),
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
                        webPath = "consumables/$consumableId",
                        onDeleteClick = { deleteState.requestDelete() },
                        deleteEnabled = !deleteState.isDeleting,
                    )
                },
            )
        },
        bottomBar = {
            if (consumable != null) {
                DetailBottomBar(
                    actions = listOf(
                        DetailBarAction(L10n.string("edit"), SnipeOrange) { showEdit = true },
                        DetailBarAction(L10n.string("check_out"), SnipeAccent, enabled = canCheckout) { showCheckout = true },
                    ),
                )
            }
        },
    ) { padding ->
        if (consumable == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("consumable_not_found_id", consumableId.toString()))
            }
            return@Scaffold
        }

        ConsumableDetailContent(
            consumable = consumable,
            checkedOutRows = checkedOutRows,
            users = users,
            loadingCheckedOut = loadingCheckedOut,
            onOpenUser = onOpenUser,
            tabIndex = tabIndex,
            onTabSelected = { tabIndex = it },
            consumableId = consumableId,
            viewModel = viewModel,
            modifier = Modifier.padding(padding),
        )
    }

    if (showCheckout) {
        ConsumableCheckoutSheet(
            consumable = consumable!!,
            viewModel = viewModel,
            onDismiss = { showCheckout = false },
            onSuccess = { reloadCheckedOut() },
        )
    }

    if (showEdit && consumable != null) {
        EditConsumableSheet(
            consumable = consumable,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
            onSaved = { reloadCheckedOut() },
        )
    }

    val consumableName = consumable?.decodedName ?: consumableId.toString()
    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", consumableName),
        confirmMessage = L10n.string("delete_consumable_confirm_message", consumableName),
        onConfirmDelete = {
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteConsumable(consumableId) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = onBack,
            )
        },
    )
}

@Composable
private fun ConsumableDetailContent(
    consumable: Consumable,
    checkedOutRows: List<ConsumableUserRow>,
    users: List<com.callandt.snipemobile.data.model.User>,
    loadingCheckedOut: Boolean,
    onOpenUser: ((Int) -> Unit)?,
    tabIndex: Int,
    onTabSelected: (Int) -> Unit,
    consumableId: Int,
    viewModel: AppViewModel,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tabIndex) {
            ConsumableDetailTab.entries.forEachIndexed { index, tab ->
                Tab(
                    selected = tabIndex == index,
                    onClick = { onTabSelected(index) },
                    text = { Text(L10n.string(tab.key)) },
                )
            }
        }
        when (ConsumableDetailTab.entries[tabIndex]) {
            ConsumableDetailTab.Details -> ConsumableDetailsBody(
                consumable = consumable,
                checkedOutRows = checkedOutRows,
                users = users,
                loadingCheckedOut = loadingCheckedOut,
                onOpenUser = onOpenUser,
            )
            ConsumableDetailTab.History -> ItemHistoryTab(
                itemType = "consumable",
                itemId = consumableId,
                viewModel = viewModel,
            )
        }
    }
}

@Composable
private fun ConsumableDetailsBody(
    consumable: Consumable,
    checkedOutRows: List<ConsumableUserRow>,
    users: List<com.callandt.snipemobile.data.model.User>,
    loadingCheckedOut: Boolean,
    onOpenUser: ((Int) -> Unit)?,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!consumable.image.isNullOrBlank()) {
            ItemCard(title = consumable.decodedName, imageUrl = consumable.image)
        }

        DetailSectionCard(title = L10n.string("consumable_info")) {
            DetailRow(L10n.string("name"), consumable.decodedName)
            DetailRow(L10n.string("item_no"), consumable.decodedItemNo)
            DetailRow(L10n.string("model_number"), consumable.decodedModelNumber)
            DetailRow(L10n.string("category"), consumable.decodedCategoryName)
            DetailRow(L10n.string("location"), consumable.decodedLocationName)
            DetailRow(L10n.string("company"), consumable.decodedCompanyName)
        }

        if (consumable.qty != null || consumable.minAmt != null || consumable.remaining != null) {
            DetailSectionCard(title = L10n.string("stock_usage")) {
                consumable.qty?.let { DetailRow(L10n.string("total_quantity"), it.toString()) }
                consumable.minAmt?.let { DetailRow(L10n.string("minimum_amount"), it.toString()) }
                consumable.remaining?.let { DetailRow(L10n.string("remaining"), it.toString()) }
            }
        }

        consumable.notes?.takeIf { it.isNotBlank() }?.let { notes ->
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
                Text(L10n.string("assigned_to_none_consumable"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                    checkedOutRows.forEach { row ->
                        val fullUser = row.userId?.let { id -> users.find { it.id == id } }
                        val displayName = fullUser?.decodedName
                            ?: HtmlDecoder.decode(row.name ?: "")
                        AssetCheckedOutBanner(
                            assigneeName = displayName.ifEmpty { L10n.string("user") },
                            icon = Icons.Default.Person,
                            onClick = row.userId?.let { userId ->
                                onOpenUser?.let { callback -> { callback(userId) } }
                            },
                        )
            }
            }
        }

        val hasPurchase = consumable.decodedManufacturerName.isNotEmpty() ||
            !consumable.supplier?.name.isNullOrBlank() ||
            !consumable.purchaseDate.isNullOrBlank() ||
            !consumable.purchaseCost.isNullOrBlank() ||
            !consumable.orderNumber.isNullOrBlank()
        if (hasPurchase) {
            DetailSectionCard(title = L10n.string("purchase_only")) {
                DetailRow(L10n.string("manufacturer"), consumable.decodedManufacturerName)
                DetailRow(L10n.string("supplier"), consumable.supplier?.name)
                DetailRow(L10n.string("purchase_date"), formatPurchaseDate(consumable.purchaseDate))
                DetailRow(L10n.string("purchase_cost"), consumable.purchaseCost)
                DetailRow(L10n.string("order_number"), consumable.orderNumber)
            }
        }
    }
}
