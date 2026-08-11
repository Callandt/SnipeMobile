package com.callandt.snipemobile.ui.main

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.component.AddComponentSheet
import com.callandt.snipemobile.ui.components.ComponentCard
import com.callandt.snipemobile.ui.components.ConsumableCard
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.consumable.AddConsumableSheet
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.componentMatchesSearch
import com.callandt.snipemobile.ui.util.consumableMatchesSearch

private enum class StockSubtab { Consumables, Components }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StockTab(
    viewModel: AppViewModel,
    onConsumableClick: (Int) -> Unit,
    onComponentClick: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSettings: () -> Unit = {},
    onOpenScanner: () -> Unit = {},
) {
    val consumables by viewModel.consumables.collectAsState()
    val components by viewModel.components.collectAsState()
    val showConsumables by viewModel.showConsumablesTab.collectAsState()
    val showComponents by viewModel.showComponentsTab.collectAsState()
    val refreshError by viewModel.refreshErrorMessage.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    var searchQuery by remember { mutableStateOf("") }
    var subtab by remember { mutableIntStateOf(0) }
    var showAddConsumable by remember { mutableStateOf(false) }
    var showAddComponent by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    val tabs = buildList {
        if (showConsumables) add(StockSubtab.Consumables)
        if (showComponents) add(StockSubtab.Components)
    }
    val currentSubtab = tabs.getOrElse(subtab) { StockSubtab.Consumables }
    val showConsumablesList = currentSubtab == StockSubtab.Consumables

    ErrorSnackbar(refreshError, snackbarHostState)

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            SearchTopBar(
                title = L10n.string("tab_stock"),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                leadingActions = {
                    IconButton(onClick = {
                        if (showConsumablesList) showAddConsumable = true else showAddComponent = true
                    }) {
                        Icon(Icons.Default.Add, contentDescription = L10n.string("add"))
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
            isRefreshing = isLoading,
            onRefresh = { viewModel.refresh() },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            androidx.compose.foundation.layout.Column(modifier = Modifier.fillMaxSize()) {
                if (tabs.size > 1) {
                    TabRow(selectedTabIndex = subtab.coerceIn(0, tabs.lastIndex)) {
                        tabs.forEachIndexed { index, tab ->
                            Tab(
                                selected = subtab == index,
                                onClick = { subtab = index },
                                text = {
                                    Text(
                                        when (tab) {
                                            StockSubtab.Consumables -> L10n.string("tab_consumables")
                                            StockSubtab.Components -> L10n.string("tab_components")
                                        },
                                    )
                                },
                            )
                        }
                    }
                }
                if (showConsumablesList) {
                    val filtered = consumables.filter {
                        consumableMatchesSearch(it, searchQuery)
                    }
                    if (filtered.isEmpty()) {
                        EmptyState(
                            title = L10n.string("no_consumables"),
                            icon = Icons.Outlined.Inventory2,
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            items(filtered, key = { it.id }) { item ->
                                ConsumableCard(
                                    consumable = item,
                                    onClick = { onConsumableClick(item.id) },
                                )
                            }
                        }
                    }
                } else {
                    val filtered = components.filter {
                        componentMatchesSearch(it, searchQuery)
                    }
                    if (filtered.isEmpty()) {
                        EmptyState(
                            title = L10n.string("no_components"),
                            icon = Icons.Outlined.Memory,
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            items(filtered, key = { it.id }) { item ->
                                ComponentCard(
                                    component = item,
                                    onClick = { onComponentClick(item.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showAddConsumable) {
        AddConsumableSheet(
            viewModel = viewModel,
            onDismiss = { showAddConsumable = false },
            onCreated = { viewModel.syncInBackground() },
        )
    }

    if (showAddComponent) {
        AddComponentSheet(
            viewModel = viewModel,
            onDismiss = { showAddComponent = false },
            onCreated = { viewModel.syncInBackground() },
        )
    }
}
