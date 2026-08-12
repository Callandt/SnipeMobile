package com.callandt.snipemobile.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Sell
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.DellAddPrefill
import com.callandt.snipemobile.ui.asset.AddAssetSheet
import com.callandt.snipemobile.ui.asset.BulkAuditSheet
import com.callandt.snipemobile.ui.asset.BulkLabelSheet
import com.callandt.snipemobile.ui.components.AssetCard
import com.callandt.snipemobile.ui.components.AssetFilterMenuButton
import com.callandt.snipemobile.ui.components.CompactSubtabRow
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.components.ListCountHeader
import com.callandt.snipemobile.ui.components.ListLoadingPlaceholder
import com.callandt.snipemobile.ui.components.MaintenanceCard
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.components.SwipeToDeleteRow
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.components.rememberUserPullRefreshing
import com.callandt.snipemobile.ui.maintenance.BulkMaintenanceFormSheet
import com.callandt.snipemobile.ui.theme.SnipeGreen
import com.callandt.snipemobile.ui.util.AssetFilter
import com.callandt.snipemobile.ui.util.AssetFilterOptions
import com.callandt.snipemobile.ui.util.AuditDateHelper
import com.callandt.snipemobile.ui.util.AuditListFilter
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.assetMatchesSearch
import com.callandt.snipemobile.ui.util.maintenanceMatchesSearch
import kotlinx.coroutines.launch

private enum class HardwareSubtab { All, Audit, Maintenance }

/** Maintenance status filter for the hardware tab. */
private enum class MaintenanceStatusFilter {
    All,
    InProgress,
    Completed,
    ;

    fun title(): String = when (this) {
        All -> L10n.string("filter_all")
        InProgress -> L10n.string("in_progress")
        Completed -> L10n.string("status_completed")
    }

    fun matches(record: AssetMaintenance): Boolean = when (this) {
        All -> true
        InProgress -> !record.isCompleted
        Completed -> record.isCompleted
    }

