package com.callandt.snipemobile.ui.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.SettingsGroupedCard
import com.callandt.snipemobile.ui.components.SettingsSectionFooter
import com.callandt.snipemobile.ui.components.SettingsSectionHeader
import com.callandt.snipemobile.ui.components.SettingsToggleRow
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DellSettingsScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
) {
    val enableDellQrScan by viewModel.enableDellQrScan.collectAsState()
    var clientId by remember { mutableStateOf("") }
    var clientSecret by remember { mutableStateOf("") }
    var testing by remember { mutableStateOf(false) }
    var alertMessage by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        clientId = viewModel.dellTechDirectClientId()
        clientSecret = viewModel.dellTechDirectClientSecret()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("dell_settings_title")) },
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
            SettingsSectionHeader(L10n.string("scanning"))
            SettingsGroupedCard {
                SettingsToggleRow(
                    icon = Icons.Default.QrCode,
                    iconColor = Color(0xFF007AFF),
                    title = L10n.string("dell_qr_scan_toggle"),
                    checked = enableDellQrScan,
                    onCheckedChange = { viewModel.setEnableDellQrScan(it) },
                )
            }
            SettingsSectionFooter(L10n.string("dell_qr_scan_footer"))

            SettingsSectionHeader(L10n.string("dell_techdirect_api"))
            SettingsGroupedCard {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    OutlinedTextField(
                        value = clientId,
                        onValueChange = { clientId = it },
                        label = { Text(L10n.string("dell_client_id")) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = clientSecret,
                        onValueChange = { clientSecret = it },
                        label = { Text(L10n.string("dell_client_secret")) },
                        modifier = Modifier.fillMaxWidth(),
                        visualTransformation = PasswordVisualTransformation(),
                        singleLine = true,
                    )
                }
            }
            SettingsSectionFooter(L10n.string("dell_techdirect_footer"))

            TextButton(
                onClick = {
                    scope.launch {
                        testing = true
                        viewModel.saveDellTechDirectCredentials(clientId.trim(), clientSecret)
                        alertMessage = viewModel.testDellTechDirectConnection()
                            ?: L10n.string("api_test_connection_ok")
                        testing = false
                    }
                },
                enabled = !testing,
            ) {
                if (testing) {
                    CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                }
                Text(L10n.string("api_test_connection"))
            }

            TextButton(
                onClick = {
                    viewModel.saveDellTechDirectCredentials(clientId.trim(), clientSecret)
                    onBack()
                },
            ) {
                Text(L10n.string("save"))
            }

            Text(
                L10n.string("api_test_connection_footer"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    alertMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { alertMessage = null },
            title = { Text(L10n.string("dell_techdirect_api")) },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = { alertMessage = null }) {
                    Text(L10n.string("ok"))
                }
            },
        )
    }
}
