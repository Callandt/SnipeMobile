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
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Usb
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
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.accessory.AddAccessorySheet
import com.callandt.snipemobile.ui.components.AccessoryCard
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.components.ListCountHeader
import com.callandt.snipemobile.ui.components.ListFilterMenuButton
import com.callandt.snipemobile.ui.components.ListLoadingPlaceholder
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.components.SwipeToDeleteRow
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.components.rememberUserPullRefreshing
import com.callandt.snipemobile.ui.util.FilterDimension
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.ListFilter
import com.callandt.snipemobile.ui.util.accessoryMatchesSearch
import com.callandt.snipemobile.ui.util.listFilterOptions

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccessoriesTab(
    viewModel: AppViewModel,
    onAccessoryClick: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSettings: () -> Unit = {},
    onOpenScanner: () -> Unit = {},
) {
    val items by viewModel.accessories.collectAsState()
    val categories by viewModel.categories.collectAsState()
    val manufacturers by viewModel.manufacturers.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val refreshError by viewModel.refreshErrorMessage.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val hasCompletedInitialLoad by viewModel.hasCompletedInitialLoad.collectAsState()
    var searchQuery by remember { mutableStateOf("") }
    var listFilter by remember { mutableStateOf(ListFilter()) }
    var showAddAccessory by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var itemToDelete by remember { mutableStateOf<Accessory?>(null) }
    val deleteState = rememberEntityDeleteState()
    val (isUserRefreshing, onUserRefresh) = rememberUserPullRefreshing(isLoading) {
        viewModel.refresh()
    }

    val categoryTitle = L10n.string("category")
    val manufacturerTitle = L10n.string("manufacturer")
    val locationTitle = L10n.string("location")
    val dimensions = remember(categoryTitle, manufacturerTitle, locationTitle) {
        listOf<FilterDimension<Accessory>>(
            FilterDimension(categoryTitle) { it.decodedCategoryName },
            FilterDimension(manufacturerTitle) { it.decodedManufacturerName },
            FilterDimension(locationTitle) { it.decodedLocationName },
        )
    }
    val filterOptions = remember(items, categories, manufacturers, locations, dimensions) {
        listFilterOptions(
            dimensions = dimensions,
            catalogByTitle = mapOf(
                categoryTitle to viewModel.apiClient.categoriesFor("accessory").map { it.decodedName },
                manufacturerTitle to manufacturers.map { it.decodedName },
                locationTitle to locations.map { it.decodedName },
            ),
            items = items,
        )
    }
    val filtered = items
        .filter { listFilter.matches(it, dimensions) }
        .filter { accessoryMatchesSearch(it, searchQuery) }

    ErrorSnackbar(refreshError, snackbarHostState)

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            SearchTopBar(
                title = L10n.string("tab_accessories"),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                leadingActions = {
                    IconButton(onClick = { showAddAccessory = true }) {
                        Icon(Icons.Default.Add, contentDescription = L10n.string("add_accessory"))
                    }
                },
                actions = {
                    IconButton(onClick = onOpenScanner) {
                        Icon(Icons.Default.QrCodeScanner, contentDescription = L10n.string("scan_qr"))
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Default.Settings, contentDescription = L10n.string("settings"))
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
                    icon = Icons.Default.Usb,
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
                                title = L10n.string("no_accessories"),
                                icon = Icons.Default.Usb,
                            )
                        }
                        else -> {
                            LazyColumn(
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                items(filtered, key = { it.id }) { item ->
                                    SwipeToDeleteRow(
                                        onDeleteRequest = {
                                            itemToDelete = item
                                            deleteState.requestDelete()
                                        },
                                    ) {
                                        AccessoryCard(
                                            accessory = item,
                                            onClick = { onAccessoryClick(item.id) },
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

    if (showAddAccessory) {
        AddAccessorySheet(
            viewModel = viewModel,
            onDismiss = { showAddAccessory = false },
            onCreated = { viewModel.syncInBackground() },
        )
    }

    val pending = itemToDelete
    val name = pending?.decodedName ?: ""
    val needsCheckin = (pending?.checkoutsCount ?: 0) > 0 ||
        pending?.statusLabel?.statusMeta?.equals("deployed", ignoreCase = true) == true
    EntityDeleteSupport(
        state = deleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", name),
        confirmMessage = if (needsCheckin) {
            L10n.string("delete_item_confirm_message_with_checkin", name)
        } else {
            L10n.string("delete_item_confirm_message", name)
        },
        onConfirmDelete = {
            val id = pending?.id ?: return@EntityDeleteSupport
            deleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteAccessory(id) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = { itemToDelete = null },
            )
        },
    )
}
