package com.callandt.snipemobile.ui.asset

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.text.format.Formatter
import android.webkit.MimeTypeMap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.TextSnippet
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderZip
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.api.UploadFile
import com.callandt.snipemobile.data.model.AssetFile
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.ErrorSnackbar
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch
import java.util.Locale
import java.util.UUID

/** Asset files tab: list + upload + delete. */
@Composable
fun AssetFilesTab(assetId: Int, viewModel: AppViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var files by remember(assetId) { mutableStateOf<List<AssetFile>>(emptyList()) }
    var isLoading by remember(assetId) { mutableStateOf(true) }
    var showAddSheet by remember { mutableStateOf(false) }
    var filePendingDelete by remember { mutableStateOf<AssetFile?>(null) }
    var isDeleting by remember { mutableStateOf(false) }
    var noticeMessage by remember { mutableStateOf<String?>(null) }
    val snackbarHostState = remember { SnackbarHostState() }

    suspend fun reload() {
        if (files.isEmpty()) isLoading = true
        files = viewModel.apiClient.fetchAssetFiles(assetId)
        isLoading = false
    }

    LaunchedEffect(assetId) { reload() }

    Box(modifier = Modifier.fillMaxSize()) {
        when {
            isLoading && files.isEmpty() -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            files.isEmpty() -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            L10n.string("no_files"),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        Text(
                            L10n.string("files_empty_desc"),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
            else -> {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp, 16.dp, 16.dp, 88.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    items(files, key = { it.id }) { file ->
                        AssetFileRow(
                            file = file,
                            onClick = {
                                val url = file.url?.takeIf { it.isNotBlank() }
                                if (url != null) {
                                    runCatching {
                                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                    }.onFailure {
                                        noticeMessage = L10n.string("file_download_failed")
                                    }
                                } else {
                                    noticeMessage = L10n.string("file_download_failed")
                                }
                            },
                            onDelete = if (file.canDelete) {
                                { filePendingDelete = file }
                            } else {
                                null
                            },
                        )
                    }
                }
            }
        }

        FloatingActionButton(
            onClick = { showAddSheet = true },
            modifier = Modifier.align(Alignment.BottomEnd).padding(20.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = L10n.string("add_files"))
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 88.dp),
        )
    }

    if (showAddSheet) {
        AssetAddFilesSheet(
            assetId = assetId,
            viewModel = viewModel,
            onDismiss = { showAddSheet = false },
            onUploaded = { scope.launch { reload() } },
        )
    }

    filePendingDelete?.let { file ->
        AlertDialog(
            onDismissRequest = { if (!isDeleting) filePendingDelete = null },
            title = { Text(L10n.string("delete_file_confirm_title")) },
            text = { Text(L10n.string("delete_file_confirm_message")) },
            confirmButton = {
                TextButton(
                    enabled = !isDeleting,
                    onClick = {
                        scope.launch {
                            isDeleting = true
                            val success = viewModel.apiClient.deleteAssetFile(assetId, file.id)
                            isDeleting = false
                            filePendingDelete = null
                            if (success) {
                                files = files.filterNot { it.id == file.id }
                            } else {
                                noticeMessage = viewModel.apiClient.lastApiMessage.value
                                    ?: L10n.string("file_delete_failed")
                            }
                        }
                    },
                ) { Text(L10n.string("delete")) }
            },
            dismissButton = {
                TextButton(onClick = { filePendingDelete = null }, enabled = !isDeleting) {
                    Text(L10n.string("cancel"))
                }
            },
        )
    }

    ErrorSnackbar(
        message = noticeMessage,
        snackbarHostState = snackbarHostState,
        onDismiss = { noticeMessage = null },
    )
}

