package com.callandt.snipemobile.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.AssetAssignedComponent
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.asset.AssetAuditSheet
import com.callandt.snipemobile.ui.asset.AssetCheckinSheet
import com.callandt.snipemobile.ui.asset.AssetCheckoutSheet
import com.callandt.snipemobile.ui.asset.AssetFilesTab
import com.callandt.snipemobile.ui.asset.EditAssetSheet
import com.callandt.snipemobile.ui.asset.LabelPdfSupport
import com.callandt.snipemobile.ui.components.AccessoryCard
import com.callandt.snipemobile.ui.components.AssetCard
import com.callandt.snipemobile.ui.components.AssetCheckedOutBanner
import com.callandt.snipemobile.ui.components.ComponentCard
import com.callandt.snipemobile.ui.components.DetailRow
import com.callandt.snipemobile.ui.components.DetailCardListSection
import com.callandt.snipemobile.ui.components.DetailSectionCard
import com.callandt.snipemobile.ui.components.DetailEntityToolbarActions
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ItemHistoryTab
import com.callandt.snipemobile.ui.components.LicenseCard
import com.callandt.snipemobile.ui.components.LocationCard
import com.callandt.snipemobile.ui.components.MaintenanceCard
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.components.UserCard
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.maintenance.AddMaintenanceSheet
import com.callandt.snipemobile.ui.theme.SnipeGreen
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.theme.SnipeOrange
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.WarrantyHelper
import com.callandt.snipemobile.ui.util.assetCardLocationName
import com.callandt.snipemobile.ui.util.assetCheckedOutAssignee
import com.callandt.snipemobile.ui.util.assetCheckedOutIcon
import com.callandt.snipemobile.ui.util.assetResolvedStatus
import com.callandt.snipemobile.ui.util.resolveSnipeImageUrl
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

