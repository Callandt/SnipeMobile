package com.callandt.snipemobile.ui.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.PrimaryButton
import com.callandt.snipemobile.ui.util.L10n

@Composable
fun ModuleSelectionScreen(
    viewModel: AppViewModel,
    onFinish: () -> Unit,
) {
    val showAccessories by viewModel.showAccessoriesTab.collectAsState()
    val showLicenses by viewModel.showLicensesTab.collectAsState()
    val showConsumables by viewModel.showConsumablesTab.collectAsState()
    val showComponents by viewModel.showComponentsTab.collectAsState()
    val showAudit by viewModel.showAuditSubtab.collectAsState()
    val showMaintenance by viewModel.showMaintenanceSubtab.collectAsState()

    LaunchedEffect(Unit) {
        // Enable audit the first time this screen is shown.
        if (!viewModel.isAuditSubtabPreferenceSet()) {
            viewModel.setShowAuditSubtab(true)
        }
    }

    OnboardingShell {
        OnboardingLogo()
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = L10n.string("module_intro_title"),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(32.dp))
        Text(
            text = L10n.string("module_intro_subtitle"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(22.dp))

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            ModuleSection(L10n.string("module_intro_tabs_header")) {
                ModuleRow(Icons.Default.Usb, L10n.string("tab_accessories"), showAccessories) {
                    viewModel.setShowAccessoriesTab(it)
                }
                HorizontalDivider(modifier = Modifier.padding(start = 48.dp))
                ModuleRow(Icons.Default.Description, L10n.string("tab_licenses"), showLicenses) {
                    viewModel.setShowLicensesTab(it)
                }
            }
            ModuleSection(L10n.string("tab_stock")) {
                ModuleRow(Icons.Default.Inventory2, L10n.string("tab_consumables"), showConsumables) {
                    viewModel.setShowConsumablesTab(it)
                }
                HorizontalDivider(modifier = Modifier.padding(start = 48.dp))
                ModuleRow(Icons.Default.Memory, L10n.string("tab_components"), showComponents) {
                    viewModel.setShowComponentsTab(it)
                }
            }
            ModuleSection(L10n.string("settings_features")) {
                ModuleRow(Icons.Default.Notifications, L10n.string("settings_audit_short"), showAudit) {
                    viewModel.setShowAuditSubtab(it)
                }
                HorizontalDivider(modifier = Modifier.padding(start = 48.dp))
                ModuleRow(Icons.Default.Build, L10n.string("settings_maintenance"), showMaintenance) {
                    viewModel.setShowMaintenanceSubtab(it)
                }
            }
            PrimaryButton(
                text = L10n.string("continue"),
                onClick = {
                    viewModel.completeOnboarding()
                    viewModel.refresh()
                    onFinish()
                },
            )
        }
    }
}

@Composable
private fun ModuleSection(
    title: String,
    content: @Composable () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = title.uppercase(),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Surface(
            shape = RoundedCornerShape(14.dp),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Column { content() }
        }
    }
}

@Composable
private fun ModuleRow(
    icon: ImageVector,
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
            modifier = Modifier.width(28.dp),
        )
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.weight(1f),
        )
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
