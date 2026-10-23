package com.callandt.snipemobile.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

// Spinner only for a user pull, not a background sync.
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