private enum class AssetDetailTab(val key: String) {
    Details("asset_tab_details"),
    Maintenance("asset_tab_maint"),
    Files("asset_tab_files"),
    History("asset_tab_history"),
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AssetDetailScreen(
    assetId: Int,
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenMaintenance: ((Int) -> Unit)? = null,
    onOpenUser: ((Int) -> Unit)? = null,
    onOpenLocation: ((Int) -> Unit)? = null,
    onOpenAsset: ((Int) -> Unit)? = null,
    onOpenAccessory: ((Int) -> Unit)? = null,
    onOpenLicense: ((Int) -> Unit)? = null,
    onOpenComponent: ((Int) -> Unit)? = null,
) {
    val context = LocalContext.current
    val assets by viewModel.assets.collectAsState()
    val users by viewModel.users.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val showMaintenancePref by viewModel.showMaintenanceSubtab.collectAsState()
    val asset = assets.firstOrNull { it.id == assetId }
    val scope = rememberCoroutineScope()

    var tabIndex by remember { mutableIntStateOf(0) }
    var showCheckout by remember { mutableStateOf(false) }
    var showCheckin by remember { mutableStateOf(false) }
    var showAudit by remember { mutableStateOf(false) }
    var showEdit by remember { mutableStateOf(false) }
    var showAddMaintenance by remember { mutableStateOf(false) }
    var maintenanceReloadToken by remember { mutableIntStateOf(0) }
    var isGeneratingLabel by remember { mutableStateOf(false) }
    var labelErrorMessage by remember { mutableStateOf<String?>(null) }
    val deleteState = rememberEntityDeleteState()

    suspend fun generateLabel() {
        val tag = asset?.decodedAssetTag?.trim().orEmpty()
        if (tag.isEmpty()) {
            labelErrorMessage = L10n.string("labels_no_asset_tags")
            return
        }
        isGeneratingLabel = true
        val bytes = viewModel.apiClient.generateAssetLabels(listOf(tag))
        isGeneratingLabel = false
        if (bytes == null) {
            labelErrorMessage = viewModel.apiClient.lastApiMessage.value ?: L10n.string("labels_generate_failed")
            return
        }
        val file = LabelPdfSupport.writeTemporaryPdf(context, bytes, "label-$tag")
        if (file == null || !LabelPdfSupport.openPdf(context, file)) {
            labelErrorMessage = L10n.string("labels_generate_failed")
        }
    }

    val tabs = buildList {
        add(AssetDetailTab.Details)
        if (showMaintenancePref) add(AssetDetailTab.Maintenance)
        add(AssetDetailTab.Files)
        add(AssetDetailTab.History)
    }
    val currentTab = tabs.getOrElse(tabIndex.coerceIn(0, tabs.lastIndex)) { AssetDetailTab.Details }

    LaunchedEffect(showMaintenancePref) {
        if (!showMaintenancePref && currentTab == AssetDetailTab.Maintenance) {
            tabIndex = 0
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        asset?.let {
                            it.decodedModelName.ifEmpty { it.decodedName.ifEmpty { it.decodedAssetTag } }
                        } ?: L10n.string("asset"),
                        maxLines = 1,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
                actions = {
                    if (currentTab == AssetDetailTab.Maintenance) {
                        IconButton(onClick = { showAddMaintenance = true }) {
                            Icon(
                                imageVector = Icons.Default.Add,
                                contentDescription = L10n.string("add_maintenance"),
                            )
                        }
                    }
                    if (!asset?.decodedAssetTag.isNullOrEmpty()) {
                        IconButton(
                            onClick = { scope.launch { generateLabel() } },
                            enabled = !isGeneratingLabel && !deleteState.isDeleting,
                        ) {
                            Icon(
                                imageVector = Icons.Default.QrCodeScanner,
                                contentDescription = L10n.string("print_label"),
                            )
                        }
                    }
                    DetailEntityToolbarActions(
                        baseUrl = viewModel.apiClient.baseUrl,
                        webPath = "hardware/$assetId",
                        onDeleteClick = { deleteState.requestDelete() },
                        deleteEnabled = !deleteState.isDeleting,
                    )
                },
            )
        },
        bottomBar = {
            if (asset != null) {
                AssetDetailBottomBar(
                    asset = asset,
                    onEdit = { showEdit = true },
                    onCheckout = { showCheckout = true },
                    onCheckin = { showCheckin = true },
                    onAudit = { showAudit = true },
                )
            }
        },
    ) { padding ->
        if (asset == null) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Text(L10n.string("asset_not_found_id", assetId.toString()))
            }
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            TabRow(selectedTabIndex = tabIndex.coerceIn(0, tabs.lastIndex)) {
                tabs.forEachIndexed { index, tab ->
                    Tab(
                        selected = tabIndex == index,
                        onClick = { tabIndex = index },
                        text = { Text(L10n.string(tab.key)) },
                    )
                }
            }

