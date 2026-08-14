package com.callandt.snipemobile.ui.settings

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DesktopWindows
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.WifiTethering
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.callandt.snipemobile.data.prefs.AppMode
import com.callandt.snipemobile.data.prefs.AppModeCheckProgress
import com.callandt.snipemobile.debug.AppLog
import com.callandt.snipemobile.debug.DebugLogStore
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.SettingsGroupedCard
import com.callandt.snipemobile.ui.components.SettingsRow
import com.callandt.snipemobile.ui.components.SettingsSectionFooter
import com.callandt.snipemobile.ui.components.SettingsSectionHeader
import com.callandt.snipemobile.ui.components.SettingsToggleRow
import com.callandt.snipemobile.ui.management.ManagementEntity
import com.callandt.snipemobile.ui.management.ManagementHubScreen
import com.callandt.snipemobile.ui.management.ManagementListScreen
import com.callandt.snipemobile.ui.onboarding.RightsCheckProgressList
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.notifications.AuditNotificationScheduler
import java.util.Locale
import kotlinx.coroutines.launch

private object SettingsRoutes {
    const val Root = "settings_root"
    const val Appearance = "appearance"
    const val Modules = "modules"
    const val Management = "management"
    const val ManagementEntity = "management/{entity}"
    const val ActivityLog = "activity_log"
    const val Api = "api"
    const val Audit = "audit"
    const val Assets = "assets"
    const val Dell = "dell"

