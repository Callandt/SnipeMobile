package com.callandt.snipemobile.ui.components

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.callandt.snipemobile.R
import com.callandt.snipemobile.ui.util.L10n

/** Scrim used in the app switcher / when resigning active. */
@Composable
fun PrivacyCoverOverlay(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        Color(0xE6121216),
                        Color(0xF01C1C22),
                        Color(0xE6121216),
                    ),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.ic_launcher_foreground),
            contentDescription = null,
            modifier = Modifier
                .size(120.dp)
                .alpha(0.85f),
        )
    }
}

@Composable
fun PrivacyBlurOverlay(
    activity: FragmentActivity,
    modifier: Modifier = Modifier,
    authGeneration: Int = 0,
    onAuthenticated: () -> Unit,
    onUnavailable: () -> Unit = {},
    onContinueWithoutAuth: () -> Unit = onUnavailable,
) {
    var promptNonce by remember { mutableStateOf(0) }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    val lifecycleOwner = LocalLifecycleOwner.current
    val lifecycleState by lifecycleOwner.lifecycle.currentStateAsState()

    fun launchPrompt() {
        val manager = BiometricManager.from(activity)
        val authenticators =
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        val canAuth = manager.canAuthenticate(authenticators)
        if (canAuth != BiometricManager.BIOMETRIC_SUCCESS) {
            statusMessage = L10n.string("mgmt_load_failed")
            onUnavailable()
            return
        }
        statusMessage = null
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    onAuthenticated()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    when (errorCode) {
                        BiometricPrompt.ERROR_USER_CANCELED,
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                        BiometricPrompt.ERROR_CANCELED,
                        -> {
                            statusMessage = errString.toString().ifBlank { null }
                        }
                        BiometricPrompt.ERROR_LOCKOUT,
                        BiometricPrompt.ERROR_LOCKOUT_PERMANENT,
                        BiometricPrompt.ERROR_HW_UNAVAILABLE,
                        BiometricPrompt.ERROR_NO_BIOMETRICS,
                        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
                        BiometricPrompt.ERROR_HW_NOT_PRESENT,
                        -> {
                            statusMessage = errString.toString().ifBlank {
                                L10n.string("mgmt_load_failed")
                            }
                            onUnavailable()
                        }
                        else -> statusMessage = errString.toString().ifBlank {
                            L10n.string("mgmt_load_failed")
                        }
                    }
                }
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(L10n.string("require_biometrics"))
            .setSubtitle(L10n.string("security"))
            .setAllowedAuthenticators(authenticators)
            .build()
        runCatching { prompt.authenticate(info) }
            .onFailure {
                statusMessage = L10n.string("mgmt_load_failed")
                onUnavailable()
            }
    }

    // Only prompt while resumed — avoids cancel when leaving to the app switcher.
    LaunchedEffect(authGeneration, promptNonce, lifecycleState) {
        if (lifecycleState.isAtLeast(Lifecycle.State.RESUMED)) {
            launchPrompt()
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        PrivacyCoverOverlay()
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 64.dp, start = 32.dp, end = 32.dp),
        ) {
            statusMessage?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.85f),
                )
            }
            Button(onClick = { promptNonce += 1 }) {
                Text(L10n.string("retry"))
            }
            TextButton(onClick = onContinueWithoutAuth) {
                Text(L10n.string("continue"))
            }
        }
    }
}