            when (currentTab) {
                AssetDetailTab.Details -> AssetDetailsTab(
                    asset = asset,
                    viewModel = viewModel,
                    onOpenUser = onOpenUser,
                    onOpenLocation = onOpenLocation,
                    onOpenAsset = onOpenAsset,
                    onOpenAccessory = onOpenAccessory,
                    onOpenLicense = onOpenLicense,
                    onOpenComponent = onOpenComponent,
                )
                AssetDetailTab.Maintenance -> AssetMaintenanceTab(
                    assetId = asset.id,
                    viewModel = viewModel,
                    reloadToken = maintenanceReloadToken,
                    onOpenMaintenance = onOpenMaintenance,
                    onAddMaintenance = { showAddMaintenance = true },
                )
                AssetDetailTab.Files -> AssetFilesTab(assetId = asset.id, viewModel = viewModel)
                AssetDetailTab.History -> ItemHistoryTab(
                    itemType = "asset",
                    itemId = asset.id,
                    viewModel = viewModel,
                )
            }
        }
    }

    if (showEdit && asset != null) {
        EditAssetSheet(
            asset = asset,
            viewModel = viewModel,
            onDismiss = { showEdit = false },
        )
    }

    if (showAddMaintenance && asset != null) {
        AddMaintenanceSheet(
            viewModel = viewModel,
            initialAssetId = asset.id,
            lockAssetSelection = true,
            onDismiss = { showAddMaintenance = false },
            onSaved = { _ -> maintenanceReloadToken += 1 },
        )
    }

    if (showCheckout && asset != null) {
        AssetCheckoutSheet(
            asset = asset,
            viewModel = viewModel,
            onDismiss = { showCheckout = false },
            onSuccess = { scope.launch { viewModel.apiClient.fetchAssets() } },
        )
    }

    if (showCheckin && asset != null) {
        AssetCheckinSheet(
            asset = asset,
            viewModel = viewModel,
            onDismiss = { showCheckin = false },
        )
    }

    if (showAudit && asset != null) {
        AssetAuditSheet(
            asset = asset,
            locations = locations.map { PickerItem(it.id, it.decodedName) },
            viewModel = viewModel,
            onDismiss = { showAudit = false },
            onSaved = { scope.launch { viewModel.apiClient.fetchAssets() } },
        )
    }

    labelErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { labelErrorMessage = null },
            title = { Text(L10n.string("generate_labels")) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { labelErrorMessage = null }) { Text(L10n.string("ok")) } },
        )
    }

    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_asset_confirm_title"),
        confirmMessage = if (asset?.assignedTo != null) {
            L10n.string("delete_asset_confirm_message_checked_out", asset.decodedAssetTag)
        } else {
            L10n.string("delete_asset_confirm_message", asset?.decodedAssetTag ?: assetId.toString())
        },
        onConfirmDelete = {
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteAsset(assetId) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = onBack,
            )
        },
    )
    }
}

