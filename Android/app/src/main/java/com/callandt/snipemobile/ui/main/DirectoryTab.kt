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
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Place
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
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.components.LocationCard
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.components.UserCard
import com.callandt.snipemobile.ui.location.AddLocationSheet
import com.callandt.snipemobile.ui.user.AddUserSheet
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.locationMatchesSearch
import com.callandt.snipemobile.ui.util.userMatchesSearch

private enum class DirectorySubtab { Users, Locations }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DirectoryTab(
    viewModel: AppViewModel,
    onUserClick: (Int) -> Unit,
    onLocationClick: (Int) -> Unit,
    modifier: Modifier = Modifier,
    onOpenSettings: () -> Unit = {},
    onOpenScanner: () -> Unit = {},
) {
    val users by viewModel.users.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val refreshError by viewModel.refreshErrorMessage.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    var searchQuery by remember { mutableStateOf("") }
    var subtab by remember { mutableIntStateOf(0) }
    var showAddUser by remember { mutableStateOf(false) }
    var showAddLocation by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val tabs = listOf(DirectorySubtab.Users, DirectorySubtab.Locations)
    val currentSubtab = tabs[subtab.coerceIn(tabs.indices)]

    ErrorSnackbar(refreshError, snackbarHostState)

    Scaffold(
        modifier = modifier,
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            SearchTopBar(
                title = L10n.string("tab_directory"),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                leadingActions = {
                    IconButton(onClick = {
                        if (currentSubtab == DirectorySubtab.Users) showAddUser = true else showAddLocation = true
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
                TabRow(selectedTabIndex = subtab) {
                    tabs.forEachIndexed { index, tab ->
                        Tab(
                            selected = subtab == index,
                            onClick = { subtab = index },
                            text = {
                                Text(
                                    when (tab) {
                                        DirectorySubtab.Users -> L10n.string("tab_users")
                                        DirectorySubtab.Locations -> L10n.string("tab_locations")
                                    },
                                )
                            },
                        )
                    }
                }
                if (currentSubtab == DirectorySubtab.Users) {
                    val filtered = users.filter {
                        userMatchesSearch(it, searchQuery)
                    }
                    if (filtered.isEmpty()) {
                        EmptyState(
                            title = L10n.string("no_users"),
                            icon = Icons.Outlined.Groups,
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            items(filtered, key = { it.id }) { user ->
                                UserCard(
                                    user = user,
                                    onClick = { onUserClick(user.id) },
                                )
                            }
                        }
                    }
                } else {
                    val filtered = locations.filter {
                        locationMatchesSearch(it, searchQuery)
                    }
                    if (filtered.isEmpty()) {
                        EmptyState(
                            title = L10n.string("no_locations"),
                            icon = Icons.Outlined.Place,
                        )
                    } else {
                        LazyColumn(
                            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            items(filtered, key = { it.id }) { location ->
                                LocationCard(
                                    location = location,
                                    onClick = { onLocationClick(location.id) },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showAddUser) {
        AddUserSheet(
            viewModel = viewModel,
            onDismiss = { showAddUser = false },
            onCreated = { viewModel.syncInBackground() },
        )
    }

    if (showAddLocation) {
        AddLocationSheet(
            viewModel = viewModel,
            onDismiss = { showAddLocation = false },
            onCreated = { _, _ -> viewModel.syncInBackground() },
        )
    }
}
