package com.callandt.snipemobile.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.callandt.snipemobile.data.api.DellQrLink
import com.callandt.snipemobile.data.api.SnipeITQRLink
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
import com.callandt.snipemobile.ui.main.MainScaffold
import com.callandt.snipemobile.ui.main.MainTab
import com.callandt.snipemobile.ui.main.TabletDetailSelection
import com.callandt.snipemobile.ui.main.TabletMainSplit
import com.callandt.snipemobile.ui.onboarding.ApiSetupScreen
import com.callandt.snipemobile.ui.onboarding.ModuleSelectionScreen
import com.callandt.snipemobile.ui.onboarding.WelcomeScreen
import com.callandt.snipemobile.ui.scanner.QrScannerScreen
import com.callandt.snipemobile.ui.settings.SettingsScreen
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.WindowAdaptive
import kotlinx.coroutines.launch

object Routes {
    const val Welcome = "welcome"
    const val ApiSetup = "api_setup"
    const val ModuleSelection = "module_selection"
    const val Main = "main"
    const val Settings = "settings"
    const val Scanner = "scanner"
    const val AssetDetail = "asset/{id}"
    const val AccessoryDetail = "accessory/{id}"
    const val LicenseDetail = "license/{id}"
    const val ConsumableDetail = "consumable/{id}"
    const val ComponentDetail = "component/{id}"
    const val UserDetail = "user/{id}"
    const val LocationDetail = "location/{id}"
    const val MaintenanceDetail = "maintenance/{id}"

    fun asset(id: Int) = "asset/$id"
    fun accessory(id: Int) = "accessory/$id"
    fun license(id: Int) = "license/$id"
    fun consumable(id: Int) = "consumable/$id"
    fun component(id: Int) = "component/$id"
    fun user(id: Int) = "user/$id"
    fun location(id: Int) = "location/$id"
    fun maintenance(id: Int) = "maintenance/$id"
}