@Composable
private fun AssetDetailsTab(
    asset: Asset,
    viewModel: AppViewModel,
    onOpenUser: ((Int) -> Unit)? = null,
    onOpenLocation: ((Int) -> Unit)? = null,
    onOpenAsset: ((Int) -> Unit)? = null,
    onOpenAccessory: ((Int) -> Unit)? = null,
    onOpenLicense: ((Int) -> Unit)? = null,
    onOpenComponent: ((Int) -> Unit)? = null,
) {
    val users by viewModel.users.collectAsState()
    val assets by viewModel.assets.collectAsState()
    val locations by viewModel.locations.collectAsState()
    var detailAsset by remember(asset.id) { mutableStateOf<Asset?>(null) }
    var assignedChildAssets by remember(asset.id) { mutableStateOf<List<Asset>>(emptyList()) }
    var assignedLicenses by remember(asset.id) { mutableStateOf<List<License>>(emptyList()) }
    var assignedAccessories by remember(asset.id) { mutableStateOf<List<Accessory>>(emptyList()) }
    var assignedComponents by remember(asset.id) { mutableStateOf<List<AssetAssignedComponent>>(emptyList()) }

    LaunchedEffect(asset.id) {
        detailAsset = viewModel.apiClient.fetchHardwareDetails(asset.id)
    }

    LaunchedEffect(asset.id) {
        coroutineScope {
            val childAssetsDeferred = async { viewModel.apiClient.fetchAssetAssignedAssets(asset.id) }
            val licensesDeferred = async { viewModel.apiClient.fetchAssetLicenses(asset.id) }
            val accessoriesDeferred = async { viewModel.apiClient.fetchAssetAccessories(asset.id) }
            val componentsDeferred = async { viewModel.apiClient.fetchAssetComponents(asset.id) }
            assignedChildAssets = childAssetsDeferred.await()
            assignedLicenses = licensesDeferred.await()
            assignedAccessories = accessoriesDeferred.await()
            assignedComponents = componentsDeferred.await()
        }
    }

    val assignee = assetCheckedOutAssignee(asset)
    val locationName = assetCardLocationName(asset)
    val status = assetResolvedStatus(asset)
    val imagePath = asset.image?.trim()?.takeIf { it.isNotEmpty() }
        ?: detailAsset?.image?.trim()?.takeIf { it.isNotEmpty() }
    val cacheBuster = asset.updatedAt?.datetime ?: asset.updatedAt?.date
        ?: detailAsset?.updatedAt?.datetime ?: detailAsset?.updatedAt?.date
    val imageUrl = resolveSnipeImageUrl(viewModel.apiClient.baseUrl, imagePath, cacheBuster)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (imageUrl != null) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = L10n.string("image"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                AsyncImage(
                    model = imageUrl,
                    contentDescription = L10n.string("image"),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 220.dp)
                        .clip(RoundedCornerShape(12.dp)),
                    contentScale = ContentScale.Fit,
                )
            }
        }

        DetailSectionCard(title = L10n.string("device_info")) {
            DetailRow(L10n.string("asset_tag"), asset.decodedAssetTag)
            DetailRow(L10n.string("serial_number"), asset.decodedSerial)
            if (asset.decodedName.isNotEmpty() && asset.decodedName != asset.decodedModelName) {
                DetailRow(L10n.string("name"), asset.decodedName)
            }
            DetailRow(L10n.string("model"), asset.decodedModelName)
            DetailRow(L10n.string("manufacturer"), asset.decodedManufacturerName)
            DetailRow(L10n.string("supplier"), asset.decodedSupplierName)
            DetailRow(L10n.string("status"), status)
            DetailRow(L10n.string("category"), asset.decodedCategoryName)
        }

        DetailSectionCard(title = L10n.string("location_details")) {
            DetailRow(L10n.string("location"), locationName ?: asset.decodedLocationName)
            DetailRow(L10n.string("company"), asset.decodedCompanyName)
        }

        asset.assignedTo?.let { assignedTo ->
            val showAssignedSection = asset.statusLabel.statusMeta?.equals("deployed", ignoreCase = true) == true ||
                !assignee.isNullOrEmpty()
            if (showAssignedSection) {
                DetailCardListSection(title = L10n.string("assigned_to")) {
                    when {
                        assignedTo.isUser -> {
                            val user = users.firstOrNull { it.id == assignedTo.id }
                            if (user != null) {
                                UserCard(
                                    user = user,
                                    onClick = { onOpenUser?.invoke(user.id) },
                                )
                            } else {
                                AssetCheckedOutBanner(
                                    assigneeName = assignee ?: assignedTo.decodedName,
                                    icon = assetCheckedOutIcon(asset),
                                    onClick = onOpenUser?.let { callback -> { callback(assignedTo.id) } },
                                )
                            }
                        }
                        assignedTo.isLocation -> {
                            val location = locations.firstOrNull { it.id == assignedTo.id }
                            if (location != null) {
                                LocationCard(
                                    location = location,
                                    onClick = { onOpenLocation?.invoke(location.id) },
                                )
                            } else {
                                AssetCheckedOutBanner(
                                    assigneeName = assignee ?: assignedTo.decodedName,
                                    icon = assetCheckedOutIcon(asset),
                                    onClick = onOpenLocation?.let { callback -> { callback(assignedTo.id) } },
                                )
                            }
                        }
                        assignedTo.isAsset -> {
                            val assignedAsset = assets.firstOrNull { it.id == assignedTo.id }
                            if (assignedAsset != null) {
                                AssetCard(
                                    asset = assignedAsset,
                                    onClick = { onOpenAsset?.invoke(assignedAsset.id) },
                                )
                            } else {
                                AssetCheckedOutBanner(
                                    assigneeName = assignee ?: assignedTo.decodedName,
                                    icon = assetCheckedOutIcon(asset),
                                    onClick = onOpenAsset?.let { callback -> { callback(assignedTo.id) } },
                                )
                            }
                        }
                        else -> {
                            AssetCheckedOutBanner(
                                assigneeName = assignee ?: assignedTo.decodedName,
                                icon = assetCheckedOutIcon(asset),
                            )
                        }
                    }
                }
            }
        }

        if (assignedChildAssets.isNotEmpty()) {
            DetailCardListSection(title = L10n.string("assigned_assets")) {
                    assignedChildAssets.forEach { child ->
                        AssetCard(asset = child, onClick = { onOpenAsset?.invoke(child.id) })
                    }
            }
        }

        if (assignedLicenses.isNotEmpty()) {
            DetailCardListSection(title = L10n.string("tab_licenses")) {
                    assignedLicenses.forEach { license ->
                        LicenseCard(license = license, onClick = { onOpenLicense?.invoke(license.id) })
                    }
            }
        }

        if (assignedAccessories.isNotEmpty()) {
            DetailCardListSection(title = L10n.string("tab_accessories")) {
                    assignedAccessories.forEach { accessory ->
                        AccessoryCard(accessory = accessory, onClick = { onOpenAccessory?.invoke(accessory.id) })
                    }
            }
        }

        if (assignedComponents.isNotEmpty()) {
            DetailCardListSection(title = L10n.string("tab_components")) {
                    assignedComponents.forEach { row ->
                        ComponentCard(
                            component = row.component,
                            onClick = { onOpenComponent?.invoke(row.component.id) },
                        )
                    }
            }
        }

        DetailSectionCard(title = L10n.string("dates")) {
            DetailRow(L10n.string("last_audit_date"), asset.lastAuditDate?.localizedDisplay())
            DetailRow(L10n.string("next_audit_date"), asset.nextAuditDate?.localizedDisplay())
            DetailRow(L10n.string("expected_checkin"), asset.expectedCheckin?.localizedDisplay())
            DetailRow(L10n.string("purchase_date"), asset.purchaseDate?.localizedDisplay())
            WarrantyExpiresRow(asset)
            DetailRow(L10n.string("eol_date"), asset.assetEolDate?.localizedDisplay())
        }

        DetailSectionCard(title = L10n.string("financial")) {
            DetailRow(L10n.string("purchase_cost"), asset.purchaseCost)
            DetailRow(L10n.string("book_value"), asset.bookValue)
            DetailRow(L10n.string("order_number"), asset.orderNumber)
            DetailRow(L10n.string("warranty_months"), asset.decodedWarrantyMonths)
        }

        if (asset.decodedNotes.isNotBlank()) {
            DetailSectionCard(title = L10n.string("notes")) {
                Text(asset.decodedNotes, style = MaterialTheme.typography.bodyLarge)
            }
        }

        val customFields = (detailAsset ?: asset).customFields
        val hasCustomFieldValues = customFields?.values?.any { it.decodedValue.isNotBlank() } == true
        if (hasCustomFieldValues) {
            DetailSectionCard(title = L10n.string("custom_fields")) {
                customFields.orEmpty().toSortedMap().forEach { (label, field) ->
                    DetailRow(label, field.decodedValue)
                }
            }
        }
    }
}