    fun managementEntity(entity: ManagementEntity) = "management/${entity.name}"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onWiped: () -> Unit,
) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = SettingsRoutes.Root) {
        composable(SettingsRoutes.Root) {
            SettingsRootScreen(
                viewModel = viewModel,
                onBack = onBack,
                onWiped = onWiped,
                onNavigate = { navController.navigate(it) },
            )
        }
        composable(SettingsRoutes.Appearance) {
            AppearanceSettingsScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
        }
        composable(SettingsRoutes.Modules) {
            ModulesSettingsScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
        }
        composable(SettingsRoutes.Management) {
            ManagementHubScreen(
                onBack = { navController.popBackStack() },
                onOpenEntity = { entity ->
                    navController.navigate(SettingsRoutes.managementEntity(entity))
                },
            )
        }
        composable(
            route = SettingsRoutes.ManagementEntity,
            arguments = listOf(navArgument("entity") { type = NavType.StringType }),
        ) { backStackEntry ->
            val entityName = backStackEntry.arguments?.getString("entity")
            val entity = ManagementEntity.entries.firstOrNull { it.name == entityName }
            if (entity != null) {
                ManagementListScreen(
                    entity = entity,
                    viewModel = viewModel,
                    onBack = { navController.popBackStack() },
                )
            }
        }
        composable(SettingsRoutes.ActivityLog) {
            ActivityLogScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
        }
        composable(SettingsRoutes.Api) {
            ApiSettingsScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
        }
        composable(SettingsRoutes.Audit) {
            AuditSettingsScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
        }
        composable(SettingsRoutes.Assets) {
            AssetCreationSettingsScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
        }
        composable(SettingsRoutes.Dell) {
            DellSettingsScreen(viewModel = viewModel, onBack = { navController.popBackStack() })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsRootScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onWiped: () -> Unit,
    onNavigate: (String) -> Unit,
) {
    val appTheme by viewModel.appTheme.collectAsState()
    val useBiometrics by viewModel.useBiometrics.collectAsState()
    val baseUrl by viewModel.baseUrl.collectAsState()
    val isConfigured by viewModel.isConfigured.collectAsState()
    val showAccessories by viewModel.showAccessoriesTab.collectAsState()
    val showLicenses by viewModel.showLicensesTab.collectAsState()
    val showConsumables by viewModel.showConsumablesTab.collectAsState()
    val showComponents by viewModel.showComponentsTab.collectAsState()
    val showAudit by viewModel.showAuditSubtab.collectAsState()
    val showMaintenance by viewModel.showMaintenanceSubtab.collectAsState()
    val appMode by viewModel.appMode.collectAsState()
    val isAdminCapable by viewModel.isAdminCapable.collectAsState()
    val showPhotosInCardList by viewModel.showPhotosInCardList.collectAsState()
    val isUserMode = appMode == AppMode.User

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var showWipeDialog by remember { mutableStateOf(false) }
    var showDebugExportConfirm by remember { mutableStateOf(false) }
    var showDebugExportError by remember { mutableStateOf(false) }
    var isExportingDebug by remember { mutableStateOf(false) }
    var pendingBiometrics by remember { mutableStateOf<Boolean?>(null) }

    val themeLabel = when (appTheme) {
        "light" -> L10n.string("light")
        "dark" -> L10n.string("dark")
        else -> L10n.string("system")
    }
    val enabledModuleCount = listOf(showAccessories, showLicenses, showConsumables, showComponents).count { it }
    val apiStatusLabel = if (!isConfigured || baseUrl.isBlank()) {
        L10n.string("settings_not_configured")
    } else {
        runCatching { Uri.parse(baseUrl).host }.getOrNull()?.takeIf { !it.isNullOrBlank() } ?: baseUrl
    }
    val auditStatusLabel = if (showAudit) L10n.string("settings_status_on") else L10n.string("settings_status_off")
    val versionDisplay = remember {
        runCatching {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val version = info.versionName ?: "—"
            val build = info.longVersionCode
            if (build > 0) "$version ($build)" else version
        }.getOrDefault("—")
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("settings")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.background),
        ) {
            if (isAdminCapable) {
                item {
                    SettingsSectionHeader(L10n.string("app_mode_section"))
                    SettingsGroupedCard {
                        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                                SegmentedButton(
                                    selected = !isUserMode,
                                    onClick = {
                                        if (isUserMode) {
                                            viewModel.setActiveMode(AppMode.Admin)
                                            onBack()
                                        }
                                    },
                                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2),
                                ) {
                                    Text(L10n.string("app_mode_admin"))
                                }
                                SegmentedButton(
                                    selected = isUserMode,
                                    onClick = {
                                        if (!isUserMode) {
                                            viewModel.setActiveMode(AppMode.User)
                                            onBack()
                                        }
                                    },
                                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2),
                                ) {
                                    Text(L10n.string("app_mode_user"))
                                }
                            }
                        }
                    }
                    SettingsSectionFooter(L10n.string("app_mode_switch_footer"))
                }
            }

            item {
                SettingsSectionHeader(L10n.string("settings_general"))
                SettingsGroupedCard {
                    SettingsRow(
                        icon = Icons.Default.Brush,
                        iconColor = Color(0xFFAF52DE),
                        title = L10n.string("appearance"),
                        value = themeLabel,
                        onClick = { onNavigate(SettingsRoutes.Appearance) },
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                    SettingsToggleRow(
                        icon = Icons.Default.PhotoLibrary,
                        iconColor = Color(0xFF5AC8FA),
                        title = L10n.string("show_photos_in_cards_toggle"),
                        checked = showPhotosInCardList,
                        onCheckedChange = { viewModel.setShowPhotosInCardList(it) },
                    )
                }
                SettingsSectionFooter(L10n.string("show_photos_in_cards_footer"))
            }

            if (!isUserMode) {
                item {
                    SettingsSectionHeader(L10n.string("settings_modules"))
                    SettingsGroupedCard {
                        SettingsRow(
                            icon = Icons.Default.GridView,
                            iconColor = Color(0xFFFF9500),
                            title = L10n.string("settings_modules"),
                            value = L10n.string("settings_modules_count", enabledModuleCount),
                            onClick = { onNavigate(SettingsRoutes.Modules) },
                        )
                    }
                }

                item {
                    SettingsSectionHeader(L10n.string("settings_management"))
                    SettingsGroupedCard {
                        SettingsRow(
                            icon = Icons.Default.Tune,
                            iconColor = Color(0xFFFF2D55),
                            title = L10n.string("settings_management"),
                            onClick = { onNavigate(SettingsRoutes.Management) },
                        )
                        HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(
                            icon = Icons.Default.History,
                            iconColor = Color(0xFF8E6F4E),
                            title = L10n.string("settings_activity_log"),
                            onClick = { onNavigate(SettingsRoutes.ActivityLog) },
                        )
                    }
                    SettingsSectionFooter(L10n.string("settings_management_footer"))
                }
            }

            item {
                SettingsSectionHeader(L10n.string("settings_privacy"))
                SettingsGroupedCard {
                    SettingsToggleRow(
                        icon = Icons.Default.Fingerprint,
                        iconColor = Color(0xFF5856D6),
                        title = L10n.string("require_biometrics"),
                        checked = useBiometrics,
                        enabled = pendingBiometrics == null,
                        onCheckedChange = { newValue ->
                            val activity = context as? FragmentActivity
                            if (activity == null) {
                                viewModel.setUseBiometrics(newValue)
                                return@SettingsToggleRow
                            }
                            pendingBiometrics = newValue
                            val manager = BiometricManager.from(activity)
                            val canAuth = manager.canAuthenticate(
                                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                            )
                            if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
                                pendingBiometrics = null
                                return@SettingsToggleRow
                            }
                            val executor = ContextCompat.getMainExecutor(activity)
                            val prompt = BiometricPrompt(
                                activity,
                                executor,
                                object : BiometricPrompt.AuthenticationCallback() {
                                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                                        viewModel.setUseBiometrics(
                                            enabled = newValue,
                                            justConfirmed = true,
                                        )
                                        pendingBiometrics = null
                                    }

                                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                                        pendingBiometrics = null
                                    }

                                    override fun onAuthenticationFailed() = Unit
                                },
                            )
                            prompt.authenticate(
                                BiometricPrompt.PromptInfo.Builder()
                                    .setTitle(L10n.string("security"))
                                    .setSubtitle(L10n.string("confirm_setting_change"))
                                    .setAllowedAuthenticators(
                                        BiometricManager.Authenticators.BIOMETRIC_STRONG or
                                            BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                                    )
                                    .build(),
                            )
                        },
                    )
                }
            }

            if (!isUserMode) {
                item {
                    SettingsSectionHeader(L10n.string("settings_features"))
                    SettingsGroupedCard {
                        SettingsRow(
                            icon = Icons.Default.QrCode,
                            iconColor = Color(0xFF007AFF),
                            title = L10n.string("settings_assets"),
                            onClick = { onNavigate(SettingsRoutes.Assets) },
                        )
                        HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(
                            icon = Icons.Default.Notifications,
                            iconColor = Color(0xFFFF3B30),
                            title = L10n.string("settings_audit_short"),
                            value = auditStatusLabel,
                            onClick = { onNavigate(SettingsRoutes.Audit) },
                        )
                        HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                        SettingsToggleRow(
                            icon = Icons.Default.Build,
                            iconColor = Color(0xFF5AC8FA),
                            title = L10n.string("settings_maintenance"),
                            checked = showMaintenance,
                            onCheckedChange = viewModel::setShowMaintenanceSubtab,
                        )
                    }
                    SettingsSectionFooter(L10n.string("settings_maintenance_footer"))
                }
            }

            item {
                SettingsSectionHeader(L10n.string("settings_connection"))
                SettingsGroupedCard {
                    SettingsRow(
                        icon = Icons.Default.WifiTethering,
                        iconColor = Color(0xFF34C759),
                        title = L10n.string("api_settings_short"),
                        value = apiStatusLabel,
                        onClick = { onNavigate(SettingsRoutes.Api) },
                    )
                    if (!isUserMode) {
                        HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                        SettingsRow(
                            icon = Icons.Default.DesktopWindows,
                            iconColor = Color(0xFF8E8E93),
                            title = L10n.string("settings_dell"),
                            onClick = { onNavigate(SettingsRoutes.Dell) },
                        )
                    }
                }
                SettingsSectionFooter(L10n.string("connection_section_footer"))
            }

            item {
                SettingsSectionHeader(L10n.string("settings_about"))
                SettingsGroupedCard {
                    SettingsRow(
                        icon = Icons.Default.Info,
                        iconColor = Color(0xFF8E8E93),
                        title = L10n.string("settings_version"),
                        value = versionDisplay,
                        showChevron = false,
                        onClick = null,
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                    SettingsRow(
                        icon = Icons.Default.BarChart,
                        iconColor = Color(0xFF000000),
                        title = L10n.string("settings_source_code"),
                        value = "GitHub",
                        onClick = {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/Callandt/SnipeMobile")),
                            )
                        },
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                    SettingsRow(
                        icon = Icons.Default.Email,
                        iconColor = Color(0xFF007AFF),
                        title = L10n.string("settings_support"),
                        onClick = {
                            val intent = Intent(Intent.ACTION_SENDTO).apply {
                                data = Uri.parse("mailto:snipemobile@icloud.com")
                                putExtra(Intent.EXTRA_SUBJECT, "SnipeMobile Support")
                            }
                            runCatching { context.startActivity(intent) }
                        },
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                    SettingsRow(
                        icon = Icons.Default.Archive,
                        iconColor = Color(0xFFFF9500),
                        title = L10n.string("debug_export"),
                        value = if (isExportingDebug) L10n.string("debug_export_working") else null,
                        showChevron = false,
                        onClick = {
                            if (!isExportingDebug) showDebugExportConfirm = true
                        },
                    )
                    HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                    SettingsRow(
                        icon = Icons.Default.Delete,
                        iconColor = Color(0xFFFF3B30),
                        title = L10n.string("reset_data_button"),
                        titleColor = Color(0xFFFF3B30),
                        showChevron = false,
                        onClick = { showWipeDialog = true },
                    )
                }
            }
        }
    }

    if (showDebugExportConfirm) {
        AlertDialog(
            onDismissRequest = { if (!isExportingDebug) showDebugExportConfirm = false },
            title = { Text(L10n.string("debug_export_confirm_title")) },
            text = { Text(L10n.string("debug_export_confirm_message")) },
            confirmButton = {
                TextButton(
                    enabled = !isExportingDebug,
                    onClick = {
                        isExportingDebug = true
                        AppLog.info("User requested debug zip export", "debug")
                        scope.launch {
                            val ok = runCatching {
                                val zip = DebugLogStore.exportZip(context, viewModel.apiClient)
                                DebugLogStore.shareZip(context, zip)
                            }.isSuccess
                            isExportingDebug = false
                            showDebugExportConfirm = false
                            if (!ok) {
                                AppLog.info("Debug zip export failed", "debug")
                                showDebugExportError = true
                            }
                        }
                    },
                ) { Text(L10n.string("debug_export_confirm_action")) }
            },
            dismissButton = {
                TextButton(
                    enabled = !isExportingDebug,
                    onClick = { showDebugExportConfirm = false },
                ) { Text(L10n.string("cancel")) }
            },
        )
    }

    if (showDebugExportError) {
        AlertDialog(
            onDismissRequest = { showDebugExportError = false },
            title = { Text(L10n.string("debug_export_failed_title")) },
            text = { Text(L10n.string("debug_export_failed")) },
            confirmButton = {
                TextButton(onClick = { showDebugExportError = false }) {
                    Text(L10n.string("ok"))
                }
            },
        )
    }

    if (showWipeDialog) {
        AlertDialog(
            onDismissRequest = { showWipeDialog = false },
            title = { Text(L10n.string("reset_data_confirm_title")) },
            text = { Text(L10n.string("reset_data_confirm_message")) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.wipeAllData()
                    showWipeDialog = false
                    onWiped()
                }) { Text(L10n.string("reset_data_confirm_action")) }
            },
            dismissButton = {
                TextButton(onClick = { showWipeDialog = false }) { Text(L10n.string("cancel")) }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AppearanceSettingsScreen(viewModel: AppViewModel, onBack: () -> Unit) {
    val appTheme by viewModel.appTheme.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("appearance")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SettingsSectionHeader(L10n.string("theme"))
            SettingsGroupedCard {
                ThemeOption(L10n.string("system"), appTheme == "system") { viewModel.setAppTheme("system") }
                HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                ThemeOption(L10n.string("light"), appTheme == "light") { viewModel.setAppTheme("light") }
                HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                ThemeOption(L10n.string("dark"), appTheme == "dark") { viewModel.setAppTheme("dark") }
            }
        }
    }
}

