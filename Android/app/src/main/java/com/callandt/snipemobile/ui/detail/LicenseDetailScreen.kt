package com.callandt.snipemobile.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.data.model.LicenseSeatRow
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.ItemHistoryTab
import com.callandt.snipemobile.ui.components.DetailBarAction
import com.callandt.snipemobile.ui.components.DetailBottomBar
import com.callandt.snipemobile.ui.components.DetailEntityToolbarActions
import com.callandt.snipemobile.ui.components.DetailRow
import com.callandt.snipemobile.ui.components.DetailCardListSection
import com.callandt.snipemobile.ui.components.DetailSectionCard
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ItemCard
import com.callandt.snipemobile.ui.components.AssetCard
import com.callandt.snipemobile.ui.components.UserCard
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.license.EditLicenseSheet
import com.callandt.snipemobile.ui.license.LicenseCheckinConfirmDialog
import com.callandt.snipemobile.ui.license.LicenseCheckoutSheet
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

private enum class LicenseDetailTab(val key: String) {
    Details("asset_tab_details"),
    History("asset_tab_history"),
}

private data class CategorizedSeats(
    val assigned: List<LicenseSeatRow>,
    val free: List<LicenseSeatRow>,
    val consumed: List<LicenseSeatRow>,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LicenseDetailScreen(
    licenseId: Int,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenUser: ((Int) -> Unit)? = null,
    onOpenAsset: ((Int) -> Unit)? = null,
) {
    val licenses by viewModel.licenses.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val users by viewModel.users.collectAsState()
    val license = licenses.firstOrNull { it.id == licenseId }
    val scope = rememberCoroutineScope()

    var seats by remember { mutableStateOf<List<LicenseSeatRow>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var showProductKey by remember { mutableStateOf(false) }
    var showCheckout by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    var checkinTarget by remember { mutableStateOf<LicenseSeatRow?>(null) }
    var isCheckingIn by remember { mutableStateOf(false) }
    var tabIndex by remember { mutableIntStateOf(0) }
    val deleteState = rememberEntityDeleteState()

    fun reloadDetail() {
        scope.launch {
            loading = true
            seats = viewModel.apiClient.fetchLicenseSeats(licenseId)
            loading = false
        }
    }

    LaunchedEffect(licenseId) {
        reloadDetail()
    }

    val freeCount = license?.freeSeatsCount ?: license?.remaining ?: 0
    val canCheckout = freeCount > 0

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(license?.decodedName ?: L10n.string("category_type_license"), maxLines = 1) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
                actions = {
                    DetailEntityToolbarActions(
                        baseUrl = viewModel.apiClient.baseUrl,
                        webPath = "licenses/$licenseId",
                        onDeleteClick = { deleteState.requestDelete() },
                        deleteEnabled = !deleteState.isDeleting && !isCheckingIn,
                    )
                },
            )
        },
        bottomBar = {
            if (license != null) {
                DetailBottomBar(
                    actions = listOf(
                        DetailBarAction(
                            label = L10n.string("edit"),
                            color = SnipeOrange,
                            onClick = { showEdit = true },
                        ),
                        DetailBarAction(
                            label = L10n.string("check_out"),
                            color = SnipeAccent,
                            enabled = canCheckout,
                            onClick = { showCheckout = true },
                        ),
                    ),
                )
            }
        },
    ) { padding ->
        if (license == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("license_not_found_id", licenseId.toString()))
            }
            return@Scaffold
        }

        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            Column(modifier = Modifier.fillMaxSize()) {
                TabRow(selectedTabIndex = tabIndex) {
                    LicenseDetailTab.entries.forEachIndexed { index, tab ->
                        Tab(
                            selected = tabIndex == index,
                            onClick = { tabIndex = index },
                            text = { Text(L10n.string(tab.key)) },
                        )
                    }
                }
                when (LicenseDetailTab.entries[tabIndex]) {
                    LicenseDetailTab.Details -> LicenseDetailContent(
                        license = license,
                        seats = seats,
                        assets = assets,
                        users = users,
                        loading = loading,
                        showProductKey = showProductKey,
                        onToggleProductKey = { showProductKey = !showProductKey },
                        onCheckinSeat = { checkinTarget = it },
                        onOpenUser = onOpenUser,
                        onOpenAsset = onOpenAsset,
                    )
                    LicenseDetailTab.History -> ItemHistoryTab(
                        itemType = "license",
                        itemId = licenseId,
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

    if (showCheckout && license != null) {
        LicenseCheckoutSheet(
            license = license,
            availableSeats = seats,
            viewModel = viewModel,
            onDismiss = { showCheckout = false },
            onSuccess = { reloadDetail() },
        )
    }

    if (showEdit && license != null) {
        EditLicenseSheet(
            license = license,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
            onSaved = { reloadDetail() },
        )
    }

    checkinTarget?.let { seat ->
        val message = checkinMessageForSeat(seat, assets, users)
        LicenseCheckinConfirmDialog(
            message = message,
            warningUnreassignable = license?.reassignable == false,
            onDismiss = { checkinTarget = null },
            onConfirm = {
                checkinTarget = null
                isCheckingIn = true
                scope.launch {
                    viewModel.apiClient.checkinLicenseSeat(licenseId, seat.id)
                    reloadDetail()
                    isCheckingIn = false
                }
            },
        )
    }

    val licenseName = license?.decodedName ?: licenseId.toString()
    val hasAssignedSeats = seats.any { it.assignedUser != null || it.assignedAsset != null }
    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", licenseName),
        confirmMessage = if (hasAssignedSeats) {
            L10n.string("delete_item_confirm_message_with_checkin", licenseName)
        } else {
            L10n.string("delete_item_confirm_message", licenseName)
        },
        onConfirmDelete = {
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteLicense(licenseId) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = onBack,
            )
        },
    )
}