@Composable
fun AppNav(viewModel: AppViewModel) {
    val hasCompletedOnboarding by viewModel.hasCompletedOnboarding.collectAsState()

    // Wait for onboarding preference.
    if (hasCompletedOnboarding == null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        return
    }

    val navController = rememberNavController()
    val enableDellQrScan by viewModel.enableDellQrScan.collectAsState()
    val pendingDellAdd by viewModel.pendingDellAdd.collectAsState()
    val scope = rememberCoroutineScope()
    var selectedTab by remember { mutableStateOf(MainTab.Hardware) }
    var tabletSelection by remember { mutableStateOf<TabletDetailSelection?>(null) }
    var showDellAddPrompt by remember { mutableStateOf<DellAddPrefill?>(null) }
    val isTablet = WindowAdaptive.isTabletLayout()
    val pendingMainTab by viewModel.pendingMainTab.collectAsState()

    LaunchedEffect(pendingMainTab) {
        val tab = viewModel.consumePendingMainTab() ?: return@LaunchedEffect
        selectedTab = tab
        tabletSelection = null
        if (navController.currentDestination?.route != Routes.Main) {
            navController.navigate(Routes.Main) {
                popUpTo(navController.graph.startDestinationId) { inclusive = false }
                launchSingleTop = true
            }
        }
    }

    val startDestination = remember(hasCompletedOnboarding) {
        if (hasCompletedOnboarding == true) Routes.Main else Routes.Welcome
    }
    fun openPhoneDetail(route: String) {
        navController.navigate(route)
    }

    fun openTabletDetail(tab: MainTab, selection: TabletDetailSelection) {
        selectedTab = tab
        tabletSelection = selection
    }

    fun openEntityFromQr(route: String) {
        when {
            route.startsWith("asset/") -> {
                val id = route.removePrefix("asset/").toIntOrNull() ?: return
                if (isTablet) openTabletDetail(MainTab.Hardware, TabletDetailSelection.Asset(id))
                else openPhoneDetail(route)
            }
            route.startsWith("accessory/") -> {
                val id = route.removePrefix("accessory/").toIntOrNull() ?: return
                if (isTablet) openTabletDetail(MainTab.Accessories, TabletDetailSelection.Accessory(id))
                else openPhoneDetail(route)
            }
            route.startsWith("license/") -> {
                val id = route.removePrefix("license/").toIntOrNull() ?: return
                if (isTablet) openTabletDetail(MainTab.Licenses, TabletDetailSelection.License(id))
                else openPhoneDetail(route)
            }
            route.startsWith("consumable/") -> {
                val id = route.removePrefix("consumable/").toIntOrNull() ?: return
                if (isTablet) openTabletDetail(MainTab.Stock, TabletDetailSelection.Consumable(id))
                else openPhoneDetail(route)
            }
            route.startsWith("component/") -> {
                val id = route.removePrefix("component/").toIntOrNull() ?: return
                if (isTablet) openTabletDetail(MainTab.Stock, TabletDetailSelection.Component(id))
                else openPhoneDetail(route)
            }
            else -> openPhoneDetail(route)
        }
    }

    NavHost(navController = navController, startDestination = startDestination) {
        composable(Routes.Welcome) {
            WelcomeScreen(onContinue = { navController.navigate(Routes.ApiSetup) })
        }
        composable(Routes.ApiSetup) {
            ApiSetupScreen(viewModel = viewModel, onContinue = { navController.navigate(Routes.ModuleSelection) })
        }
        composable(Routes.ModuleSelection) {
            ModuleSelectionScreen(viewModel = viewModel, onFinish = {
                navController.navigate(Routes.Main) {
                    popUpTo(Routes.Welcome) { inclusive = true }
                }
            })
        }
        composable(Routes.Main) {
            if (isTablet) {
                TabletMainSplit(
                    viewModel = viewModel,
                    selectedTab = selectedTab,
                    onTabSelected = { selectedTab = it },
                    selection = tabletSelection,
                    onSelectionChange = { tabletSelection = it },
                    onOpenSettings = { navController.navigate(Routes.Settings) },
                    onOpenScanner = { navController.navigate(Routes.Scanner) },
                    pendingDellAdd = pendingDellAdd ?: showDellAddPrompt,
                    onClearPendingDellAdd = {
                        showDellAddPrompt = null
                        viewModel.clearPendingDellAdd()
                    },
                )
            } else {
                MainScaffold(
                    viewModel = viewModel,
                    selectedTab = selectedTab,
                    onTabSelected = { selectedTab = it },
                    onOpenSettings = { navController.navigate(Routes.Settings) },
                    onOpenScanner = { navController.navigate(Routes.Scanner) },
                    onAssetClick = { navController.navigate(Routes.asset(it)) },
                    onAccessoryClick = { navController.navigate(Routes.accessory(it)) },
                    onLicenseClick = { navController.navigate(Routes.license(it)) },
                    onConsumableClick = { navController.navigate(Routes.consumable(it)) },
                    onComponentClick = { navController.navigate(Routes.component(it)) },
                    onUserClick = { navController.navigate(Routes.user(it)) },
                    onLocationClick = { navController.navigate(Routes.location(it)) },
                    onMaintenanceClick = { navController.navigate(Routes.maintenance(it)) },
                    pendingDellAdd = pendingDellAdd ?: showDellAddPrompt,
                    onClearPendingDellAdd = {
                        showDellAddPrompt = null
                        viewModel.clearPendingDellAdd()
                    },
                )
            }
        }
        composable(Routes.Settings) {
            SettingsScreen(
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onWiped = {
                    navController.navigate(Routes.Welcome) {
                        popUpTo(Routes.Main) { inclusive = true }
                    }
                },
            )
        }
        composable(Routes.Scanner) {
            val snackbarHostState = remember { SnackbarHostState() }
            Scaffold(
                snackbarHost = { SnackbarHost(snackbarHostState) },
            ) { _ ->
                QrScannerScreen(
                    onBack = { navController.popBackStack() },
                    onLinkParsed = { link ->
                        scope.launch {
                            navigateFromQrLink(
                                navController = navController,
                                viewModel = viewModel,
                                link = link,
                                snackbarHostState = snackbarHostState,
                                openEntity = { route ->
                                    navController.popBackStack()
                                    openEntityFromQr(route)
                                },
                            )
                        }
                    },
                    onDellUrlScanned = { url ->
                        if (!enableDellQrScan) {
                            scope.launch {
                                snackbarHostState.showSnackbar(L10n.string("invalid_qr_unrecognized"))
                            }
                            return@QrScannerScreen
                        }
                        scope.launch {
                            handleDellQrScan(
                                navController = navController,
                                viewModel = viewModel,
                                url = url,
                                snackbarHostState = snackbarHostState,
                                onOpenAsset = { assetId ->
                                    navController.popBackStack()
                                    openEntityFromQr(Routes.asset(assetId))
                                },
                                onPromptAddAsset = { prefill ->
                                    navController.popBackStack()
                                    selectedTab = MainTab.Hardware
                                    showDellAddPrompt = prefill
                                    viewModel.setPendingDellAdd(prefill.url, prefill.serial)
                                },
                            )
                        }
                    },
                    onError = { message ->
                        scope.launch { snackbarHostState.showSnackbar(message) }
                    },
                )
            }
        }
        // Phone detail routes.
        detailRoute(Routes.AssetDetail, "id") { id ->
            AssetDetailScreen(
                assetId = id,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenMaintenance = { navController.navigate(Routes.maintenance(it)) },
                onOpenUser = { navController.navigate(Routes.user(it)) },
                onOpenLocation = { navController.navigate(Routes.location(it)) },
                onOpenAsset = { navController.navigate(Routes.asset(it)) },
                onOpenAccessory = { navController.navigate(Routes.accessory(it)) },
                onOpenLicense = { navController.navigate(Routes.license(it)) },
                onOpenComponent = { navController.navigate(Routes.component(it)) },
            )
        }
        detailRoute(Routes.AccessoryDetail, "id") { id ->
            AccessoryDetailScreen(
                accessoryId = id,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenUser = { navController.navigate(Routes.user(it)) },
                onOpenLocation = { navController.navigate(Routes.location(it)) },
                onOpenAsset = { navController.navigate(Routes.asset(it)) },
            )
        }
        detailRoute(Routes.LicenseDetail, "id") { id ->
            LicenseDetailScreen(
                licenseId = id,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenUser = { navController.navigate(Routes.user(it)) },
                onOpenAsset = { navController.navigate(Routes.asset(it)) },
            )
        }
        detailRoute(Routes.ConsumableDetail, "id") { id ->
            ConsumableDetailScreen(
                consumableId = id,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenUser = { navController.navigate(Routes.user(it)) },
            )
        }
        detailRoute(Routes.ComponentDetail, "id") { id ->
            ComponentDetailScreen(
                componentId = id,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenAsset = { navController.navigate(Routes.asset(it)) },
            )
        }
        detailRoute(Routes.UserDetail, "id") { id ->
            UserDetailScreen(
                userId = id,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenAsset = { navController.navigate(Routes.asset(it)) },
                onOpenAccessory = { navController.navigate(Routes.accessory(it)) },
                onOpenLicense = { navController.navigate(Routes.license(it)) },
                onOpenConsumable = { navController.navigate(Routes.consumable(it)) },
            )
        }
        detailRoute(Routes.LocationDetail, "id") { id ->
            LocationDetailScreen(
                locationId = id,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onOpenUser = { navController.navigate(Routes.user(it)) },
                onOpenAsset = { navController.navigate(Routes.asset(it)) },
                onOpenAccessory = { navController.navigate(Routes.accessory(it)) },
            )
        }
        detailRoute(Routes.MaintenanceDetail, "id") { id ->
            MaintenanceDetailScreen(id, viewModel) { navController.popBackStack() }
        }
    }
}

