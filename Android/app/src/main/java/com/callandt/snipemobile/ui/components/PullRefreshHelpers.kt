package com.callandt.snipemobile.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

/**
 * Pull-to-refresh indicator only while the user pulled.
 * Background sync (e.g. launch) does not show the spinner.
 */
@Composable
fun rememberUserPullRefreshing(
    isLoading: Boolean,
    onRefresh: () -> Unit,
): Pair<Boolean, () -> Unit> {
    var userRefreshing by remember { mutableStateOf(false) }
    LaunchedEffect(isLoading) {
        if (!isLoading) userRefreshing = false
    }
    return userRefreshing to {
        userRefreshing = true
        onRefresh()
    }
}
