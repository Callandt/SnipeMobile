package com.callandt.snipemobile.ui.onboarding

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.prefs.AppMode
import com.callandt.snipemobile.data.prefs.AppModeCheckProgress
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.PrimaryButton
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@Composable
fun RightsCheckOnboardingScreen(
    viewModel: AppViewModel,
    onFinished: (AppMode) -> Unit,
    onFailed: () -> Unit,
) {
    var progress by remember { mutableStateOf(AppModeCheckProgress()) }
    var didStart by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun runCheck() {
        scope.launch {
            progress = AppModeCheckProgress()
            progress = viewModel.detectAppMode { updated ->
                progress = updated
            }
        }
    }

    LaunchedEffect(Unit) {
        if (!didStart) {
            didStart = true
            runCheck()
        }
    }

    OnboardingShell {
        OnboardingLogo()
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = L10n.string("rights_check_title"),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = L10n.string("rights_check_subtitle"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(20.dp))

        Surface(
            shape = RoundedCornerShape(14.dp),
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.fillMaxWidth(),
        ) {
            RightsCheckProgressList(
                progress = progress,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
            )
        }

        Spacer(modifier = Modifier.height(16.dp))

        when {
            progress.succeeded && progress.detectedMode != null -> {
                Text(
                    text = if (progress.detectedMode == AppMode.Admin) {
                        L10n.string("rights_check_result_admin")
                    } else {
                        L10n.string("rights_check_result_user")
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }
            progress.connection is AppModeCheckProgress.StepState.Failure -> {
                val message = (progress.connection as AppModeCheckProgress.StepState.Failure).message
                Text(
                    text = message ?: L10n.string("rights_check_failed"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center,
                )
            }
            progress.rights is AppModeCheckProgress.StepState.Failure -> {
                val message = (progress.rights as AppModeCheckProgress.StepState.Failure).message
                Text(
                    text = message ?: L10n.string("rights_check_failed"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center,
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        if (progress.isComplete) {
            PrimaryButton(
                text = if (progress.succeeded) {
                    L10n.string("continue")
                } else {
                    L10n.string("rights_check_retry")
                },
                onClick = {
                    if (progress.succeeded) {
                        val mode = progress.detectedMode
                        if (mode != null) onFinished(mode)
                        else runCheck()
                    } else {
                        runCheck()
                    }
                },
            )
            if (!progress.succeeded) {
                Spacer(modifier = Modifier.height(8.dp))
                TextButton(onClick = onFailed) {
                    Text(L10n.string("back"))
                }
            }
        } else {
            CircularProgressIndicator(modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
fun RightsCheckProgressList(
    progress: AppModeCheckProgress,
    modifier: Modifier = Modifier,
) {
    val rightsDetail = when {
        progress.rights is AppModeCheckProgress.StepState.Success && progress.detectedMode != null ->
            progress.detectedMode!!.localizedTitle
        else -> null
    }

    Column(modifier = modifier.fillMaxWidth()) {
        RightsCheckProgressRow(
            title = L10n.string("rights_check_connection"),
            state = progress.connection,
        )
        HorizontalDivider(modifier = Modifier.padding(start = 40.dp))
        RightsCheckProgressRow(
            title = L10n.string("rights_check_rights"),
            state = progress.rights,
            detail = rightsDetail,
        )
    }
}

@Composable
private fun RightsCheckProgressRow(
    title: String,
    state: AppModeCheckProgress.StepState,
    detail: String? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp, horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RightsCheckStatusIcon(state)
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
            )
            if (!detail.isNullOrBlank()) {
                Text(
                    text = detail,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun RightsCheckStatusIcon(state: AppModeCheckProgress.StepState) {
    when (state) {
        is AppModeCheckProgress.StepState.Pending -> {
            Icon(
                imageVector = Icons.Default.RadioButtonUnchecked,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                modifier = Modifier.size(28.dp),
            )
        }
        is AppModeCheckProgress.StepState.Running -> {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp,
            )
        }
        is AppModeCheckProgress.StepState.Success -> {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                tint = Color(0xFF34C759),
                modifier = Modifier.size(28.dp),
            )
        }
        is AppModeCheckProgress.StepState.Failure -> {
            Icon(
                imageVector = Icons.Default.Cancel,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(28.dp),
            )
        }
    }
}
