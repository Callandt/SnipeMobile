package com.callandt.snipemobile

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.callandt.snipemobile.notifications.AuditNotificationScheduler
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.AuditNavigationIntent
import com.callandt.snipemobile.ui.components.PrivacyBlurOverlay
import com.callandt.snipemobile.ui.navigation.AppNav
import com.callandt.snipemobile.ui.theme.SnipeMobileTheme
import com.callandt.snipemobile.widget.WidgetDestination
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class MainActivity : FragmentActivity() {

    private var privacyEnabled by mutableStateOf(false)
    private var unlocked by mutableStateOf(true)
    private var authGeneration by mutableIntStateOf(0)

    /** Always attached; toggled via alpha so Recents can capture it in time. */
    private var privacyShield: View? = null
    private var stoppedWhilePrivate = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val app = application as SnipeMobileApp
        val launchIntent = intent

        lifecycleScope.launch {
            combine(app.preferences.useBiometrics, app.preferences.hasCompletedOnboarding) { bio, onboarded ->
                bio && onboarded
            }.collect { enabled ->
                val wasEnabled = privacyEnabled
                privacyEnabled = enabled
                applyRecentsProtection(enabled)
                when {
                    !enabled -> {
                        unlocked = true
                        stoppedWhilePrivate = false
                        setPrivacyShieldVisible(false)
                    }
                    app.preferences.consumeBiometricsJustConfirmed() -> {
                        unlocked = true
                        setPrivacyShieldVisible(false)
                    }
                    !wasEnabled -> {
                        lockSession()
                        setPrivacyShieldVisible(true)
                    }
                }
            }
        }

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
            val shouldLock = privacyEnabled && !unlocked

            SnipeMobileTheme(themeMode = appTheme) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background,
                    contentColor = MaterialTheme.colorScheme.onBackground,
                ) {
                    Box(modifier = Modifier.fillMaxSize()) {
                        AppNav(viewModel)

                        if (shouldLock) {
                            PrivacyBlurOverlay(
                                activity = this@MainActivity,
                                authGeneration = authGeneration,
                                onAuthenticated = {
                                    unlocked = true
                                    setPrivacyShieldVisible(false)
                                },
                                onUnavailable = { },
                                onContinueWithoutAuth = {
                                    unlocked = true
                                    setPrivacyShieldVisible(false)
                                },
                            )
                        }
                    }
                }
            }
        }

        // Permanent overlay (alpha 0). Faster than add/remove when leaving to Recents.
        ensurePrivacyShield()
    }

    /**
     * Fires before the system takes the Recents thumbnail — unlike onPause.
     * Solid privacy cover while the app is in the background.
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!privacyEnabled) {
            setPrivacyShieldVisible(false)
            return
        }
        if (!hasFocus) {
            applyRecentsProtection(true)
            setPrivacyShieldVisible(true)
        } else if (unlocked) {
            setPrivacyShieldVisible(false)
        } else {
            setPrivacyShieldVisible(true)
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (privacyEnabled) {
            stoppedWhilePrivate = true
            lockSession()
            setPrivacyShieldVisible(true)
        }
    }

    override fun onStop() {
        super.onStop()
        if (privacyEnabled) {
            stoppedWhilePrivate = true
            lockSession()
            setPrivacyShieldVisible(true)
        }
    }

    override fun onResume() {
        super.onResume()
        if (privacyEnabled) {
            applyRecentsProtection(true)
        }
        if (privacyEnabled && stoppedWhilePrivate) {
            stoppedWhilePrivate = false
            lockSession()
        }
        if (privacyEnabled && !unlocked) {
            setPrivacyShieldVisible(true)
        } else if (unlocked) {
            setPrivacyShieldVisible(false)
        }
    }

    private fun lockSession() {
        if (!unlocked) {
            authGeneration += 1
            return
        }
        unlocked = false
        authGeneration += 1
    }

    private fun applyRecentsProtection(enabled: Boolean) {
        // Prefer the dedicated Recents API (blank card). FLAG_SECURE as extra guard.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(!enabled)
        }
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun ensurePrivacyShield() {
        if (privacyShield != null) return
        val size = (120 * resources.displayMetrics.density).toInt()
        val shield = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#F0121216"))
            alpha = 0f
            elevation = Float.MAX_VALUE
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(
                ImageView(context).apply {
                    setImageResource(R.drawable.ic_launcher_foreground)
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    alpha = 0.85f
                },
                FrameLayout.LayoutParams(size, size, android.view.Gravity.CENTER),
            )
        }
        addContentView(
            shield,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        privacyShield = shield
    }

    private fun setPrivacyShieldVisible(visible: Boolean) {
        ensurePrivacyShield()
        privacyShield?.alpha = if (visible) 1f else 0f
        // When visible, block touches so locked content isn't interactive under the shield.
        privacyShield?.isClickable = visible
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
