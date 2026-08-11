package com.callandt.snipemobile.ui.onboarding

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.LoadingOverlay
import com.callandt.snipemobile.ui.components.PrimaryButton
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@Composable
fun ApiSetupScreen(
    viewModel: AppViewModel,
    onContinue: () -> Unit,
) {
    var url by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var validating by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    OnboardingShell {
        OnboardingLogo()
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = L10n.string("connect_snipe_it"),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = L10n.string("connect_snipe_it_desc"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = L10n.string("how_api_key"),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.primary,
            textDecoration = TextDecoration.Underline,
            modifier = Modifier.clickable {
                val intent = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://snipe-it.readme.io/reference/generating-api-tokens"),
                )
                context.startActivity(intent)
            },
        )
        Spacer(modifier = Modifier.height(20.dp))
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L10n.string("server_url"), fontWeight = FontWeight.SemiBold)
                TextField(
                    value = url,
                    onValueChange = { url = it; error = null },
                    placeholder = { Text("https://snipeit.yourcompany.com") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    colors = TextFieldDefaults.colors(
                        focusedContainerColor = MaterialTheme.colorScheme.surface,
                        unfocusedContainerColor = MaterialTheme.colorScheme.surface,
                        disabledContainerColor = MaterialTheme.colorScheme.surface,
                    ),
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L10n.string("api_key"), fontWeight = FontWeight.SemiBold)
                TextField(
                    value = token,
                    onValueChange = { token = it; error = null },
                    placeholder = { Text("Your API Key") },
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
            if (!error.isNullOrBlank()) {
                Text(text = error!!, color = MaterialTheme.colorScheme.error)
            }
            PrimaryButton(
                text = if (validating) L10n.string("loading") else L10n.string("continue"),
                enabled = !validating,
                onClick = {
                    val urlEmpty = url.trim().isEmpty()
                    val keyEmpty = token.trim().isEmpty()
                    if (urlEmpty || keyEmpty) {
                        // Empty fields = skip
                        onContinue()
                        return@PrimaryButton
                    }
                    scope.launch {
                        validating = true
                        error = null
                        viewModel.saveApiConfiguration(url.trim(), token.trim())
                        val validationError = viewModel.validateApiCredentials()
                        validating = false
                        if (validationError == null) onContinue()
                        else error = validationError
                    }
                },
            )
        }
        LoadingOverlay(visible = validating)
    }
}