@Composable
private fun WarrantyExpiresRow(asset: Asset) {
    val expires = remember(asset) { WarrantyHelper.expiresDate(asset) } ?: return
    val expired = WarrantyHelper.isExpired(expires)
    val dateText = WarrantyHelper.formattedExpires(expires)
    val statusColor = if (expired) SnipeOrange else SnipeGreen
    val statusTitle = if (expired) {
        L10n.string("warranty_expired")
    } else {
        L10n.string("warranty_under_warranty")
    }
    val statusIcon = if (expired) Icons.Filled.Warning else Icons.Filled.VerifiedUser

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = L10n.string("warranty_expires"),
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (expired) {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = SnipeOrange,
                    modifier = Modifier.size(14.dp),
                )
            }
        }
        Text(
            text = dateText,
            style = MaterialTheme.typography.bodyLarge,
        )
        WarrantyStatusCapsule(
            icon = statusIcon,
            text = statusTitle,
            color = statusColor,
        )
    }
}

@Composable
private fun WarrantyStatusCapsule(
    icon: ImageVector,
    text: String,
    color: Color,
) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(12.dp),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
    }
}

@Composable
private fun AssetMaintenanceTab(
    assetId: Int,
    viewModel: AppViewModel,
    reloadToken: Int,
    onOpenMaintenance: ((Int) -> Unit)? = null,
    onAddMaintenance: () -> Unit,
) {
    var items by remember { mutableStateOf<List<AssetMaintenance>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(assetId, reloadToken) {
        loading = true
        items = viewModel.apiClient.fetchMaintenances(assetId).orEmpty()
            .sortedByDescending { it.startDate?.date.orEmpty() }
        loading = false
    }

    when {
        loading -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        items.isEmpty() -> {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = L10n.string("no_maintenance"),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = L10n.string("no_maintenance_desc"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
                TextButton(
                    onClick = onAddMaintenance,
                    modifier = Modifier.padding(top = 16.dp),
                ) {
                    Text(L10n.string("add_maintenance"))
                }
            }
        }
        else -> {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(items, key = { it.id }) { maintenance ->
                    MaintenanceCard(
                        record = maintenance,
                        showAssetHeader = false,
                        onClick = { onOpenMaintenance?.invoke(maintenance.id) },
                    )
                }
            }
        }
    }
}