    companion object {
        fun available(records: List<AssetMaintenance>): List<MaintenanceStatusFilter> = buildList {
            add(All)
            if (records.any { !it.isCompleted }) add(InProgress)
            if (records.any { it.isCompleted }) add(Completed)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HardwareTab(
    viewModel: AppViewModel,
    onAssetClick: (Int) -> Unit,
    onMaintenanceClick: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSettings: () -> Unit = {},
    onOpenScanner: () -> Unit = {},
    pendingDellAdd: DellAddPrefill? = null,
    onClearPendingDellAdd: () -> Unit = {},
) {
    val assets by viewModel.assets.collectAsState()
    val maintenances by viewModel.maintenances.collectAsState()
    val showAudit by viewModel.showAuditSubtab.collectAsState()
    val showMaintenance by viewModel.showMaintenanceSubtab.collectAsState()
    val statusLabels by viewModel.statusLabels.collectAsState()
    val refreshError by viewModel.refreshErrorMessage.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val hasCompletedInitialLoad by viewModel.hasCompletedInitialLoad.collectAsState()
    val lastApiMessage by viewModel.lastApiMessage.collectAsState()
    val scope = rememberCoroutineScope()
    val (isUserRefreshing, onUserRefresh) = rememberUserPullRefreshing(isLoading) {
        viewModel.refresh()
    }

    var searchQuery by rememberSaveable { mutableStateOf("") }
    var subtabIndex by rememberSaveable { mutableIntStateOf(0) }
    var assetFilter by remember { mutableStateOf(AssetFilter()) }
    var maintenanceFilter by remember { mutableStateOf(MaintenanceStatusFilter.All) }
    var showMaintenanceFilterMenu by remember { mutableStateOf(false) }
    var showAddAsset by remember { mutableStateOf(false) }
    var showBulkMaintenance by remember { mutableStateOf(false) }
    var showBulkAudit by remember { mutableStateOf(false) }
    var showBulkLabels by remember { mutableStateOf(false) }
    var showAddMenu by remember { mutableStateOf(false) }
    var dellPrefill by remember { mutableStateOf<DellAddPrefill?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }

    var isSelectingMaintenances by remember { mutableStateOf(false) }
    var selectedMaintenanceIds by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var maintenanceToComplete by remember { mutableStateOf<AssetMaintenance?>(null) }
    var completeNote by remember { mutableStateOf("") }
    var showBulkCompleteConfirm by remember { mutableStateOf(false) }
    var isCompleting by remember { mutableStateOf(false) }
    var completeErrorMessage by remember { mutableStateOf<String?>(null) }

    var assetToDelete by remember { mutableStateOf<Asset?>(null) }
    val assetDeleteState = rememberEntityDeleteState()

    LaunchedEffect(pendingDellAdd) {
        if (pendingDellAdd != null) {
            dellPrefill = pendingDellAdd
        }
    }

    val filterOptions = remember(assets, statusLabels) {
        AssetFilterOptions.from(assets, statusLabels)
    }

    val subtabs = buildList {
        add(HardwareSubtab.All)
        if (showAudit) add(HardwareSubtab.Audit)
        if (showMaintenance) add(HardwareSubtab.Maintenance)
    }
    val currentSubtab = subtabs.getOrElse(subtabIndex) { HardwareSubtab.All }

    val pendingAudit by viewModel.pendingAuditNavigation.collectAsState()
    val pendingHardwareSubtab by viewModel.pendingHardwareSubtab.collectAsState()

    LaunchedEffect(pendingHardwareSubtab, showAudit, showMaintenance, subtabs) {
        val intent = viewModel.consumePendingHardwareSubtab() ?: return@LaunchedEffect
        val target = when (intent) {
            com.callandt.snipemobile.ui.HardwareSubtabIntent.Assets -> HardwareSubtab.All
            com.callandt.snipemobile.ui.HardwareSubtabIntent.Audit ->
                if (showAudit) HardwareSubtab.Audit else null
            com.callandt.snipemobile.ui.HardwareSubtabIntent.Maintenance ->
                if (showMaintenance) HardwareSubtab.Maintenance else null
        } ?: return@LaunchedEffect
        val index = subtabs.indexOf(target)
        if (index >= 0) subtabIndex = index
    }

    LaunchedEffect(pendingAudit, showAudit, subtabs) {
        if (pendingAudit == com.callandt.snipemobile.ui.AuditNavigationIntent.OpenDueToday && showAudit) {
            val auditIndex = subtabs.indexOf(HardwareSubtab.Audit)
            if (auditIndex >= 0) subtabIndex = auditIndex
            viewModel.consumePendingAuditNavigation()
        }
    }

    LaunchedEffect(currentSubtab) {
        if (currentSubtab != HardwareSubtab.Maintenance) {
            isSelectingMaintenances = false
            selectedMaintenanceIds = emptySet()
            completeNote = ""
        }
    }

    val searchableAssets = remember(assets, searchQuery, assetFilter, statusLabels) {
        assets
            .filter { assetFilter.matches(it, statusLabels) }
            .filter { assetMatchesSearch(it, searchQuery) }
    }

    val filteredAssets = remember(searchableAssets, currentSubtab) {
        when (currentSubtab) {
            HardwareSubtab.All -> searchableAssets
            HardwareSubtab.Audit -> AuditDateHelper.filterAssets(searchableAssets, AuditListFilter.All)
            HardwareSubtab.Maintenance -> emptyList()
        }
    }

    val overdueAssets = remember(searchableAssets) { AuditDateHelper.overdueAssets(searchableAssets) }
    val dueTodayAssets = remember(searchableAssets) { AuditDateHelper.dueTodayAssets(searchableAssets) }
    val dueSoonAssets = remember(searchableAssets) { AuditDateHelper.dueSoonAssets(searchableAssets) }

    val maintenanceChoices = remember(maintenances) { MaintenanceStatusFilter.available(maintenances) }
    LaunchedEffect(maintenanceChoices, maintenanceFilter) {
        if (maintenanceFilter !in maintenanceChoices) {
            maintenanceFilter = MaintenanceStatusFilter.All
        }
    }

    val displayedMaintenances = remember(maintenances, maintenanceFilter, searchQuery) {
        maintenances
            .filter { maintenanceFilter.matches(it) }
            .filter { maintenanceMatchesSearch(it, searchQuery) }
    }
    val selectableMaintenances = remember(displayedMaintenances) {
        displayedMaintenances.filter { !it.isCompleted }
    }
    val isMaintenanceSubtab = currentSubtab == HardwareSubtab.Maintenance

    fun cancelMaintenanceSelection() {
        isSelectingMaintenances = false
        selectedMaintenanceIds = emptySet()
        completeNote = ""
    }

    ErrorSnackbar(refreshError, snackbarHostState, onDismiss = { viewModel.clearRefreshError() })

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            SearchTopBar(
                title = L10n.string("tab_assets"),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                leadingActions = {
                    when (currentSubtab) {
                        HardwareSubtab.All, HardwareSubtab.Audit -> {
                            Box {
                                IconButton(onClick = { showAddMenu = true }) {
                                    Icon(Icons.Default.Add, contentDescription = L10n.string("add"))
                                }
                                DropdownMenu(expanded = showAddMenu, onDismissRequest = { showAddMenu = false }) {
                                    DropdownMenuItem(
                                        text = { Text(L10n.string("add_asset")) },
                                        leadingIcon = { Icon(Icons.Default.Laptop, contentDescription = null) },
                                        onClick = {
                                            showAddMenu = false
                                            showAddAsset = true
                                        },
                                    )
                                    if (showMaintenance) {
                                        DropdownMenuItem(
                                            text = { Text(L10n.string("add_maintenance")) },
                                            leadingIcon = { Icon(Icons.Default.Build, contentDescription = null) },
                                            onClick = {
                                                showAddMenu = false
                                                showBulkMaintenance = true
                                            },
                                        )
                                    }
                                    if (showAudit) {
                                        DropdownMenuItem(
                                            text = { Text(L10n.string("add_audit")) },
                                            leadingIcon = { Icon(Icons.Default.Checklist, contentDescription = null) },
                                            onClick = {
                                                showAddMenu = false
                                                showBulkAudit = true
                                            },
                                        )
                                    }
                                    DropdownMenuItem(
                                        text = { Text(L10n.string("generate_labels")) },
                                        leadingIcon = { Icon(Icons.Default.Sell, contentDescription = null) },
                                        onClick = {
                                            showAddMenu = false
                                            showBulkLabels = true
                                        },
                                    )
                                }
                            }
                        }
                        HardwareSubtab.Maintenance -> {
                            if (isSelectingMaintenances) {
                                TextButton(onClick = { cancelMaintenanceSelection() }) {
                                    Text(L10n.string("cancel"))
                                }
                            } else {
                                IconButton(onClick = { showBulkMaintenance = true }) {
                                    Icon(Icons.Default.Add, contentDescription = L10n.string("add_maintenance"))
                                }
                            }
                        }
                    }
                },
                actions = {
                    when (currentSubtab) {
                        HardwareSubtab.Maintenance -> {
                            if (isSelectingMaintenances) {
                                TextButton(
                                    onClick = {
                                        selectedMaintenanceIds = selectableMaintenances.map { it.id }.toSet()
                                    },
                                    enabled = selectableMaintenances.isNotEmpty(),
                                ) {
                                    Text(L10n.string("select_all"))
                                }
                            } else if (selectableMaintenances.isNotEmpty()) {
                                TextButton(onClick = { isSelectingMaintenances = true }) {
                                    Text(L10n.string("select"))
                                }
                            }
                        }
                        else -> Unit
                    }
                    if (!(isMaintenanceSubtab && isSelectingMaintenances)) {
                        IconButton(onClick = onOpenScanner) {
                            Icon(Icons.Default.QrCodeScanner, contentDescription = L10n.string("scan_qr"))
                        }
                        IconButton(onClick = onOpenSettings) {
                            Icon(Icons.Default.Settings, contentDescription = L10n.string("settings"))
                        }
                    }
                },
            )
        },
        bottomBar = {
            if (isMaintenanceSubtab && isSelectingMaintenances && selectedMaintenanceIds.isNotEmpty()) {
                Button(
                    onClick = {
                        completeNote = ""
                        showBulkCompleteConfirm = true
                    },
                    enabled = !isCompleting,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = SnipeGreen),
                ) {
                    Text(L10n.string("mark_complete_selected", selectedMaintenanceIds.size))
                }
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            PullToRefreshBox(
                isRefreshing = isUserRefreshing,
                onRefresh = onUserRefresh,
                modifier = Modifier.fillMaxSize(),
            ) {
                Column(modifier = Modifier.fillMaxSize()) {
                    if (subtabs.size > 1) {
                        CompactSubtabRow(
                            selectedIndex = subtabIndex.coerceIn(0, subtabs.lastIndex),
                            titles = subtabs.map { tab ->
                                when (tab) {
                                    HardwareSubtab.All -> L10n.string("tab_assets")
                                    HardwareSubtab.Audit -> L10n.string("audit")
                                    HardwareSubtab.Maintenance -> L10n.string("maintenance")
                                }
                            },
                            onSelect = { subtabIndex = it },
                        )
                    }

                    when (currentSubtab) {
                        HardwareSubtab.All -> ListCountHeader(
                            count = searchableAssets.size,
                            icon = Icons.Default.Laptop,
                            trailing = if (filterOptions.hasFilterOptions) {
                                {
                                    AssetFilterMenuButton(
                                        filter = assetFilter,
                                        options = filterOptions,
                                        onFilterChange = { assetFilter = it },
                                        showLabel = true,
                                    )
                                }
                            } else {
                                null
                            },
                        )
                        HardwareSubtab.Audit -> ListCountHeader(
                            count = overdueAssets.size + dueTodayAssets.size + dueSoonAssets.size,
                            icon = Icons.Default.Checklist,
                        )
                        HardwareSubtab.Maintenance -> ListCountHeader(
                            count = displayedMaintenances.size,
                            icon = Icons.Default.Build,
                            trailing = if (!isSelectingMaintenances && maintenanceChoices.size > 1) {
                                {
                                    Box {
                                        TextButton(onClick = { showMaintenanceFilterMenu = true }) {
                                            Text(
                                                if (maintenanceFilter == MaintenanceStatusFilter.All) {
                                                    L10n.string("filter")
                                                } else {
                                                    maintenanceFilter.title()
                                                },
                                                color = MaterialTheme.colorScheme.primary,
                                            )
                                            Icon(
                                                Icons.Default.FilterList,
                                                contentDescription = null,
                                                tint = MaterialTheme.colorScheme.primary,
                                                modifier = Modifier.padding(start = 4.dp),
                                            )
                                        }
                                        DropdownMenu(
                                            expanded = showMaintenanceFilterMenu,
                                            onDismissRequest = { showMaintenanceFilterMenu = false },
                                        ) {
                                            maintenanceChoices.forEach { choice ->
                                                DropdownMenuItem(
                                                    text = { Text(choice.title()) },
                                                    onClick = {
                                                        maintenanceFilter = choice
                                                        showMaintenanceFilterMenu = false
                                                    },
                                                )
                                            }
                                        }
                                    }
                                }
                            } else {
                                null
                            },
                        )
                    }

                    Box(modifier = Modifier.weight(1f)) {
                        when (currentSubtab) {
                            HardwareSubtab.Maintenance -> {
                                if (displayedMaintenances.isEmpty()) {
                                    EmptyState(
                                        title = L10n.string("no_maintenance"),
                                        message = L10n.string("no_maintenance_overview_desc"),
                                        icon = Icons.Default.Settings,
                                    )
                                } else {
                                    LazyColumn(
                                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                                        verticalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        items(displayedMaintenances, key = { it.id }) { item ->
                                            val linked = item.assetId?.let { id ->
                                                assets.firstOrNull { it.id == id }
                                            }
                                            MaintenanceOverviewRow(
                                                record = item,
                                                linkedAsset = linked,
                                                isSelecting = isSelectingMaintenances,
                                                isSelected = selectedMaintenanceIds.contains(item.id),
                                                onClick = {
                                                    if (isSelectingMaintenances) {
                                                        if (item.isCompleted) return@MaintenanceOverviewRow
                                                        selectedMaintenanceIds =
                                                            if (selectedMaintenanceIds.contains(item.id)) {
                                                                selectedMaintenanceIds - item.id
                                                            } else {
                                                                selectedMaintenanceIds + item.id
                                                            }
                                                    } else {
                                                        onMaintenanceClick(item.id)
                                                    }
                                                },
                                                onRequestComplete = {
                                                    completeNote = ""
                                                    maintenanceToComplete = item
                                                },
                                            )
                                        }
                                    }
                                }
                            }
                            HardwareSubtab.Audit -> {
                                AuditOverviewList(
                                    overdue = overdueAssets,
                                    dueToday = dueTodayAssets,
                                    dueSoon = dueSoonAssets,
                                    onAssetClick = onAssetClick,
                                )
                            }
                            HardwareSubtab.All -> AssetList(
                                assets = filteredAssets,
                                onAssetClick = onAssetClick,
                                onRequestDelete = { asset ->
                                    assetToDelete = asset
                                    assetDeleteState.requestDelete()
                                },
                                showNextAudit = false,
                                isFiltered = searchQuery.isNotBlank() || assetFilter.isActive,
                                showLoadingPlaceholder = isLoading && filteredAssets.isEmpty() &&
                                    !hasCompletedInitialLoad,
                            )
                        }
                    }
                }
            }

            if (isCompleting) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.25f)),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
        }
    }

    if (showAddAsset) {
        AddAssetSheet(
            viewModel = viewModel,
            onDismiss = {
                showAddAsset = false
                dellPrefill = null
                onClearPendingDellAdd()
            },
            onCreated = { viewModel.syncInBackground() },
            prefilledDellUrl = dellPrefill?.url,
            prefilledSerial = dellPrefill?.serial,
        )
    }

    dellPrefill?.let { prefill ->
        if (!showAddAsset) {
            AlertDialog(
                onDismissRequest = {
                    dellPrefill = null
                    onClearPendingDellAdd()
                },
                title = { Text(L10n.string("dell_asset_not_found_title")) },
                text = { Text(L10n.string("dell_asset_not_found_message", prefill.serial)) },
                confirmButton = {
                    TextButton(onClick = { showAddAsset = true }) {
                        Text(L10n.string("dell_asset_not_found_add"))
                    }
                },
                dismissButton = {
                    TextButton(onClick = {
                        dellPrefill = null
                        onClearPendingDellAdd()
                    }) {
                        Text(L10n.string("cancel"))
                    }
                },
            )
        }
    }

    if (showBulkMaintenance) {
        BulkMaintenanceFormSheet(
            viewModel = viewModel,
            onDismiss = { showBulkMaintenance = false },
            onSaved = { viewModel.syncInBackground() },
        )
    }

    if (showBulkAudit) {
        BulkAuditSheet(
            viewModel = viewModel,
            onDismiss = { showBulkAudit = false },
            onSaved = { viewModel.syncInBackground() },
        )
    }

    if (showBulkLabels) {
        BulkLabelSheet(
            viewModel = viewModel,
            onDismiss = { showBulkLabels = false },
        )
    }

    maintenanceToComplete?.let { record ->
        AlertDialog(
            onDismissRequest = { if (!isCompleting) maintenanceToComplete = null },
            title = { Text(L10n.string("mark_complete_confirm_title")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(L10n.string("mark_complete_confirm_message"))
                    OutlinedTextField(
                        value = completeNote,
                        onValueChange = { completeNote = it },
                        label = { Text(L10n.string("note_optional")) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        isCompleting = true
                        scope.launch {
                            val ok = viewModel.apiClient.completeMaintenance(
                                id = record.id,
                                note = completeNote.trim().takeIf { it.isNotEmpty() },
                            )
                            isCompleting = false
                            if (ok) {
                                maintenanceToComplete = null
                                completeNote = ""
                                viewModel.syncInBackground()
                            } else {
                                completeErrorMessage = lastApiMessage ?: L10n.string("error")
                            }
                        }
                    },
                    enabled = !isCompleting,
                ) { Text(L10n.string("mark_complete")) }
            },
            dismissButton = {
                TextButton(
                    onClick = { maintenanceToComplete = null },
                    enabled = !isCompleting,
                ) { Text(L10n.string("cancel")) }
            },
        )
    }

    if (showBulkCompleteConfirm) {
        AlertDialog(
            onDismissRequest = { if (!isCompleting) showBulkCompleteConfirm = false },
            title = { Text(L10n.string("mark_complete_confirm_title")) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(L10n.string("bulk_mark_complete_confirm_message", selectedMaintenanceIds.size))
                    OutlinedTextField(
                        value = completeNote,
                        onValueChange = { completeNote = it },
                        label = { Text(L10n.string("note_optional")) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 2,
                    )
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val ids = selectedMaintenanceIds
                        if (ids.isEmpty()) return@TextButton
                        isCompleting = true
                        showBulkCompleteConfirm = false
                        scope.launch {
                            var failed = 0
                            var lastError: String? = null
                            val note = completeNote.trim().takeIf { it.isNotEmpty() }
                            for (id in ids) {
                                val ok = viewModel.apiClient.completeMaintenance(id, note)
                                if (!ok) {
                                    failed += 1
                                    lastError = viewModel.lastApiMessage.value
                                }
                            }
                            viewModel.syncInBackground()
                            isCompleting = false
                            if (failed == 0) {
                                cancelMaintenanceSelection()
                            } else {
                                val base = L10n.string("bulk_maintenance_complete_failed", failed)
                                completeErrorMessage = lastError?.let { "$base\n$it" } ?: base
                                if (failed < ids.size) {
                                    cancelMaintenanceSelection()
                                }
                            }
                        }
                    },
                    enabled = !isCompleting,
                ) { Text(L10n.string("mark_complete")) }
            },
            dismissButton = {
                TextButton(
                    onClick = { showBulkCompleteConfirm = false },
                    enabled = !isCompleting,
                ) { Text(L10n.string("cancel")) }
            },
        )
    }

    completeErrorMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { completeErrorMessage = null },
            title = { Text(L10n.string("error")) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { completeErrorMessage = null }) {
                    Text(L10n.string("ok"))
                }
            },
        )
    }

    val pendingDelete = assetToDelete
    EntityDeleteSupport(
        state = assetDeleteState,
        confirmTitle = L10n.string("delete_asset_confirm_title"),
        confirmMessage = if (pendingDelete?.assignedTo != null) {
            L10n.string(
                "delete_asset_confirm_message_checked_out",
                pendingDelete.decodedAssetTag,
            )
        } else {
            L10n.string(
                "delete_asset_confirm_message",
                pendingDelete?.decodedAssetTag ?: "",
            )
        },
        onConfirmDelete = {
            val id = pendingDelete?.id ?: return@EntityDeleteSupport
            assetDeleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteAsset(id) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = { assetToDelete = null },
            )
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MaintenanceOverviewRow(
    record: AssetMaintenance,
    linkedAsset: Asset?,
    isSelecting: Boolean,
    isSelected: Boolean,
    onClick: () -> Unit,
    onRequestComplete: () -> Unit,
) {
    val rowModifier = if (isSelecting && record.isCompleted) {
        Modifier.alpha(0.45f)
    } else {
        Modifier
    }

    Row(
        modifier = rowModifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (isSelecting) {
            Checkbox(
                checked = isSelected,
                onCheckedChange = { if (!record.isCompleted) onClick() },
                enabled = !record.isCompleted,
            )
        }

        val cardModifier = Modifier.weight(1f)
        if (isSelecting || record.isCompleted) {
            MaintenanceCard(
                record = record,
                linkedAsset = linkedAsset,
                showAssetHeader = true,
                onClick = onClick,
                modifier = cardModifier,
            )
        } else {
            key(record.id) {
                val dismissState = rememberSwipeToDismissBoxState(
                    confirmValueChange = { value ->
                        if (value == SwipeToDismissBoxValue.EndToStart) {
                            onRequestComplete()
                        }
                        false
                    },
                )
                SwipeToDismissBox(
                    state = dismissState,
                    // Same radius as MaintenanceCard so swipe green doesn't peek at corners.
                    modifier = cardModifier.clip(RoundedCornerShape(18.dp)),
                    enableDismissFromStartToEnd = false,
                    enableDismissFromEndToStart = true,
                    backgroundContent = {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(SnipeGreen)
                                .padding(horizontal = 20.dp),
                            contentAlignment = Alignment.CenterEnd,
                        ) {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = L10n.string("mark_complete"),
                                tint = Color.White,
                            )
                        }
                    },
                ) {
                    MaintenanceCard(
                        record = record,
                        linkedAsset = linkedAsset,
                        showAssetHeader = true,
                        onClick = onClick,
                    )
                }
            }
        }
    }
}

