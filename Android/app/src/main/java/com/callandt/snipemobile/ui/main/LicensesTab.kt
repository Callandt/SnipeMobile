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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.EmptyState
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.components.LicenseCard
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.license.AddLicenseSheet
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.matchesSearch

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
    val refreshError by viewModel.refreshErrorMessage.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    var searchQuery by remember { mutableStateOf("") }
    var showAddLicense by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    val filtered = items.filter {
        matchesSearch(it.decodedName, it.decodedProductKey, it.decodedCategoryName, query = searchQuery)
    }

    ErrorSnackbar(refreshError, snackbarHostState)

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
                    IconButton(onClick = { showAddLicense = true }) {
                        Icon(Icons.Default.Add, contentDescription = L10n.string("add_license"))
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
            if (filtered.isEmpty()) {
                EmptyState(
                    title = L10n.string("no_licenses"),
                    icon = Icons.Default.Description,
                )
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 6.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    items(filtered, key = { it.id }) { license ->
                        LicenseCard(
                            license = license,
                            onClick = { onLicenseClick(license.id) },
                        )
                    }
                }
            }
        }
    }

    if (showAddLicense) {
        AddLicenseSheet(
            viewModel = viewModel,
            onDismiss = { showAddLicense = false },
            onCreated = { viewModel.syncInBackground() },
        )
    }
}
