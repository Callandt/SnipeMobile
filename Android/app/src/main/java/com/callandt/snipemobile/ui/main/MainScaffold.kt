package com.callandt.snipemobile.ui.main

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarDefaults
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.DellAddPrefill
import com.callandt.snipemobile.ui.util.L10n

enum class MainTab(val labelKey: String, val icon: ImageVector) {
    Hardware("tab_assets", Icons.Default.Laptop),
    Accessories("tab_accessories", Icons.Default.Usb),
    Licenses("tab_licenses", Icons.Default.Description),
    Stock("tab_stock", Icons.Default.Inventory2),
    Directory("tab_directory", Icons.Default.People),
}

@Composable
fun MainScaffold(
    viewModel: AppViewModel,
    selectedTab: MainTab,
    onTabSelected: (MainTab) -> Unit,
    onOpenSettings: () -> Unit,
    onOpenScanner: () -> Unit,
    onAssetClick: (Int) -> Unit,
    onAccessoryClick: (Int) -> Unit,
    onLicenseClick: (Int) -> Unit,
    onConsumableClick: (Int) -> Unit,
    onComponentClick: (Int) -> Unit,
    onUserClick: (Int) -> Unit,
    onLocationClick: (Int) -> Unit,
    onMaintenanceClick: (Int) -> Unit,
    pendingDellAdd: DellAddPrefill? = null,
    onClearPendingDellAdd: () -> Unit = {},
) {
    val showAccessories by viewModel.showAccessoriesTab.collectAsState()
    val showLicenses by viewModel.showLicensesTab.collectAsState()
    val showConsumables by viewModel.showConsumablesTab.collectAsState()
    val showComponents by viewModel.showComponentsTab.collectAsState()

    val visibleTabs = buildList {
        add(MainTab.Hardware)
        if (showAccessories) add(MainTab.Accessories)
        if (showLicenses) add(MainTab.Licenses)
        if (showConsumables || showComponents) add(MainTab.Stock)
        add(MainTab.Directory)
    }

    // Avoid double status-bar padding under nested tab scaffolds.
    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surface,
                tonalElevation = 0.dp,
                windowInsets = NavigationBarDefaults.windowInsets,
            ) {
                visibleTabs.forEach { tab ->
                    val label = L10n.string(tab.labelKey)
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { onTabSelected(tab) },
                        icon = { Icon(tab.icon, contentDescription = label) },
                        label = { Text(label) },
                    )
                }
            }
        },
    ) { padding ->
        MainTabContent(
            viewModel = viewModel,
            selectedTab = selectedTab,
            onOpenSettings = onOpenSettings,
            onOpenScanner = onOpenScanner,
            onAssetClick = onAssetClick,
            onAccessoryClick = onAccessoryClick,
            onLicenseClick = onLicenseClick,
            onConsumableClick = onConsumableClick,
            onComponentClick = onComponentClick,
            onUserClick = onUserClick,
            onLocationClick = onLocationClick,
            onMaintenanceClick = onMaintenanceClick,
            pendingDellAdd = pendingDellAdd,
            onClearPendingDellAdd = onClearPendingDellAdd,
            modifier = Modifier.padding(padding),
        )
    }
}

/** Shared list content for phone tabs and tablet list column. */
@Composable
fun MainTabContent(
    viewModel: AppViewModel,
    selectedTab: MainTab,
    onOpenSettings: () -> Unit,
    onOpenScanner: () -> Unit,
    onAssetClick: (Int) -> Unit,
    onAccessoryClick: (Int) -> Unit,
    onLicenseClick: (Int) -> Unit,
    onConsumableClick: (Int) -> Unit,
    onComponentClick: (Int) -> Unit,
    onUserClick: (Int) -> Unit,
    onLocationClick: (Int) -> Unit,
    onMaintenanceClick: (Int) -> Unit,
    modifier: Modifier = Modifier,
    pendingDellAdd: DellAddPrefill? = null,
    onClearPendingDellAdd: () -> Unit = {},
) {
    when (selectedTab) {
        MainTab.Hardware -> HardwareTab(
            viewModel = viewModel,
            onAssetClick = onAssetClick,
            onMaintenanceClick = onMaintenanceClick,
            onOpenSettings = onOpenSettings,
            onOpenScanner = onOpenScanner,
            pendingDellAdd = pendingDellAdd,
            onClearPendingDellAdd = onClearPendingDellAdd,
            modifier = modifier,
        )
        MainTab.Accessories -> AccessoriesTab(
            viewModel = viewModel,
            onAccessoryClick = onAccessoryClick,
            onOpenSettings = onOpenSettings,
            onOpenScanner = onOpenScanner,
            modifier = modifier,
        )
        MainTab.Licenses -> LicensesTab(
            viewModel = viewModel,
            onLicenseClick = onLicenseClick,
            onOpenSettings = onOpenSettings,
            onOpenScanner = onOpenScanner,
            modifier = modifier,
        )
        MainTab.Stock -> StockTab(
            viewModel = viewModel,
            onConsumableClick = onConsumableClick,
            onComponentClick = onComponentClick,
            onOpenSettings = onOpenSettings,
            onOpenScanner = onOpenScanner,
            modifier = modifier,
        )
        MainTab.Directory -> DirectoryTab(
            viewModel = viewModel,
            onUserClick = onUserClick,
            onLocationClick = onLocationClick,
            onOpenSettings = onOpenSettings,
            onOpenScanner = onOpenScanner,
            modifier = modifier,
        )
    }
}