/** Audit list grouped by due date. */
@Composable
private fun AuditOverviewList(
    overdue: List<Asset>,
    dueToday: List<Asset>,
    dueSoon: List<Asset>,
    onAssetClick: (Int) -> Unit,
) {
    if (overdue.isEmpty() && dueToday.isEmpty() && dueSoon.isEmpty()) {
        EmptyState(
            title = L10n.string("audit_empty_title"),
            message = L10n.string("audit_empty_message"),
            icon = Icons.Default.Checklist,
        )
        return
    }

    LazyColumn(
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (overdue.isNotEmpty()) {
            item { AuditSectionHeader(L10n.string("audit_overdue_header", overdue.size)) }
            items(overdue, key = { "overdue-${it.id}" }) { asset ->
                AssetCard(asset = asset, onClick = { onAssetClick(asset.id) }, showNextAuditDate = true)
            }
        }
        if (dueToday.isNotEmpty()) {
            item { AuditSectionHeader(L10n.string("audit_due_today_header", dueToday.size)) }
            items(dueToday, key = { "today-${it.id}" }) { asset ->
                AssetCard(asset = asset, onClick = { onAssetClick(asset.id) }, showNextAuditDate = true)
            }
        }
        if (dueSoon.isNotEmpty()) {
            item {
                Column(modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp)) {
                    Text(
                        L10n.string("audit_due_soon_header", dueSoon.size),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        L10n.string("audit_due_soon_within_days", 7),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            items(dueSoon, key = { "soon-${it.id}" }) { asset ->
                AssetCard(asset = asset, onClick = { onAssetClick(asset.id) }, showNextAuditDate = true)
            }
        }
    }
}

@Composable
private fun AuditSectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
    )
}

@Composable
private fun AssetList(
    assets: List<Asset>,
    onAssetClick: (Int) -> Unit,
    onRequestDelete: (Asset) -> Unit,
    showNextAudit: Boolean,
    isFiltered: Boolean,
    showLoadingPlaceholder: Boolean = false,
) {
    if (assets.isEmpty()) {
        if (showLoadingPlaceholder) {
            ListLoadingPlaceholder()
            return
        }
        EmptyState(
            title = if (isFiltered) L10n.string("no_assets_match") else L10n.string("no_assets"),
            message = null,
            icon = Icons.Default.Laptop,
        )
        return
    }
    LazyColumn(
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        items(assets, key = { it.id }) { asset ->
            SwipeToDeleteRow(
                onDeleteRequest = { onRequestDelete(asset) },
            ) {
                AssetCard(
                    asset = asset,
                    onClick = { onAssetClick(asset.id) },
                    showNextAuditDate = showNextAudit,
                )
            }
        }
    }
}
