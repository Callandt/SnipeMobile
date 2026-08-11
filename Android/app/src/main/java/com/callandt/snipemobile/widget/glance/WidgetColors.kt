package com.callandt.snipemobile.widget.glance

import androidx.compose.ui.graphics.Color
import androidx.glance.color.ColorProvider
import androidx.glance.unit.ColorProvider as SolidColorProvider

object WidgetColors {
    val brandLight = Color(0xFF0F3D66)
    val brandDark = Color(0xFF8CC7FF)
    val overdue = Color(0xFFFF3B30)
    val dueToday = Color(0xFFFF9500)
    val dueSoonLight = Color(0xFFD9A600)
    val dueSoonDark = Color(0xFFFFD60A)
    val maintenance = Color(0xFFFF9500)
    val stock = Color(0xFFAF52DE)
    val available = Color(0xFF34C759)

    val pageBackground = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF000000))
    val cardBackground = ColorProvider(day = Color(0xFFF2F2F7), night = Color(0xFF1C1C1E))
    val primaryText = ColorProvider(day = Color(0xFF000000), night = Color(0xFFFFFFFF))
    val secondaryText = ColorProvider(day = Color(0xFF8E8E93), night = Color(0xFF8E8E93))
    val tertiaryText = ColorProvider(day = Color(0xFFAEAEB2), night = Color(0xFF636366))
    val separator = ColorProvider(day = Color(0xFFC6C6C8), night = Color(0xFF38383A))
    val brand = ColorProvider(day = brandLight, night = brandDark)
    val overdueProvider = SolidColorProvider(overdue)
    val dueTodayProvider = SolidColorProvider(dueToday)
    val dueSoon = ColorProvider(day = dueSoonLight, night = dueSoonDark)
    val maintenanceProvider = SolidColorProvider(maintenance)
    val assetsProvider = brand
    val stockProvider = SolidColorProvider(stock)
    val availableProvider = SolidColorProvider(available)
}
