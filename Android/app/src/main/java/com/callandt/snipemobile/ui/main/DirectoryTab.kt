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
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Place
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Location
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.CompactSubtabRow
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.EntityDeleteSupport
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.components.ListCountHeader
import com.callandt.snipemobile.ui.components.ListFilterMenuButton
import com.callandt.snipemobile.ui.components.ListHeaderActions
import com.callandt.snipemobile.ui.components.ListLoadingPlaceholder
import com.callandt.snipemobile.ui.components.ListSortMenuButton
import com.callandt.snipemobile.ui.components.LocationCard
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.components.SwipeToDeleteRow
import com.callandt.snipemobile.ui.components.UserCard
import com.callandt.snipemobile.ui.components.rememberEntityDeleteState
import com.callandt.snipemobile.ui.components.rememberUserPullRefreshing
import com.callandt.snipemobile.ui.location.AddLocationSheet
import com.callandt.snipemobile.ui.user.AddUserSheet
import com.callandt.snipemobile.ui.util.FilterDimension
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.ListFilter
import com.callandt.snipemobile.ui.util.ListSort
import com.callandt.snipemobile.ui.util.ListSortCatalog
import com.callandt.snipemobile.ui.util.ListSortField
import com.callandt.snipemobile.ui.util.ListSortOrder
import com.callandt.snipemobile.ui.util.WindowAdaptive
import com.callandt.snipemobile.ui.util.listFilterOptions
import com.callandt.snipemobile.ui.util.locationMatchesSearch
import com.callandt.snipemobile.ui.util.rememberResettingLazyListState
import com.callandt.snipemobile.ui.util.sortedByListSort
import com.callandt.snipemobile.ui.util.userMatchesSearch
import com.callandt.snipemobile.ui.util.usersSortedWithCurrentFirst

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
    val currentUser by viewModel.currentUser.collectAsState()
    val locations by viewModel.locations.collectAsState()
    val companies by viewModel.companies.collectAsState()
    val refreshError by viewModel.refreshErrorMessage.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val hasCompletedInitialLoad by viewModel.hasCompletedInitialLoad.collectAsState()

    var searchQuery by remember { mutableStateOf("") }
    var userFilter by remember { mutableStateOf(ListFilter()) }
    var userSort by remember { mutableStateOf(ListSort.nameAscending) }
    var locationSort by remember { mutableStateOf(ListSort.nameAscending) }
    var subtab by remember { mutableIntStateOf(0) }
    var showAddUser by remember { mutableStateOf(false) }
    var showAddLocation by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var userToDelete by remember { mutableStateOf<User?>(null) }
    var locationToDelete by remember { mutableStateOf<Location?>(null) }
    val userDeleteState = rememberEntityDeleteState()
    val locationDeleteState = rememberEntityDeleteState()
    val (isUserRefreshing, onUserRefresh) = rememberUserPullRefreshing(isLoading) {
        viewModel.refresh()
    }
    val tabs = listOf(DirectorySubtab.Users, DirectorySubtab.Locations)
    val currentSubtab = tabs[subtab.coerceIn(tabs.indices)]

    val companyTitle = L10n.string("company")
    val locationTitle = L10n.string("location")
    val jobTitle = L10n.string("job_title")
    val userDimensions = remember(companyTitle, locationTitle, jobTitle) {
        listOf<FilterDimension<User>>(
            FilterDimension(companyTitle) { it.decodedCompanyName },
            FilterDimension(locationTitle) { it.decodedLocationName },
            FilterDimension(jobTitle) { it.decodedJobtitle },
        )
    }
    val userFilterOptions = remember(users, companies, locations, userDimensions) {
        listFilterOptions(
            dimensions = userDimensions,
            catalogByTitle = mapOf(
                companyTitle to companies.map { it.decodedName },
                locationTitle to locations.map { it.decodedName },
            ),
            items = users,
        )
    }

    ErrorSnackbar(refreshError, snackbarHostState, onDismiss = { viewModel.clearRefreshError() })

    val isTablet = WindowAdaptive.isTabletLayout()

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
                    if (!isTablet) {
                        IconButton(onClick = {
                            if (currentSubtab == DirectorySubtab.Users) showAddUser = true else showAddLocation = true
                        }) {
                            Icon(Icons.Default.Add, contentDescription = L10n.string("add"))
                        }
                    }
                },
                actions = {
                    if (isTablet) {
                        IconButton(onClick = {
                            if (currentSubtab == DirectorySubtab.Users) showAddUser = true else showAddLocation = true
                        }) {
                            Icon(Icons.Default.Add, contentDescription = L10n.string("add"))
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
                CompactSubtabRow(
                    selectedIndex = subtab,
                    titles = tabs.map { tab ->
                        when (tab) {
                            DirectorySubtab.Users -> L10n.string("tab_users")
                            DirectorySubtab.Locations -> L10n.string("tab_locations")
                        }
                    },
                    onSelect = { subtab = it },
                )
                if (currentSubtab == DirectorySubtab.Users) {
                    val sorted = users
                        .filter { userFilter.matches(it, userDimensions) }
                        .filter { userMatchesSearch(it, searchQuery) }
                        .sortedByListSort(userSort, ListSortCatalog.users) { it.id }
                    val filtered = if (userSort.field == ListSortField.Name &&
                        userSort.order == ListSortOrder.Ascending
                    ) {
                        usersSortedWithCurrentFirst(sorted, currentUser)
                    } else {
                        sorted
                    }
                    ListCountHeader(
                        count = filtered.size,
                        icon = Icons.Outlined.Groups,
                        trailing = {
                            ListHeaderActions {
                                ListSortMenuButton(
                                    sort = userSort,
                                    keys = ListSortCatalog.users,
                                    onSortChange = { userSort = it },
                                )
                                ListFilterMenuButton(
                                    filter = userFilter,
                                    options = userFilterOptions,
                                    onFilterChange = { userFilter = it },
                                    showLabel = true,
                                )
                            }
                        },
                    )
                    Box(modifier = Modifier.weight(1f)) {
                        when {
                            filtered.isEmpty() && isLoading && !hasCompletedInitialLoad -> {
                                ListLoadingPlaceholder()
                            }
                            filtered.isEmpty() -> {
                                EmptyState(
                                    title = L10n.string("no_users"),
                                    icon = Icons.Outlined.Groups,
                                )
                            }
                            else -> {
                                val listState = rememberResettingLazyListState(
                                    Triple(searchQuery, userFilter, userSort),
                                )
                                LazyColumn(
                                    state = listState,
                                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    items(filtered, key = { it.id }) { user ->
                                        SwipeToDeleteRow(
                                            onDeleteRequest = {
                                                userToDelete = user
                                                userDeleteState.requestDelete()
                                            },
                                        ) {
                                            UserCard(
                                                user = user,
                                                onClick = { onUserClick(user.id) },
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    val filtered = locations
                        .filter { locationMatchesSearch(it, searchQuery) }
                        .sortedByListSort(locationSort, ListSortCatalog.locations) { it.id }
                    ListCountHeader(
                        count = filtered.size,
                        icon = Icons.Outlined.Place,
                        trailing = {
                            ListHeaderActions {
                                ListSortMenuButton(
                                    sort = locationSort,
                                    keys = ListSortCatalog.locations,
                                    onSortChange = { locationSort = it },
                                )
                            }
                        },
                    )
                    Box(modifier = Modifier.weight(1f)) {
                        when {
                            filtered.isEmpty() && isLoading && !hasCompletedInitialLoad -> {
                                ListLoadingPlaceholder()
                            }
                            filtered.isEmpty() -> {
                                EmptyState(
                                    title = L10n.string("no_locations"),
                                    icon = Icons.Outlined.Place,
                                )
                            }
                            else -> {
                                val listState = rememberResettingLazyListState(
                                    Triple(searchQuery, locationSort, subtab),
                                )
                                LazyColumn(
                                    state = listState,
                                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                                    verticalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    items(filtered, key = { it.id }) { location ->
                                        SwipeToDeleteRow(
                                            onDeleteRequest = {
                                                locationToDelete = location
                                                locationDeleteState.requestDelete()
                                            },
                                        ) {
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
            }
        }
    }

    if (showAddUser) {
        AddUserSheet(
            viewModel = viewModel,
            onDismiss = { showAddUser = false },
            onCreated = { id -> id?.let(onUserClick) },
        )
    }

    if (showAddLocation) {
        AddLocationSheet(
            viewModel = viewModel,
            onDismiss = { showAddLocation = false },
            onCreated = { id, _ -> id?.let(onLocationClick) },
        )
    }

    val pendingUser = userToDelete
    val userName = pendingUser?.decodedName ?: pendingUser?.username ?: ""
    EntityDeleteSupport(
        state = userDeleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", userName),
        confirmMessage = L10n.string("delete_user_confirm_message", userName),
        onConfirmDelete = {
            val id = pendingUser?.id ?: return@EntityDeleteSupport
            userDeleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteUser(id) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = { userToDelete = null },
            )
        },
    )

    val pendingLocation = locationToDelete
    val locationName = pendingLocation?.decodedName ?: ""
    EntityDeleteSupport(
        state = locationDeleteState,
        confirmTitle = L10n.string("delete_item_confirm_title", locationName),
        confirmMessage = L10n.string("delete_location_confirm_message", locationName),
        onConfirmDelete = {
            val id = pendingLocation?.id ?: return@EntityDeleteSupport
            locationDeleteState.confirmDelete(
                scope = scope,
                delete = { viewModel.apiClient.deleteLocation(id) },
                errorFromApi = { viewModel.apiClient.lastApiMessage.value },
                onSuccess = { locationToDelete = null },
            )
        },
    )
}
