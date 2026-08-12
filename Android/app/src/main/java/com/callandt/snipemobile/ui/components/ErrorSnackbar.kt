package com.callandt.snipemobile.ui.components

import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import com.callandt.snipemobile.ui.util.L10n

@Composable
fun ErrorSnackbar(
    message: String?,
    snackbarHostState: SnackbarHostState,
    onDismiss: () -> Unit = {},
) {
    LaunchedEffect(message) {
        val text = message?.trim().orEmpty()
        // Unauthorized uses a wipe dialog, not this snackbar.
        if (text.isNotEmpty() && text != L10n.string("api_validate_unauthorized")) {
            snackbarHostState.showSnackbar(text)
            // Clear after show.
            onDismiss()
        } else if (text.isNotEmpty()) {
            onDismiss()
        }
    }
}