@Composable
private fun LicenseDetailContent(
    license: License,
    seats: List<LicenseSeatRow>,
    assets: List<com.callandt.snipemobile.data.model.Asset>,
    users: List<com.callandt.snipemobile.data.model.User>,
    loading: Boolean,
    showProductKey: Boolean,
    onToggleProductKey: () -> Unit,
    onCheckinSeat: (LicenseSeatRow) -> Unit,
    onOpenUser: ((Int) -> Unit)?,
    onOpenAsset: ((Int) -> Unit)?,
) {
    val groups = remember(seats, license) { categorizeSeats(seats, license) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        DetailSectionCard(title = L10n.string("license_info")) {
            DetailRow(L10n.string("name"), license.decodedName)
            DetailRow(L10n.string("manufacturer"), license.decodedManufacturerName)
            DetailRow(L10n.string("category"), license.decodedCategoryName)
            DetailRow(L10n.string("licensed_to"), license.decodedLicenseName)
            DetailRow(L10n.string("email"), license.decodedLicenseEmail)
            DetailRow(L10n.string("expiration_date"), license.expirationDate?.localizedDisplay())
            DetailRow(L10n.string("purchase_date"), license.purchaseDate?.localizedDisplay())
            DetailRow(L10n.string("purchase_price"), license.purchaseCost)
            DetailRow(L10n.string("order_number"), license.orderNumber)
            DetailRow(L10n.string("supplier"), license.decodedSupplierName)
            DetailRow(L10n.string("company"), license.decodedCompanyName)
            license.reassignable?.let {
                DetailRow(L10n.string("reassignable"), if (it) L10n.string("yes") else L10n.string("no"))
            }
            license.maintained?.let {
                DetailRow(L10n.string("maintained"), if (it) L10n.string("yes") else L10n.string("no"))
            }
            DetailRow(L10n.string("notes"), license.decodedNotes)
        }

        if (license.decodedProductKey.isNotEmpty()) {
            DetailSectionCard(title = L10n.string("product_key")) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(L10n.string("product_key"), fontWeight = FontWeight.Bold)
                    IconButton(onClick = onToggleProductKey) {
                        Icon(
                            if (showProductKey) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = null,
                        )
                    }
                }
                Text(
                    text = if (showProductKey) {
                        license.decodedProductKey
                    } else {
                        "•".repeat(maxOf(8, minOf(license.decodedProductKey.length, 24)))
                    },
                    fontFamily = FontFamily.Monospace,
                )
            }
        }

        val total = license.seats
        val free = license.freeSeatsCount ?: license.remaining
        if (total != null || free != null || license.minAmt != null) {
            DetailSectionCard(title = L10n.string("seats")) {
                total?.let { DetailRow(L10n.string("license_seats_total_label"), it.toString()) }
                free?.let { DetailRow(L10n.string("remaining"), it.toString()) }
                if (total != null && free != null) {
                    val assigned = groups.assigned.size
                    DetailRow(L10n.string("license_seats_assigned"), assigned.toString())
                    val used = maxOf(0, total - free)
                    LinearProgressIndicator(
                        progress = { used.toFloat() / maxOf(total, 1).toFloat() },
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    )
                }
                license.minAmt?.let { DetailRow(L10n.string("minimum_amount"), it.toString()) }
            }
        }

        DetailCardListSection(title = L10n.string("seats")) {
            if (loading) {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else if (seats.isEmpty()) {
                Text(L10n.string("no_details"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                if (groups.assigned.isNotEmpty()) {
                    SeatGroupHeader("license_seats_assigned", groups.assigned.size)
                    groups.assigned.forEach { seat ->
                        LicenseAssignedSeatCard(
                            seat = seat,
                            assets = assets,
                            users = users,
                            onCheckin = { onCheckinSeat(seat) },
                            onOpenUser = onOpenUser,
                            onOpenAsset = onOpenAsset,
                        )
                    }
                    Text(
                        text = L10n.string("license_seats_assigned_hint"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (groups.free.isNotEmpty()) {
                    SeatGroupHeader("license_seats_free", groups.free.size)
                    groups.free.forEach { _ ->
                        FreeSeatCard()
                    }
                }
                if (groups.consumed.isNotEmpty()) {
                    SeatGroupHeader("license_seats_consumed", groups.consumed.size)
                    groups.consumed.forEach { _ ->
                        ConsumedSeatCard()
                    }
                }
            }
        }
    }
}

@Composable
private fun SeatGroupHeader(titleKey: String, count: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "${L10n.string(titleKey)} ($count)",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun LicenseAssignedSeatCard(
    seat: LicenseSeatRow,
    assets: List<com.callandt.snipemobile.data.model.Asset>,
    users: List<com.callandt.snipemobile.data.model.User>,
    onCheckin: () -> Unit,
    onOpenUser: ((Int) -> Unit)?,
    onOpenAsset: ((Int) -> Unit)?,
) {
    val assignee = seat.resolvedAssignee(assets, users)
    val canCheckin = seat.userCanCheckin != false
    val onLongClick = onCheckin.takeIf { canCheckin }

    when {
        seat.assignedAsset != null -> {
            val assetId = seat.assignedAsset.id
            val fullAsset = assets.firstOrNull { it.id == assetId }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (fullAsset != null) {
                    AssetCard(
                        asset = fullAsset,
                        onClick = { onOpenAsset?.invoke(fullAsset.id) },
                        onLongClick = onLongClick,
                    )
                } else {
                    ItemCard(
                        title = seat.assignedAsset.decodedName.ifEmpty { L10n.string("asset") },
                        onClick = onOpenAsset?.let { callback -> { callback(assetId) } },
                        onLongClick = onLongClick,
                    )
                }
                assignee?.let { resolved ->
                    if (resolved.name.isNotEmpty()) {
                        Text(
                            text = resolved.name,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                    }
                    if (resolved.email.isNotEmpty()) {
                        Text(
                            text = resolved.email,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 4.dp),
                        )
                    }
                }
            }
        }
        seat.assignedUser != null -> {
            val userId = seat.assignedUser.id
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                val fullUser = users.firstOrNull { it.id == userId }
                if (fullUser != null) {
                    UserCard(
                        user = fullUser,
                        onClick = { onOpenUser?.invoke(fullUser.id) },
                        onLongClick = onLongClick,
                    )
                } else {
                    val fallbackName = seat.assignedUser.name
                        .let { com.callandt.snipemobile.util.HtmlDecoder.decode(it) }
                    ItemCard(
                        title = fallbackName.ifEmpty { L10n.string("user") },
                        subtitle = seat.assignedUser.email?.let {
                            com.callandt.snipemobile.util.HtmlDecoder.decode(it)
                        },
                        onClick = onOpenUser?.let { callback -> { callback(userId) } },
                        onLongClick = onLongClick,
                    )
                }
            }
        }
    }
}

@Composable
private fun FreeSeatCard() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Text(L10n.string("license_seats_free"), style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun ConsumedSeatCard() {
    ItemCard(
        title = L10n.string("license_seats_consumed"),
        statusLabel = L10n.string("license_seats_consumed"),
        onClick = null,
    )
}

private fun categorizeSeats(seats: List<LicenseSeatRow>, license: License): CategorizedSeats {
    val assigned = seats.filter { it.assignedUser != null || it.assignedAsset != null }
    val unassigned = seats.filter { it.assignedUser == null && it.assignedAsset == null }
    val free: List<LicenseSeatRow>
    val consumed: List<LicenseSeatRow>
    if (unassigned.any { it.disabled != null }) {
        free = unassigned.filter { it.disabled != true }
        consumed = unassigned.filter { it.disabled == true }
    } else {
        val reportedFree = license.freeSeatsCount ?: license.remaining ?: unassigned.size
        val freeCount = maxOf(0, minOf(reportedFree, unassigned.size))
        free = unassigned.take(freeCount)
        consumed = unassigned.drop(freeCount)
    }
    return CategorizedSeats(assigned, free, consumed)
}

private fun checkinMessageForSeat(
    seat: LicenseSeatRow,
    assets: List<com.callandt.snipemobile.data.model.Asset>,
    users: List<com.callandt.snipemobile.data.model.User>,
): String {
    seat.assignedAsset?.decodedName?.takeIf { it.isNotEmpty() }?.let {
        return L10n.string("checkin_user_confirm_message", it)
    }
    seat.assignedUser?.id?.let { userId ->
        users.firstOrNull { it.id == userId }?.decodedName?.let {
            return L10n.string("checkin_user_confirm_message", it)
        }
    }
    seat.assignedUser?.name?.takeIf { it.isNotEmpty() }?.let {
        return L10n.string("checkin_user_confirm_message", it)
    }
    return L10n.string("checkin_generic_confirm_message")
}
