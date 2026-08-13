package com.callandt.snipemobile.ui.components

import android.content.Context
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.callandt.snipemobile.data.api.SnipeApiClient
import com.callandt.snipemobile.data.model.Activity
import com.callandt.snipemobile.data.model.AssetFile
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.io.File

/** Download via API token; images stay in-app, other types go to FileProvider. */
class SnipeFilePreviewState(
    private val api: SnipeApiClient,
    private val context: Context,
    private val scope: CoroutineScope,
) {
    var imageFile by mutableStateOf<File?>(null)
        private set
    var error by mutableStateOf<String?>(null)
    var loadingId by mutableStateOf<Int?>(null)
        private set

    fun dismissImage() {
        imageFile = null
    }

    fun dismissError() {
        error = null
    }

    fun openAssetFile(assetId: Int, file: AssetFile) {
        scope.launch {
            loadingId = file.id
            val name = file.decodedFilename.ifEmpty { "file-${file.id}" }
            val local = if (file.isAcceptance) {
                file.url?.takeIf { it.isNotBlank() }?.let { api.downloadRemoteFile(it, name) }
            } else {
                api.downloadObjectFile("hardware", assetId, file.id, name)
                    ?: file.url?.takeIf { it.isNotBlank() }?.let { api.downloadRemoteFile(it, name) }
            }
            loadingId = null
            present(local, file.isImage)
        }
    }

    fun openActivityFile(itemType: String?, itemId: Int?, activity: Activity) {
        val file = activity.file ?: return
        scope.launch {
            loadingId = activity.id
            val name = file.decodedFilename.ifEmpty { file.filename ?: "file" }
            val action = activity.actionType.lowercase()
            val isAcceptance = action.contains("accept") || action.contains("eula") ||
                (file.url ?: "").lowercase().contains("stored-eula-file") ||
                name.lowercase().contains("accepted-eula")

            val local = when {
                isAcceptance -> file.url?.takeIf { it.isNotBlank() }?.let { api.downloadRemoteFile(it, name) }
                else -> {
                    val type = itemType ?: activity.item?.type
                    val id = itemId ?: activity.item?.id
                    val primary = if (type != null && id != null) {
                        api.downloadObjectFile(type, id, activity.id, name)
                    } else {
                        null
                    }
                    primary
                        ?: activity.item?.let { item ->
                            if (item.type != type || item.id != id) {
                                api.downloadObjectFile(item.type, item.id, activity.id, name)
                            } else {
                                null
                            }
                        }
                        ?: file.url?.takeIf { it.isNotBlank() }?.let { api.downloadRemoteFile(it, name) }
                }
            }
            loadingId = null
            present(local, file.isImage)
        }
    }

    private fun present(local: File?, isImage: Boolean) {
        if (local == null) {
            error = api.lastApiMessage.value ?: L10n.string("file_download_failed")
            return
        }
        if (isImage) {
            imageFile = local
        } else if (!openLocalFile(context, local)) {
            error = L10n.string("file_download_failed")
        }
    }
}

@Composable
fun rememberSnipeFilePreviewState(viewModel: AppViewModel): SnipeFilePreviewState {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    return remember(viewModel, context) {
        SnipeFilePreviewState(viewModel.apiClient, context, scope)
    }
}

@Composable
fun SnipeFilePreviewHost(state: SnipeFilePreviewState) {
    state.imageFile?.let { file ->
        Dialog(
            onDismissRequest = { state.dismissImage() },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black),
            ) {
                AsyncImage(
                    model = file,
                    contentDescription = L10n.string("image"),
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(12.dp)
                        .clip(RoundedCornerShape(8.dp)),
                    contentScale = ContentScale.Fit,
                )
                IconButton(
                    onClick = { state.dismissImage() },
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(8.dp),
                ) {
                    Icon(Icons.Default.Close, contentDescription = L10n.string("close"), tint = Color.White)
                }
            }
        }
    }
    if (state.loadingId != null) {
        Dialog(onDismissRequest = {}) {
            Box(
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(12.dp))
                    .padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
        }
    }
    state.error?.let { message ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { state.dismissError() },
            title = { Text(L10n.string("error")) },
            text = { Text(message) },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { state.dismissError() }) {
                    Text(L10n.string("ok"))
                }
            },
        )
    }
}

fun openLocalFile(context: Context, file: File): Boolean {
    val uri = runCatching {
        FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    }.getOrNull() ?: return false
    val mime = MimeTypeMap.getSingleton()
        .getMimeTypeFromExtension(file.extension.lowercase())
        ?: "*/*"
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, mime)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return runCatching {
        context.startActivity(Intent.createChooser(intent, file.name).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        })
        true
    }.getOrDefault(false)
}
