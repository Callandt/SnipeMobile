package com.callandt.snipemobile.ui.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.R
import com.callandt.snipemobile.ui.components.PrimaryButton
import com.callandt.snipemobile.ui.util.L10n

@Composable
fun WelcomeScreen(onContinue: () -> Unit) {
    OnboardingShell {
        OnboardingLogo()
        Spacer(modifier = Modifier.height(32.dp))
        Text(
            text = L10n.string("welcome_title"),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(32.dp))
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            FeatureRow(
                icon = { Icon(Icons.Default.QrCodeScanner, null, Modifier.size(28.dp)) },
                title = L10n.string("welcome_manage_assets"),
                subtitle = L10n.string("welcome_scan_qr"),
            )
            FeatureRow(
                icon = { Icon(Icons.Default.Key, null, Modifier.size(28.dp)) },
                title = L10n.string("welcome_connect"),
                subtitle = L10n.string("welcome_connect_desc"),
            )
            FeatureRow(
                icon = {
                    Icon(
                        painter = painterResource(R.drawable.ic_bird),
                        contentDescription = null,
                        modifier = Modifier.size(28.dp),
                    )
                },
                title = L10n.string("welcome_free"),
                subtitle = L10n.string("welcome_free_desc"),
            )
            Spacer(modifier = Modifier.height(2.dp))
            PrimaryButton(text = L10n.string("get_started"), onClick = onContinue)
        }
    }
}

@Composable
private fun FeatureRow(
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Column(modifier = Modifier.width(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            icon()
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(text = title, fontWeight = FontWeight.Bold)
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
