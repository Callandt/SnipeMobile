package com.callandt.snipemobile.ui.main

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.DellAddPrefill
import com.callandt.snipemobile.ui.detail.AccessoryDetailScreen
import com.callandt.snipemobile.ui.detail.AssetDetailScreen
import com.callandt.snipemobile.ui.detail.ComponentDetailScreen
import com.callandt.snipemobile.ui.detail.ConsumableDetailScreen
import com.callandt.snipemobile.ui.detail.LicenseDetailScreen
import com.callandt.snipemobile.ui.detail.LocationDetailScreen
import com.callandt.snipemobile.ui.detail.MaintenanceDetailScreen
import com.callandt.snipemobile.ui.detail.UserDetailScreen
import com.callandt.snipemobile.ui.theme.SnipeAccent
import com.callandt.snipemobile.ui.util.L10n

private val SidebarWidth = 260.dp
private val ListColumnWidth = 400.dp
private val DetailMaxContentWidth = 760.dp

/** Tablet: modules | list | detail. */
@Composable
fun TabletMainSplit(
    viewModel: AppViewModel,
    selectedTab: MainTab,
    onTabSelected: (MainTab) -> Unit,
    selection: TabletDetailSelection?,
    onSelectionChange: (TabletDetailSelection?) -> Unit,
    onOpenSettings: () -> Unit,
    onOpenScanner: () -> Unit,
    modifier: Modifier = Modifier,
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

    LaunchedEffect(visibleTabs, selectedTab) {
        if (selectedTab !in visibleTabs) {
            onTabSelected(visibleTabs.first())
        }
    }

    Row(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        TabletSidebar(
            visibleTabs = visibleTabs,
            selectedTab = selectedTab,
            onTabSelected = { tab ->
                onTabSelected(tab)
                onSelectionChange(null)
            },
            onOpenScanner = onOpenScanner,
            onOpenSettings = onOpenSettings,
            modifier = Modifier
                .width(SidebarWidth)
                .fillMaxHeight(),
        )

        VerticalDivider()

        Box(
            modifier = Modifier
                .width(ListColumnWidth)
                .fillMaxHeight(),
        ) {
            MainTabContent(
                viewModel = viewModel,
                selectedTab = selectedTab,
                onOpenSettings = onOpenSettings,
                onOpenScanner = onOpenScanner,
                onAssetClick = { onSelectionChange(TabletDetailSelection.Asset(it)) },
                onAccessoryClick = { onSelectionChange(TabletDetailSelection.Accessory(it)) },
                onLicenseClick = { onSelectionChange(TabletDetailSelection.License(it)) },
                onConsumableClick = { onSelectionChange(TabletDetailSelection.Consumable(it)) },
                onComponentClick = { onSelectionChange(TabletDetailSelection.Component(it)) },
                onUserClick = { onSelectionChange(TabletDetailSelection.User(it)) },
                onLocationClick = { onSelectionChange(TabletDetailSelection.Location(it)) },
                onMaintenanceClick = { onSelectionChange(TabletDetailSelection.Maintenance(it)) },
                pendingDellAdd = pendingDellAdd,
                onClearPendingDellAdd = onClearPendingDellAdd,
                modifier = Modifier.fillMaxSize(),
            )
        }

        VerticalDivider()

        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
                .background(MaterialTheme.colorScheme.surface),
            contentAlignment = Alignment.TopCenter,
        ) {
            Box(
                modifier = Modifier
                    .widthIn(max = DetailMaxContentWidth)
                    .fillMaxSize(),
            ) {
                TabletDetailPane(
                    viewModel = viewModel,
                    selectedTab = selectedTab,
                    selection = selection,
                    onSelectionChange = onSelectionChange,
                    onTabSelected = onTabSelected,
                )
            }
        }
    }
}

@Composable
private fun TabletSidebar(
    visibleTabs: List<MainTab>,
    selectedTab: MainTab,
    onTabSelected: (MainTab) -> Unit,
    onOpenScanner: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 12.dp, vertical = 16.dp),
        ) {
            Text(
                text = "SnipeMobile",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            )

            Spacer(modifier = Modifier.height(8.dp))

            SidebarActionRow(
                label = L10n.string("scan_qr"),
                icon = Icons.Default.QrCodeScanner,
                selected = false,
                onClick = onOpenScanner,
            )

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(modifier = Modifier.padding(horizontal = 8.dp))
            Spacer(modifier = Modifier.height(12.dp))

            visibleTabs.forEach { tab ->
                val label = L10n.string(tab.labelKey)
                NavigationDrawerItem(
                    label = { Text(label) },
                    selected = selectedTab == tab,
                    onClick = { onTabSelected(tab) },
                    icon = { Icon(tab.icon, contentDescription = null) },
                    modifier = Modifier.padding(vertical = 2.dp),
                    colors = NavigationDrawerItemDefaults.colors(
                        selectedContainerColor = SnipeAccent.copy(alpha = 0.14f),
                        selectedIconColor = SnipeAccent,
                        selectedTextColor = MaterialTheme.colorScheme.onSurface,
                    ),
                )
            }

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(modifier = Modifier.padding(horizontal = 8.dp))
            Spacer(modifier = Modifier.height(12.dp))

            SidebarActionRow(
                label = L10n.string("settings"),
                icon = Icons.Default.Settings,
                selected = false,
                onClick = onOpenSettings,
            )
        }
    }
}

