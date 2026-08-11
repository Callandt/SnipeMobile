package com.callandt.snipemobile

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.callandt.snipemobile.notifications.AuditNotificationScheduler
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.AuditNavigationIntent
import com.callandt.snipemobile.ui.components.PrivacyBlurOverlay
import com.callandt.snipemobile.ui.navigation.AppNav
import com.callandt.snipemobile.ui.theme.SnipeMobileTheme
import com.callandt.snipemobile.widget.WidgetDestination

class MainActivity : FragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val app = application as SnipeMobileApp
        val launchIntent = intent

        setContent {
            val viewModel: AppViewModel = viewModel(factory = AppViewModel.Factory(app))
            LaunchedEffect(Unit) {
                pendingAuditIntent?.let {
                    viewModel.setPendingAuditNavigation(it)
                    pendingAuditIntent = null
                }
                pendingWidgetDestination?.let {
                    viewModel.setPendingWidgetDestination(it)
                    pendingWidgetDestination = null
                }
                deliverLaunchExtras(viewModel, launchIntent)
            }
            val appTheme by viewModel.appTheme.collectAsState()
            val useBiometrics by viewModel.useBiometrics.collectAsState()
            val hasCompletedOnboarding by viewModel.hasCompletedOnboarding.collectAsState()
            val onboardingDone = hasCompletedOnboarding == true

            // Unlock until the app goes to background.
            var unlocked by remember { mutableStateOf(true) }
            var authGeneration by remember { mutableStateOf(0) }

            LaunchedEffect(useBiometrics) {
                if (!useBiometrics) unlocked = true
            }

            // App-level stop only (not Activity stops from pickers).
            DisposableEffect(useBiometrics, onboardingDone) {
                if (!useBiometrics || !onboardingDone) {
                    return@DisposableEffect onDispose { }
                }
                val observer = LifecycleEventObserver { _, event ->
                    if (event == Lifecycle.Event.ON_STOP) {
                        unlocked = false
                        authGeneration += 1
                    }
                }
                val lifecycle = ProcessLifecycleOwner.get().lifecycle
                lifecycle.addObserver(observer)
                onDispose { lifecycle.removeObserver(observer) }
            }

            val shouldLock = useBiometrics && onboardingDone && !unlocked

            SnipeMobileTheme(themeMode = appTheme) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                    contentColor = MaterialTheme.colorScheme.onBackground,
                ) {
                    Box(modifier = Modifier.fillMaxSize()) {
                        AppNav(viewModel)

                        if (shouldLock) {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(MaterialTheme.colorScheme.background),
                            ) {
                                PrivacyBlurOverlay(
                                    activity = this@MainActivity,
                                    authGeneration = authGeneration,
                                    onAuthenticated = { unlocked = true },
                                    onUnavailable = { unlocked = true },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverIncomingExtras(intent)
    }

    private fun deliverLaunchExtras(viewModel: AppViewModel, intent: android.content.Intent?) {
        deliverWidgetDestination(intent) { viewModel.setPendingWidgetDestination(it) }
        deliverAuditNavigation(intent) { viewModel.setPendingAuditNavigation(it) }
    }

    private fun deliverIncomingExtras(intent: android.content.Intent?) {
        val app = application as SnipeMobileApp
        runCatching {
            val viewModel = androidx.lifecycle.ViewModelProvider(this, AppViewModel.Factory(app))[AppViewModel::class.java]
            deliverWidgetDestination(intent) { viewModel.setPendingWidgetDestination(it) }
            deliverAuditNavigation(intent) { viewModel.setPendingAuditNavigation(it) }
        }.onFailure {
            WidgetDestination.fromIntent(intent)?.let { pendingWidgetDestination = it }
            val auditIntent = intent?.getStringExtra(AuditNotificationScheduler.EXTRA_AUDIT_INTENT)
            if (auditIntent == AuditNotificationScheduler.INTENT_OPEN_DUE_TODAY) {
                pendingAuditIntent = AuditNavigationIntent.OpenDueToday
            }
        }
    }

    private fun deliverWidgetDestination(
        intent: android.content.Intent?,
        onDestination: (WidgetDestination) -> Unit,
    ) {
        val destination = WidgetDestination.fromIntent(intent) ?: return
        intent?.data = null
        intent?.removeExtra(WidgetDestination.EXTRA_DESTINATION)
        onDestination(destination)
    }

    private fun deliverAuditNavigation(
        intent: android.content.Intent?,
        onIntent: (AuditNavigationIntent) -> Unit,
    ) {
        val auditIntent = intent?.getStringExtra(AuditNotificationScheduler.EXTRA_AUDIT_INTENT) ?: return
        if (auditIntent != AuditNotificationScheduler.INTENT_OPEN_DUE_TODAY) return
        intent.removeExtra(AuditNotificationScheduler.EXTRA_AUDIT_INTENT)
        onIntent(AuditNavigationIntent.OpenDueToday)
    }

    companion object {
        var pendingAuditIntent: AuditNavigationIntent? = null
        var pendingWidgetDestination: WidgetDestination? = null
    }
}