@Composable
private fun AssetFileRow(
    file: AssetFile,
    onClick: () -> Unit,
    onDelete: (() -> Unit)?,
) {
    val accentColor = fileAccentColor(file)
    val titleText = file.decodedNote.ifEmpty { file.shortFilename.ifEmpty { "#${file.id}" } }
    val subtitleText = file.decodedNote.takeIf { it.isNotEmpty() }?.let { file.shortFilename.takeIf { s -> s.isNotEmpty() } }
    val dateText = file.createdAt?.localizedDisplay(includeTime = true)

    Surface(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(accentColor.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(fileIconFor(file), contentDescription = null, tint = accentColor)
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = titleText,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!dateText.isNullOrBlank()) {
                    Text(dateText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (!subtitleText.isNullOrBlank()) {
                    Text(
                        subtitleText,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            if (onDelete != null) {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Filled.Delete, contentDescription = L10n.string("delete"))
                }
            }
        }
    }
}

@Composable
private fun fileAccentColor(file: AssetFile): Color = when {
    file.isAcceptance || file.isPDF -> MaterialTheme.colorScheme.error
    file.isImage -> MaterialTheme.colorScheme.primary
    else -> MaterialTheme.colorScheme.tertiary
}

private fun fileIconFor(file: AssetFile): ImageVector {
    val lower = file.decodedFilename.lowercase(Locale.US)
    return when {
        file.isAcceptance || file.isPDF -> Icons.Filled.PictureAsPdf
        file.isImage -> Icons.Filled.Image
        lower.endsWith(".zip") || lower.endsWith(".rar") -> Icons.Filled.FolderZip
        listOf(".mp4", ".mov", ".webm", ".mp3", ".wav", ".ogg").any { lower.endsWith(it) } -> Icons.Filled.Movie
        listOf(".xls", ".xlsx", ".ods", ".csv").any { lower.endsWith(it) } -> Icons.Filled.TableChart
        listOf(".doc", ".docx", ".odt", ".rtf", ".txt").any { lower.endsWith(it) } -> Icons.AutoMirrored.Filled.TextSnippet
        else -> Icons.AutoMirrored.Filled.InsertDriveFile
    }
}

/** Snipe-IT upload allowlist. */
private val allowedUploadExtensions = setOf(
    "avif", "doc", "docx", "gif", "ico", "jfif", "jpeg", "jpg", "json", "key", "lic",
    "mov", "mp3", "mp4", "odp", "ods", "odt", "ogg", "pdf", "png", "rar", "rtf",
    "svg", "txt", "wav", "webm", "webp", "xls", "xlsx", "xml", "zip",
)

private data class PendingUploadFile(
    val id: String = UUID.randomUUID().toString(),
    val filename: String,
    val mimeType: String,
    val data: ByteArray,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AssetAddFilesSheet(
    assetId: Int,
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onUploaded: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var pendingFiles by remember { mutableStateOf<List<PendingUploadFile>>(emptyList()) }
    var notes by remember { mutableStateOf("") }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val photoPickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        val startIndex = pendingFiles.count { it.filename.startsWith("photo-") }
        val loaded = uris.mapIndexedNotNull { index, uri ->
            val bytes = runCatching {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            }.getOrNull() ?: return@mapIndexedNotNull null
            val mimeType = context.contentResolver.getType(uri) ?: "image/jpeg"
            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "jpg"
            PendingUploadFile(filename = "photo-${startIndex + index + 1}.$ext", mimeType = mimeType, data = bytes)
        }
        pendingFiles = pendingFiles + loaded
    }

    val documentPickerLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        var rejected = 0
        val loaded = uris.mapNotNull { uri ->
            val filename = queryDisplayName(context, uri) ?: uri.lastPathComponent()
            val extension = filename.substringAfterLast('.', "").lowercase(Locale.US)
            if (extension.isEmpty() || extension !in allowedUploadExtensions) {
                rejected += 1
                return@mapNotNull null
            }
            val bytes = runCatching {
                context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            }.getOrNull() ?: return@mapNotNull null
            val mimeType = context.contentResolver.getType(uri)
                ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                ?: "application/octet-stream"
            PendingUploadFile(filename = filename, mimeType = mimeType, data = bytes)
        }
        pendingFiles = pendingFiles + loaded
        if (rejected > 0) errorMessage = L10n.string("files_type_not_allowed")
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(L10n.string("add_files")) },
                    navigationIcon = {
                        TextButton(onClick = { if (!isSaving) onDismiss() }, enabled = !isSaving) {
                            Text(L10n.string("cancel"))
                        }
                    },
                    actions = {
                        if (isSaving) {
                            CircularProgressIndicator(modifier = Modifier.padding(end = 16.dp).size(24.dp))
                        } else {
                            TextButton(
                                enabled = pendingFiles.isNotEmpty(),
                                onClick = {
                                    isSaving = true
                                    scope.launch {
                                        val uploadFiles = pendingFiles.map { UploadFile(it.filename, it.mimeType, it.data) }
                                        val success = viewModel.apiClient.uploadAssetFiles(
                                            assetId,
                                            uploadFiles,
                                            notes.trim().takeIf { it.isNotEmpty() },
                                        )
                                        isSaving = false
                                        if (success) {
                                            onUploaded()
                                            onDismiss()
                                        } else {
                                            errorMessage = viewModel.apiClient.lastApiMessage.value
                                                ?: L10n.string("file_upload_failed")
                                        }
                                    }
                                },
                            ) { Text(L10n.string("upload")) }
                        }
                    },
                )
            },
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                FormSectionTitle(L10n.string("files"))

                pendingFiles.forEach { file ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(
                            modifier = Modifier
                                .size(40.dp)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.surfaceVariant),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                if (file.mimeType.startsWith("image/")) Icons.Filled.Image else Icons.AutoMirrored.Filled.InsertDriveFile,
                                contentDescription = null,
                            )
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(file.filename, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                Formatter.formatShortFileSize(context, file.data.size.toLong()),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(onClick = { pendingFiles = pendingFiles.filterNot { it.id == file.id } }) {
                            Icon(Icons.Filled.Close, contentDescription = L10n.string("delete"))
                        }
                    }
                }

                OutlinedButton(
                    onClick = { documentPickerLauncher.launch(arrayOf("*/*")) },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.Folder, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(" " + L10n.string("choose_files"))
                }
                OutlinedButton(
                    onClick = {
                        photoPickerLauncher.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Filled.PhotoLibrary, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(" " + L10n.string("choose_from_library"))
                }
                if (pendingFiles.isNotEmpty()) {
                    OutlinedButton(
                        onClick = { pendingFiles = emptyList() },
                        modifier = Modifier.fillMaxWidth(),
                    ) { Text(L10n.string("remove_selected_files")) }
                }
                Text(
                    L10n.string("files_upload_footer"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                FormSectionTitle(L10n.string("notes"))
                OutlinedTextField(
                    value = notes,
                    onValueChange = { notes = it },
                    label = { Text(L10n.string("notes")) },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                )
            }
        }
    }

    if (errorMessage != null) {
        AlertDialog(
            onDismissRequest = { errorMessage = null },
            title = { Text(L10n.string("error")) },
            text = { Text(errorMessage.orEmpty()) },
            confirmButton = {
                TextButton(onClick = { errorMessage = null }) { Text(L10n.string("ok")) }
            },
        )
    }
}

private fun queryDisplayName(context: android.content.Context, uri: Uri): String? =
    runCatching {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) cursor.getString(nameIndex) else null
        }
    }.getOrNull()

private fun Uri.lastPathComponent(): String = lastPathSegment?.substringAfterLast('/') ?: "file"