@Composable
private fun AssetDetailBottomBar(
    asset: Asset,
    onEdit: () -> Unit,
    onCheckout: () -> Unit,
    onCheckin: () -> Unit,
    onAudit: () -> Unit,
) {
    val actions = asset.availableActions
    val showCheckin = actions?.checkin == true || isAssetDeployed(asset)
    val showCheckout = actions?.checkout == true || canAssetCheckOut(asset)
    val showAudit = actions?.audit == true

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .navigationBarsPadding(),
    ) {
        HorizontalDivider()
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            DetailActionButton(
                label = L10n.string("edit"),
                color = SnipeOrange,
                modifier = Modifier.weight(1f),
                onClick = onEdit,
            )
            if (showCheckin) {
                DetailActionButton(
                    label = L10n.string("check_in"),
                    color = SnipeGreen,
                    modifier = Modifier.weight(1f),
                    onClick = onCheckin,
                )
            } else if (showCheckout) {
                DetailActionButton(
                    label = L10n.string("check_out"),
                    color = SnipeAccent,
                    modifier = Modifier.weight(1f),
                    onClick = onCheckout,
                )
            }
            if (showAudit) {
                DetailActionButton(
                    label = L10n.string("audit"),
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.weight(1f),
                    onClick = onAudit,
                )
            }
        }
    }
}

@Composable
private fun DetailActionButton(
    label: String,
    color: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color),
    ) {
        Text(label, fontWeight = FontWeight.SemiBold)
    }
}

private fun isAssetDeployed(asset: Asset): Boolean {
    val meta = asset.statusLabel.statusMeta?.trim()?.lowercase().orEmpty()
    if (meta == "deployed") return true
    return asset.assignedTo != null && !asset.userCanCheckout
}

private fun canAssetCheckOut(asset: Asset): Boolean {
    if (isAssetDeployed(asset)) return false
    if (asset.userCanCheckout) return true
    if (asset.availableActions?.checkout == true) return true
    val meta = asset.statusLabel.statusMeta?.trim()?.lowercase().orEmpty()
    return meta == "deployable" || meta == "ready_to_deploy" || asset.statusLabel.isDeployableType
}

@Composable
fun SimpleNoteDialog(
    title: String,
    confirmLabel: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var note by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                label = { Text(L10n.string("note")) },
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = { TextButton(onClick = { onConfirm(note) }) { Text(confirmLabel) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(L10n.string("cancel")) } },
    )
}