@Composable
private fun ThemeOption(label: String, selected: Boolean, onSelect: () -> Unit) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
            .then(Modifier),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = onSelect)
        Text(text = label, modifier = Modifier.padding(end = 16.dp))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModulesSettingsScreen(viewModel: AppViewModel, onBack: () -> Unit) {
    val showAccessories by viewModel.showAccessoriesTab.collectAsState()
    val showLicenses by viewModel.showLicensesTab.collectAsState()
    val showConsumables by viewModel.showConsumablesTab.collectAsState()
    val showComponents by viewModel.showComponentsTab.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("settings_modules")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                SettingsSectionHeader(L10n.string("settings_modules_tabs_header"))
                SettingsGroupedCard {
                    SettingsToggleRow(Icons.Default.CreditCard, Color(0xFF5856D6), L10n.string("tab_accessories"), showAccessories, viewModel::setShowAccessoriesTab)
                    HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                    SettingsToggleRow(Icons.Default.ShoppingBag, Color(0xFF007AFF), L10n.string("tab_licenses"), showLicenses, viewModel::setShowLicensesTab)
                }
                SettingsSectionFooter(L10n.string("settings_modules_tabs_footer"))
            }
            item {
                SettingsSectionHeader(L10n.string("tab_stock"))
                SettingsGroupedCard {
                    SettingsToggleRow(Icons.Default.ShoppingBag, Color(0xFFFF9500), L10n.string("tab_consumables"), showConsumables, viewModel::setShowConsumablesTab)
                    HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                    SettingsToggleRow(Icons.Default.Memory, Color(0xFF34C759), L10n.string("tab_components"), showComponents, viewModel::setShowComponentsTab)
                }
                SettingsSectionFooter(L10n.string("settings_modules_stock_footer"))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AuditSettingsScreen(viewModel: AppViewModel, onBack: () -> Unit) {
    val showAudit by viewModel.showAuditSubtab.collectAsState()
    val auditNotificationsEnabled by viewModel.auditNotificationsEnabled.collectAsState()
    val auditHour by viewModel.auditNotificationHour.collectAsState()
    val auditMinute by viewModel.auditNotificationMinute.collectAsState()
    val context = LocalContext.current
    var showTimePicker by remember { mutableStateOf(false) }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) {
            viewModel.setAuditNotificationsEnabled(true)
            if (!AuditNotificationScheduler.canScheduleExactAlarms(context)) {
                AuditNotificationScheduler.openExactAlarmSettings(context)
            }
        }
    }

    fun enableAuditNotifications() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !AuditNotificationScheduler.canPostNotifications(context)
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            viewModel.setAuditNotificationsEnabled(true)
            // Request exact-alarm permission when available (API 31+).
            if (!AuditNotificationScheduler.canScheduleExactAlarms(context)) {
                AuditNotificationScheduler.openExactAlarmSettings(context)
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("audit_settings_title")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.padding(padding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SettingsGroupedCard {
                SettingsToggleRow(
                    icon = Icons.Default.Notifications,
                    iconColor = Color(0xFFFF3B30),
                    title = L10n.string("audit_subtab_toggle"),
                    checked = showAudit,
                    onCheckedChange = viewModel::setShowAuditSubtab,
                )
            }
            SettingsSectionFooter(L10n.string("audit_settings_compact_footer"))

            SettingsGroupedCard {
                SettingsToggleRow(
                    icon = Icons.Default.Notifications,
                    iconColor = Color(0xFFFF9500),
                    title = L10n.string("audit_notifications_toggle"),
                    checked = auditNotificationsEnabled,
                    enabled = showAudit,
                    onCheckedChange = { enabled ->
                        if (enabled) enableAuditNotifications() else viewModel.setAuditNotificationsEnabled(false)
                    },
                )
                HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                SettingsRow(
                    icon = Icons.Default.Notifications,
                    iconColor = Color(0xFF8E8E93),
                    title = L10n.string("audit_notification_time"),
                    value = String.format(Locale.getDefault(), "%02d:%02d", auditHour, auditMinute),
                    onClick = if (showAudit && auditNotificationsEnabled) {
                        { showTimePicker = true }
                    } else {
                        null
                    },
                )
            }
        }
    }

    if (showTimePicker) {
        val timePickerState = rememberTimePickerState(
            initialHour = auditHour,
            initialMinute = auditMinute,
            is24Hour = true,
        )
        AlertDialog(
            onDismissRequest = { showTimePicker = false },
            title = { Text(L10n.string("audit_notification_time")) },
            text = { TimePicker(state = timePickerState) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.setAuditNotificationTime(timePickerState.hour, timePickerState.minute)
                    showTimePicker = false
                }) { Text(L10n.string("ok")) }
            },
            dismissButton = {
                TextButton(onClick = { showTimePicker = false }) { Text(L10n.string("cancel")) }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AssetCreationSettingsScreen(viewModel: AppViewModel, onBack: () -> Unit) {
    val autoFill by viewModel.autoFillAssetTag.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("settings_assets")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.padding(padding).padding(16.dp)) {
            SettingsSectionHeader(L10n.string("settings_assets_creation_header"))
            SettingsGroupedCard {
                SettingsToggleRow(
                    icon = Icons.Default.QrCode,
                    iconColor = Color(0xFF007AFF),
                    title = L10n.string("auto_fill_asset_tag_toggle"),
                    checked = autoFill,
                    onCheckedChange = viewModel::setAutoFillAssetTag,
                )
            }
            SettingsSectionFooter(L10n.string("auto_fill_asset_tag_footer"))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ApiSettingsScreen(viewModel: AppViewModel, onBack: () -> Unit) {
    val baseUrl by viewModel.baseUrl.collectAsState()
    val appMode by viewModel.appMode.collectAsState()
    var url by remember(baseUrl) { mutableStateOf(baseUrl) }
    var token by remember { mutableStateOf(viewModel.currentApiToken()) }
    var isChecking by remember { mutableStateOf(false) }
    var showCheckProgress by remember { mutableStateOf(false) }
    var checkProgress by remember { mutableStateOf(AppModeCheckProgress()) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("api_settings")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            OutlinedTextField(
                value = url,
                onValueChange = { url = it },
                label = { Text(L10n.string("server_url")) },
                placeholder = { Text("https://snipeit.yourcompany.com") },
                modifier = Modifier.fillMaxWidth(),
                singleLine = true,
            )
            OutlinedTextField(
                value = token,
                onValueChange = { token = it },
                label = { Text(L10n.string("api_key")) },
                modifier = Modifier.fillMaxWidth(),
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
            )
            Text(
                L10n.string("api_settings_desc"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Button(
                onClick = {
                    scope.launch {
                        if (isChecking) return@launch
                        isChecking = true
                        showCheckProgress = true
                        checkProgress = AppModeCheckProgress()
                        viewModel.saveApiConfiguration(url.trim(), token.trim(), syncAfterSave = false)
                        val result = viewModel.detectAppMode { updated ->
                            checkProgress = updated
                        }
                        if (result.succeeded) {
                            viewModel.syncForCurrentAppModeSuspending()
                        }
                        isChecking = false
                    }
                },
                enabled = !isChecking && url.isNotBlank() && token.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isChecking) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .padding(end = 8.dp)
                            .size(18.dp),
                        strokeWidth = 2.dp,
                    )
                }
                Text(L10n.string("save"))
            }

            if (showCheckProgress) {
                RightsCheckProgressList(progress = checkProgress)
                when {
                    checkProgress.succeeded && checkProgress.detectedMode != null -> {
                        Text(
                            if (checkProgress.detectedMode == AppMode.Admin) {
                                L10n.string("rights_check_result_admin")
                            } else {
                                L10n.string("rights_check_result_user")
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    checkProgress.connection is AppModeCheckProgress.StepState.Failure -> {
                        Text(
                            (checkProgress.connection as AppModeCheckProgress.StepState.Failure).message
                                ?: L10n.string("rights_check_failed"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    checkProgress.rights is AppModeCheckProgress.StepState.Failure -> {
                        Text(
                            (checkProgress.rights as AppModeCheckProgress.StepState.Failure).message
                                ?: L10n.string("rights_check_failed"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
            }

            Text(
                L10n.string("api_save_check_footer"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            SettingsGroupedCard {
                SettingsRow(
                    icon = Icons.Default.Person,
                    iconColor = Color(0xFF5856D6),
                    title = L10n.string("app_mode_label"),
                    value = appMode?.localizedTitle ?: L10n.string("app_mode_unknown"),
                    showChevron = false,
                    onClick = null,
                )
            }
        }
    }
}
