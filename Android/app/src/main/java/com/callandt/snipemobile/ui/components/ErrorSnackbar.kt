package com.callandt.snipemobile.ui.components

import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect

@Composable
fun ErrorSnackbar(
    message: String?,
    snackbarHostState: SnackbarHostState,
    onDismiss: () -> Unit = {},
) {
    LaunchedEffect(message) {
        val text = message?.trim().orEmpty()
        if (text.isNotEmpty()) {
            snackbarHostState.showSnackbar(text)
            onDismiss()
        }
    }
}