@Composable
private fun SidebarActionRow(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(28.dp))
            .selectable(
                selected = selected,
                onClick = onClick,
                role = Role.Button,
            )
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun TabletDetailPane(
    viewModel: AppViewModel,
    selectedTab: MainTab,
    selection: TabletDetailSelection?,
    onSelectionChange: (TabletDetailSelection?) -> Unit,
    onTabSelected: (MainTab) -> Unit,
) {
    when (val current = selection) {
        null -> {
            val (title, description, icon) = emptyPlaceholderFor(selectedTab)
            DetailEmptyPlaceholder(title = title, description = description, icon = icon)
        }
        is TabletDetailSelection.Asset -> AssetDetailScreen(
            assetId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
            onOpenMaintenance = { onSelectionChange(TabletDetailSelection.Maintenance(it)) },
            onOpenUser = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.User(it))
            },
            onOpenLocation = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.Location(it))
            },
            onOpenAsset = { onSelectionChange(TabletDetailSelection.Asset(it)) },
            onOpenAccessory = {
                onTabSelected(MainTab.Accessories)
                onSelectionChange(TabletDetailSelection.Accessory(it))
            },
            onOpenLicense = {
                onTabSelected(MainTab.Licenses)
                onSelectionChange(TabletDetailSelection.License(it))
            },
            onOpenComponent = {
                onTabSelected(MainTab.Stock)
                onSelectionChange(TabletDetailSelection.Component(it))
            },
        )
        is TabletDetailSelection.Accessory -> AccessoryDetailScreen(
            accessoryId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
            onOpenUser = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.User(it))
            },
            onOpenLocation = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.Location(it))
            },
            onOpenAsset = {
                onTabSelected(MainTab.Hardware)
                onSelectionChange(TabletDetailSelection.Asset(it))
            },
        )
        is TabletDetailSelection.License -> LicenseDetailScreen(
            licenseId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
            onOpenUser = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.User(it))
            },
            onOpenAsset = {
                onTabSelected(MainTab.Hardware)
                onSelectionChange(TabletDetailSelection.Asset(it))
            },
        )
        is TabletDetailSelection.Consumable -> ConsumableDetailScreen(
            consumableId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
            onOpenUser = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.User(it))
            },
        )
        is TabletDetailSelection.Component -> ComponentDetailScreen(
            componentId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
            onOpenAsset = {
                onTabSelected(MainTab.Hardware)
                onSelectionChange(TabletDetailSelection.Asset(it))
            },
        )
        is TabletDetailSelection.User -> UserDetailScreen(
            userId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
            onOpenAsset = {
                onTabSelected(MainTab.Hardware)
                onSelectionChange(TabletDetailSelection.Asset(it))
            },
            onOpenAccessory = {
                onTabSelected(MainTab.Accessories)
                onSelectionChange(TabletDetailSelection.Accessory(it))
            },
            onOpenLicense = {
                onTabSelected(MainTab.Licenses)
                onSelectionChange(TabletDetailSelection.License(it))
            },
            onOpenConsumable = {
                onTabSelected(MainTab.Stock)
                onSelectionChange(TabletDetailSelection.Consumable(it))
            },
        )
        is TabletDetailSelection.Location -> LocationDetailScreen(
            locationId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
            onOpenUser = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.User(it))
            },
            onOpenAsset = {
                onTabSelected(MainTab.Hardware)
                onSelectionChange(TabletDetailSelection.Asset(it))
            },
            onOpenAccessory = {
                onTabSelected(MainTab.Accessories)
                onSelectionChange(TabletDetailSelection.Accessory(it))
            },
            onOpenLocation = {
                onTabSelected(MainTab.Directory)
                onSelectionChange(TabletDetailSelection.Location(it))
            },
        )
        is TabletDetailSelection.Maintenance -> MaintenanceDetailScreen(
            maintenanceId = current.id,
            viewModel = viewModel,
            onBack = { onSelectionChange(null) },
        )
    }
}

private fun emptyPlaceholderFor(tab: MainTab): Triple<String, String, ImageVector> =
    when (tab) {
        MainTab.Hardware -> Triple(
            L10n.string("select_asset"),
            L10n.string("select_asset_desc"),
            MainTab.Hardware.icon,
        )
        MainTab.Accessories -> Triple(
            L10n.string("select_accessory"),
            L10n.string("select_accessory_desc"),
            MainTab.Accessories.icon,
        )
        MainTab.Licenses -> Triple(
            L10n.string("select_license"),
            L10n.string("select_license_desc"),
            MainTab.Licenses.icon,
        )
        MainTab.Stock -> Triple(
            L10n.string("select_consumable"),
            L10n.string("select_consumable_desc"),
            MainTab.Stock.icon,
        )
        MainTab.Directory -> Triple(
            L10n.string("select_user"),
            L10n.string("select_user_desc"),
            MainTab.Directory.icon,
        )
    }

@Composable
private fun DetailEmptyPlaceholder(
    title: String,
    description: String,
    icon: ImageVector,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}
