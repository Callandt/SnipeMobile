package com.callandt.snipemobile.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val LightColors = lightColorScheme(
    primary = SnipeAccent,
    onPrimary = Color.White,
    primaryContainer = SnipeAccentLight,
    onPrimaryContainer = SnipeAccentOnContainer,
    secondary = SnipeGray,
    onSecondary = Color.White,
    secondaryContainer = SnipeAccentLight,
    onSecondaryContainer = SnipeAccent,
    tertiary = SnipeOrange,
    onTertiary = Color.White,
    background = LightBackground,
    onBackground = Color.Black,
    surface = LightSurface,
    onSurface = Color.Black,
    surfaceVariant = LightSecondaryBackground,
    onSurfaceVariant = Color(0xFF6C6C70),
    error = SnipeRed,
    onError = Color.White,
)

private val DarkColors = darkColorScheme(
    primary = SnipeAccentDark,
    onPrimary = Color.Black,
    primaryContainer = SnipeAccentDarkContainer,
    onPrimaryContainer = SnipeAccentDark,
    secondary = SnipeGray,
    onSecondary = Color.Black,
    secondaryContainer = SnipeAccentDarkContainer,
    onSecondaryContainer = SnipeAccentDark,
    tertiary = SnipeOrange,
    onTertiary = Color.Black,
    background = DarkBackground,
    onBackground = Color.White,
    surface = DarkSurface,
    onSurface = Color.White,
    surfaceVariant = DarkSecondaryBackground,
    onSurfaceVariant = Color(0xFFA1A1A6),
    error = SnipeRed,
    onError = Color.White,
)

@Composable
fun SnipeMobileTheme(
    themeMode: String = "system",
    content: @Composable () -> Unit,
) {
    val darkTheme = when (themeMode) {
        "dark" -> true
        "light" -> false
        else -> isSystemInDarkTheme()
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            // Bar colors come from enableEdgeToEdge(); only sync icon contrast here.
            val insets = WindowCompat.getInsetsController(window, view)
            insets.isAppearanceLightStatusBars = !darkTheme
            insets.isAppearanceLightNavigationBars = !darkTheme
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isNavigationBarContrastEnforced = false
            }
        }
    }

    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = SnipeTypography,
        content = content,
    )
}
