package com.callandt.snipemobile.ui.onboarding

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.api.SnipeITOAuthService
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.LoadingOverlay
import com.callandt.snipemobile.ui.components.PrimaryButton
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

private enum class SetupPhase {
    Domain,
    Checking,
    Oauth,
    ApiKey,
    Error,
}

@Composable
fun ApiSetupScreen(
    viewModel: AppViewModel,
    onContinue: () -> Unit,
    onSkip: () -> Unit,
) {
    var url by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var validating by remember { mutableStateOf(false) }
    var showSkipConfirm by remember { mutableStateOf(false) }
    var phase by remember { mutableStateOf(SetupPhase.Domain) }
    var clientId by remember { mutableStateOf<String?>(null) }
    var showApiKeyOverride by remember { mutableStateOf(false) }
    var checkGeneration by remember { mutableIntStateOf(0) }
    var pendingSession by remember { mutableStateOf<SnipeITOAuthService.AuthSession?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val busy = validating || phase == SetupPhase.Checking

    fun resetToDomainIfNeeded() {
        if (phase != SetupPhase.Domain && phase != SetupPhase.Checking) {
            checkGeneration += 1
            phase = SetupPhase.Domain
            showApiKeyOverride = false
            clientId = null
        }
    }

    OnboardingShell {
        OnboardingLogo()
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = L10n.string("connect_snipe_it"),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = L10n.string("connect_snipe_it_desc"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(20.dp))
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L10n.string("server_url"), fontWeight = FontWeight.SemiBold)
                TextField(
                    value = url,
                    onValueChange = {
                        url = it
                        error = null
                        resetToDomainIfNeeded()
                    },
                    placeholder = { Text("https://snipeit.yourcompany.com") },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !busy,
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = MaterialTheme.colorScheme.surface,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                        disabledContainerColor = MaterialTheme.colorScheme.surface,
                    ),
                )
            }

            when (phase) {
                SetupPhase.Domain -> {
                    PrimaryButton(
                        text = L10n.string("continue"),
                        enabled = !busy,
                        onClick = {
                            if (url.trim().isEmpty() && token.trim().isEmpty()) {
                                showSkipConfirm = true
                            } else {
                                val generation = checkGeneration + 1
                                checkGeneration = generation
                                phase = SetupPhase.Checking
                                scope.launch {
                                    val discovery = SnipeITOAuthService.discover(url)
                                    if (generation != checkGeneration) return@launch
                                    phase = when (discovery) {
                                        is SnipeITOAuthService.Discovery.OAuth -> {
                                            clientId = discovery.clientId
                                            SetupPhase.Oauth
                                        }
                                        SnipeITOAuthService.Discovery.Unavailable -> SetupPhase.ApiKey
                                        SnipeITOAuthService.Discovery.Unreachable -> SetupPhase.Error
                                    }
                                }
                            }
                        },
                    )
                }
                SetupPhase.Checking -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text(
                            L10n.string("login_checking_instance"),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                SetupPhase.Oauth -> {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = Color(0xFF34C759),
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            L10n.string("login_oauth_ready"),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    PrimaryButton(
                        text = if (validating) L10n.string("login_signing_in") else L10n.string("login_sign_in"),
                        enabled = !validating,
                        onClick = {
                            val id = clientId ?: return@PrimaryButton
                            pendingSession = SnipeITOAuthService.startSession(url, id)
                        },
                    )
                    TextButton(
                        onClick = { showApiKeyOverride = !showApiKeyOverride },
                        enabled = !validating,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            if (showApiKeyOverride) {
                                L10n.string("login_hide_api_key")
                            } else {
                                L10n.string("login_use_api_key")
                            },
                        )
                    }
                    if (showApiKeyOverride) {
                        ApiKeyField(token = token, onTokenChange = { token = it; error = null })
                        PrimaryButton(
                            text = L10n.string("continue"),
                            enabled = !validating,
                            onClick = {
                                scope.launch {
                                    continueWithApiKey(
                                        url = url,
                                        token = token,
                                        viewModel = viewModel,
                                        onSkipConfirm = { showSkipConfirm = true },
                                        onValidating = { validating = it },
                                        onError = { error = it },
                                        onContinue = onContinue,
                                    )
                                }
                            },
                        )
                    }
                }
                SetupPhase.ApiKey -> {
                    Text(
                        L10n.string("login_oauth_unavailable"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    ApiKeyField(token = token, onTokenChange = { token = it; error = null })
                    Text(
                        text = L10n.string("how_api_key"),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        textDecoration = TextDecoration.Underline,
                        modifier = Modifier.clickable {
                            context.startActivity(
                                Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://snipe-it.readme.io/reference/generating-api-tokens"),
                                ),
                            )
                        },
                    )
                    PrimaryButton(
                        text = if (validating) L10n.string("loading") else L10n.string("continue"),
                        enabled = !validating,
                        onClick = {
                            scope.launch {
                                continueWithApiKey(
                                    url = url,
                                    token = token,
                                    viewModel = viewModel,
                                    onSkipConfirm = { showSkipConfirm = true },
                                    onValidating = { validating = it },
                                    onError = { error = it },
                                    onContinue = onContinue,
                                )
                            }
                        },
                    )
                }
                SetupPhase.Error -> {
                    Text(
                        L10n.string("login_connection_error"),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                        textAlign = TextAlign.Center,
                    )
                    PrimaryButton(
                        text = L10n.string("rights_check_retry"),
                        onClick = { phase = SetupPhase.Domain },
                    )
                }
            }

            if (!error.isNullOrBlank()) {
                Text(text = error!!, color = MaterialTheme.colorScheme.error)
            }
        }
        LoadingOverlay(visible = validating && pendingSession == null)
    }

    pendingSession?.let { session ->
        SnipeITOAuthWebSheet(
            authorizeUrl = session.authorizeUrl,
            onCancel = { pendingSession = null },
            onRedirect = { uri ->
                val captured = session
                pendingSession = null
                scope.launch {
                    validating = true
                    error = null
                    try {
                        val result = SnipeITOAuthService.completeSignIn(url, captured, uri)
                        viewModel.saveApiConfiguration(result.baseUrl, result.token, syncAfterSave = false)
                        val validationError = viewModel.validateApiCredentials()
                        if (validationError == null) onContinue()
                        else error = validationError
                    } catch (e: SnipeITOAuthService.ServiceException) {
                        if (e.kind != SnipeITOAuthService.ServiceException.Kind.Cancelled) {
                            error = e.message
                        }
                    } catch (e: Exception) {
                        error = e.message ?: L10n.string("login_failed")
                    } finally {
                        validating = false
                    }
                }
            },
        )
    }

    if (showSkipConfirm) {
        AlertDialog(
            onDismissRequest = { showSkipConfirm = false },
            title = { Text(L10n.string("skip_api_confirm_title")) },
            text = { Text(L10n.string("skip_api_confirm_message")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showSkipConfirm = false
                        onSkip()
                    },
                ) { Text(L10n.string("continue")) }
            },
            dismissButton = {
                TextButton(onClick = { showSkipConfirm = false }) {
                    Text(L10n.string("cancel"))
                }
            },
        )
    }
}

@Composable
private fun ApiKeyField(token: String, onTokenChange: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(L10n.string("login_api_key"), fontWeight = FontWeight.SemiBold)
        TextField(
            value = token,
            onValueChange = onTokenChange,
            placeholder = { Text(L10n.string("login_api_key_placeholder")) },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            shape = RoundedCornerShape(12.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = MaterialTheme.colorScheme.surface,
                unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                disabledContainerColor = MaterialTheme.colorScheme.surface,
            ),
        )
    }
}

private suspend fun continueWithApiKey(
    url: String,
    token: String,
    viewModel: AppViewModel,
    onSkipConfirm: () -> Unit,
    onValidating: (Boolean) -> Unit,
    onError: (String?) -> Unit,
    onContinue: () -> Unit,
) {
    if (url.trim().isEmpty() || token.trim().isEmpty()) {
        onSkipConfirm()
        return
    }
    onValidating(true)
    onError(null)
    viewModel.saveApiConfiguration(url.trim(), token.trim(), syncAfterSave = false)
    val validationError = viewModel.validateApiCredentials()
    onValidating(false)
    if (validationError == null) onContinue()
    else onError(validationError)
}
