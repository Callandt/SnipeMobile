package com.callandt.snipemobile.ui.components

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

@Stable
class EntityDeleteState {
    var showConfirm by mutableStateOf(false)
    var isDeleting by mutableStateOf(false)
    var showError by mutableStateOf(false)
    var errorMessage by mutableStateOf("")

    fun requestDelete() {
        showConfirm = true
    }

    fun confirmDelete(
        scope: CoroutineScope,
        delete: suspend () -> Boolean,
        errorFromApi: () -> String?,
        onSuccess: () -> Unit,
    ) {
        scope.launch {
            showConfirm = false
            isDeleting = true
            val ok = delete()
            isDeleting = false
            if (ok) {
                onSuccess()
            } else {
                errorMessage = errorFromApi()?.trim()?.takeIf { it.isNotEmpty() }
                    ?: L10n.string("delete_failed")
                showError = true
            }
        }
    }
}

@Composable
fun rememberEntityDeleteState(): EntityDeleteState = remember { EntityDeleteState() }

@Composable
fun DetailEntityToolbarActions(
    baseUrl: String,
    webPath: String,
    onDeleteClick: (() -> Unit)? = null,
    deleteEnabled: Boolean = true,
) {
    val context = LocalContext.current
    val webUrl = remember(baseUrl, webPath) {
        "${baseUrl.trimEnd('/')}/$webPath"
    }

    Row {
        if (onDeleteClick != null) {
            IconButton(onClick = onDeleteClick, enabled = deleteEnabled) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = L10n.string("delete"),
                    tint = Color.Red,
                )
            }
        }
        IconButton(
            onClick = {
                runCatching {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(webUrl)))
                }
            },
        ) {
            Icon(
                imageVector = Icons.Default.Language,
                contentDescription = L10n.string("open_in_web"),
            )
        }
    }
}

@Composable
fun EntityDeleteSupport(
    state: EntityDeleteState,
    confirmTitle: String,
    confirmMessage: String,
    onConfirmDelete: () -> Unit,
) {
    if (state.showConfirm) {
        AlertDialog(
            onDismissRequest = { state.showConfirm = false },
            title = { Text(confirmTitle) },
            text = { Text(confirmMessage) },
            confirmButton = {
                TextButton(onClick = onConfirmDelete) {
                    Text(L10n.string("delete"), color = Color.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { state.showConfirm = false }) {
                    Text(L10n.string("cancel"))
                }
            },
        )
    }

    if (state.showError) {
        AlertDialog(
            onDismissRequest = { state.showError = false },
            title = { Text(L10n.string("delete_failed")) },
            text = { Text(state.errorMessage) },
            confirmButton = {
                TextButton(onClick = { state.showError = false }) {
                    Text(L10n.string("ok"))
                }
            },
        )
    }

    if (state.isDeleting) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .background(
                        MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
                        RoundedCornerShape(12.dp),
                    )
                    .padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                CircularProgressIndicator()
                Text(
                    text = L10n.string("deleting"),
                    modifier = Modifier.padding(top = 12.dp),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}
