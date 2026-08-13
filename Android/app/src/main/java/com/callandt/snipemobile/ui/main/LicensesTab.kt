package com.callandt.snipemobile.ui.main

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.components.LicenseCard
import com.callandt.snipemobile.ui.components.ListCountHeader
import com.callandt.snipemobile.ui.components.ListFilterMenuButton
import com.callandt.snipemobile.ui.components.ListLoadingPlaceholder
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.components.SwipeToDeleteRow
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.components.rememberUserPullRefreshing
import com.callandt.snipemobile.ui.license.AddLicenseSheet
import com.callandt.snipemobile.ui.util.FilterDimension
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.ListFilter
import com.callandt.snipemobile.ui.util.WindowAdaptive
import com.callandt.snipemobile.ui.util.licenseMatchesSearch
import com.callandt.snipemobile.ui.util.listFilterOptions

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LicensesTab(
    viewModel: AppViewModel,
    onLicenseClick: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSettings: () -> Unit = {},
    onOpenScanner: () -> Unit = {},
) {
    val items by viewModel.licenses.collectAsState()
    val categories by viewModel.categories.collectAsState()
    val manufacturers by viewModel.manufacturers.collectAsState()
    val suppliers by viewModel.suppliers.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val refreshError by viewModel.refreshErrorMessage.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val hasCompletedInitialLoad by viewModel.hasCompletedInitialLoad.collectAsState()
    var searchQuery by remember { mutableStateOf("") }
    var listFilter by remember { mutableStateOf(ListFilter()) }
    var showAddLicense by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var itemToDelete by remember { mutableStateOf<License?>(null) }
    val deleteState = rememberEntityDeleteState()
    val (isUserRefreshing, onUserRefresh) = rememberUserPullRefreshing(isLoading) {
        viewModel.refresh()
    }

    val categoryTitle = L10n.string("category")
    val manufacturerTitle = L10n.string("manufacturer")
    val supplierTitle = L10n.string("supplier")
    val companyTitle = L10n.string("company")
    val dimensions = remember(categoryTitle, manufacturerTitle, supplierTitle, companyTitle) {
        listOf<FilterDimension<License>>(
            FilterDimension(categoryTitle) { it.decodedCategoryName },
            FilterDimension(manufacturerTitle) { it.decodedManufacturerName },
            FilterDimension(supplierTitle) { it.decodedSupplierName },
            FilterDimension(companyTitle) { it.decodedCompanyName },
        )
    }
    val filterOptions = remember(items, categories, manufacturers, suppliers, companies, dimensions) {
        listFilterOptions(
            dimensions = dimensions,
            catalogByTitle = mapOf(
                categoryTitle to viewModel.apiClient.categoriesFor("license").map { it.decodedName },
                manufacturerTitle to manufacturers.map { it.decodedName },
                supplierTitle to suppliers.map { it.decodedName },
                companyTitle to companies.map { it.decodedName },
            ),
            items = items,
        )
    }
    val filtered = items
        .filter { listFilter.matches(it, dimensions) }
        .filter { licenseMatchesSearch(it, searchQuery) }

    ErrorSnackbar(refreshError, snackbarHostState, onDismiss = { viewModel.clearRefreshError() })

    val isTablet = WindowAdaptive.isTabletLayout()

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            SearchTopBar(
                title = L10n.string("tab_licenses"),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                leadingActions = {
                    if (!isTablet) {
                        IconButton(onClick = { showAddLicense = true }) {
                            Icon(Icons.Default.Add, contentDescription = L10n.string("add_license"))
                        }
                    }
                },
                actions = {
                    if (isTablet) {
                        IconButton(onClick = { showAddLicense = true }) {
                            Icon(Icons.Default.Add, contentDescription = L10n.string("add_license"))
                        }
                    } else {
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
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isUserRefreshing,
            onRefresh = onUserRefresh,
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                ListCountHeader(
                    count = filtered.size,
                    icon = Icons.Default.Description,
                    trailing = {
                        ListFilterMenuButton(
                            filter = listFilter,
                            options = filterOptions,
                            onFilterChange = { listFilter = it },
                            showLabel = true,
                        )
                    },
                )
                Box(modifier = Modifier.weight(1f)) {
                    when {
                        filtered.isEmpty() && isLoading && !hasCompletedInitialLoad -> {
                            ListLoadingPlaceholder()
                        }
                        filtered.isEmpty() -> {
                            EmptyState(
                                title = L10n.string("no_licenses"),
                                icon = Icons.Default.Description,
                            )
                        }
                        else -> {
                            LazyColumn(
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                items(filtered, key = { it.id }) { license ->
                                    SwipeToDeleteRow(
                                        onDeleteRequest = {
                                            itemToDelete = license
                                            deleteState.requestDelete()
                                        },
                                    ) {
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

    if (showAddLicense) {
        AddLicenseSheet(
            viewModel = viewModel,
            onDismiss = { showAddLicense = false },
            onCreated = { id -> id?.let(onLicenseClick) },
        )
    }

    val pending = itemToDelete
    val name = pending?.decodedName ?: ""
    val seats = pending?.seats ?: 0
    val free = pending?.freeSeatsCount ?: pending?.remaining ?: seats
    val hasAssignments = seats > free
    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", name),
        confirmMessage = if (hasAssignments) {
            L10n.string("delete_item_confirm_message_with_checkin", name)
        } else {
            L10n.string("delete_item_confirm_message", name)
        },
        onConfirmDelete = {
            val id = pending?.id ?: return@EntityDeleteSupport
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteLicense(id) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = { itemToDelete = null },
            )
        },
    )
}