private fun androidx.navigation.NavGraphBuilder.detailRoute(
    route: String,
    argName: String,
    content: @Composable (Int) -> Unit,
) {
    composable(
        route = route,
        arguments = listOf(navArgument(argName) { type = NavType.IntType }),
    ) { entry ->
        content(entry.arguments?.getInt(argName) ?: 0)
    }
}

private suspend fun navigateFromQrLink(
    navController: androidx.navigation.NavController,
    viewModel: AppViewModel,
    link: SnipeITQRLink,
    snackbarHostState: SnackbarHostState,
    openEntity: (String) -> Unit,
) {
    val route = when (link) {
        is SnipeITQRLink.Hardware -> Routes.asset(link.id)
        is SnipeITQRLink.Accessory -> Routes.accessory(link.id)
        is SnipeITQRLink.License -> Routes.license(link.id)
        is SnipeITQRLink.Consumable -> Routes.consumable(link.id)
        is SnipeITQRLink.Component -> Routes.component(link.id)
        is SnipeITQRLink.HardwareByTag -> {
            val asset = viewModel.apiClient.fetchHardwareByTag(link.tag)
            asset?.let { Routes.asset(it.id) }
        }
    }
    if (route != null) {
        openEntity(route)
    } else {
        val message = if (link is SnipeITQRLink.HardwareByTag) {
            L10n.string("asset_not_found")
        } else {
            "Item niet gevonden"
        }
        snackbarHostState.showSnackbar(message)
    }
}

private suspend fun handleDellQrScan(
    navController: androidx.navigation.NavController,
    viewModel: AppViewModel,
    url: java.net.URI,
    snackbarHostState: SnackbarHostState,
    onOpenAsset: (Int) -> Unit,
    onPromptAddAsset: (DellAddPrefill) -> Unit,
) {
    val serial = DellQrLink.extractServiceTag(url)?.trim().orEmpty()
    if (serial.isEmpty()) {
        snackbarHostState.showSnackbar(L10n.string("invalid_dell_qr"))
        return
    }
    val normalized = serial.lowercase()
    var asset = viewModel.assets.value.firstOrNull {
        it.decodedSerial.trim().lowercase() == normalized
    }
    if (asset == null && viewModel.assets.value.isEmpty()) {
        viewModel.refresh()
        asset = viewModel.assets.value.firstOrNull {
            it.decodedSerial.trim().lowercase() == normalized
        }
    }
    if (asset != null) {
        onOpenAsset(asset.id)
    } else {
        onPromptAddAsset(DellAddPrefill(url = url.toString(), serial = serial))
    }
}
