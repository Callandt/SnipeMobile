package com.callandt.snipemobile.ui.navigation

import androidx.lifecycle.Lifecycle
import androidx.navigation.NavController

fun NavController.navigateWhenResumed(route: String) {
    val entry = currentBackStackEntry ?: return
    if (!entry.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return
    navigate(route) {
        launchSingleTop = true
    }
}

fun NavController.navigateFromListWhenResumed(route: String) {
    val entry = currentBackStackEntry ?: return
    if (!entry.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return
    navigate(route) {
        launchSingleTop = true
        popUpTo(Routes.Main) { inclusive = false }
    }
}

fun NavController.popWhenResumed() {
    val entry = currentBackStackEntry ?: return
    if (!entry.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) return
    if (currentDestination?.route == Routes.Main) return
    popBackStack()
}
