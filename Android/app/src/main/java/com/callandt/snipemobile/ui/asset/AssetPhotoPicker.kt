package com.callandt.snipemobile.ui.asset

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.callandt.snipemobile.ui.util.L10n
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID

/** Pending gallery/camera image. */
internal data class PendingAssetImage(val mimeType: String, val bytes: ByteArray)

/** Resize for upload (max 1280px, ~0.8 quality). */
private fun Bitmap.toUploadJpegBytes(maxDimension: Int = 1280, quality: Int = 80): ByteArray {
    val largestSide = maxOf(width, height)
    val scaled = if (largestSide > maxDimension && largestSide > 0) {
        val scale = maxDimension.toFloat() / largestSide
        val newWidth = (width * scale).toInt().coerceAtLeast(1)
        val newHeight = (height * scale).toInt().coerceAtLeast(1)
        Bitmap.createScaledBitmap(this, newWidth, newHeight, true)
    } else {
        this
    }
    return ByteArrayOutputStream().use { stream ->
        scaled.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        stream.toByteArray()
    }
}

private fun createCameraCaptureUri(context: Context): Pair<File, Uri> {
    val dir = File(context.cacheDir, "camera").apply { mkdirs() }
    val file = File(dir, "capture_${UUID.randomUUID()}.jpg")
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    return file to uri
}

private fun decodeCapturedFile(file: File): PendingAssetImage? {
    if (!file.exists()) return null
    return runCatching {
        val bitmap = BitmapFactory.decodeFile(file.absolutePath) ?: return null
        PendingAssetImage("image/jpeg", bitmap.toUploadJpegBytes())
    }.getOrNull().also { file.delete() }
}

@Composable
private fun rememberFullResCameraLauncher(
    onImageCaptured: (PendingAssetImage) -> Unit,
): () -> Unit {
    val context = LocalContext.current
    var pendingCaptureFile by remember { mutableStateOf<File?>(null) }
    var pendingLaunch by remember { mutableStateOf(false) }
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }

    val cameraLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.TakePicture(),
    ) { success ->
        val file = pendingCaptureFile
        pendingCaptureFile = null
        if (success && file != null) {
            decodeCapturedFile(file)?.let(onImageCaptured)
        } else {
            file?.delete()
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        hasCameraPermission = granted
        if (granted && pendingLaunch) {
            pendingLaunch = false
            val (file, uri) = createCameraCaptureUri(context)
            pendingCaptureFile = file
            cameraLauncher.launch(uri)
        } else {
            pendingLaunch = false
        }
    }

    return {
        if (hasCameraPermission) {
            val (file, uri) = createCameraCaptureUri(context)
            pendingCaptureFile = file
            cameraLauncher.launch(uri)
        } else {
            pendingLaunch = true
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }
}

/** Asset photo picker for add/edit sheets. */
@Composable
internal fun AssetPhotoSection(
    pendingImage: PendingAssetImage?,
    onPendingImageChange: (PendingAssetImage?) -> Unit,
    existingImageUrl: String? = null,
    removeExistingImage: Boolean = false,
    onRemoveExistingImageChange: (Boolean) -> Unit = {},
) {
    val context = LocalContext.current
    val showsExistingImage = pendingImage == null && existingImageUrl != null && !removeExistingImage

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bitmap = runCatching {
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
        }.getOrNull()
        if (bitmap != null) {
            onPendingImageChange(PendingAssetImage("image/jpeg", bitmap.toUploadJpegBytes()))
            onRemoveExistingImageChange(false)
        }
    }

    val launchCamera = rememberFullResCameraLauncher { image ->
        onPendingImageChange(image)
        onRemoveExistingImageChange(false)
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FormSectionTitle(L10n.string("image"))

        val previewBitmap = remember(pendingImage) {
            pendingImage?.let { BitmapFactory.decodeByteArray(it.bytes, 0, it.bytes.size) }
        }
        when {
            previewBitmap != null -> {
                Image(
                    bitmap = previewBitmap.asImageBitmap(),
                    contentDescription = L10n.string("image"),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 180.dp)
                        .clip(RoundedCornerShape(12.dp)),
                    contentScale = ContentScale.Fit,
                )
            }
            showsExistingImage -> {
                AsyncImage(
                    model = existingImageUrl,
                    contentDescription = L10n.string("image"),
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 180.dp)
                        .clip(RoundedCornerShape(12.dp)),
                    contentScale = ContentScale.Fit,
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(
                onClick = {
                    galleryLauncher.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                    )
                },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Filled.PhotoLibrary, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("choose_from_library"), maxLines = 1)
            }
            OutlinedButton(
                onClick = launchCamera,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Filled.CameraAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("take_photo"), maxLines = 1)
            }
        }

        if (pendingImage != null || showsExistingImage) {
            OutlinedButton(
                onClick = {
                    if (pendingImage != null) {
                        onPendingImageChange(null)
                    } else {
                        onRemoveExistingImageChange(true)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) {
                Icon(Icons.Filled.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("remove_photo"))
            }
        }
    }
}

/** Multi-image photo section for check-in/out sheets. */
@Composable
internal fun AssetMultiPhotoSection(
    pendingImages: List<PendingAssetImage>,
    onPendingImagesChange: (List<PendingAssetImage>) -> Unit,
) {
    val context = LocalContext.current

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(maxItems = 10),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        val loaded = uris.mapNotNull { uri ->
            val bitmap = runCatching {
                context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
            }.getOrNull() ?: return@mapNotNull null
            PendingAssetImage("image/jpeg", bitmap.toUploadJpegBytes())
        }
        if (loaded.isNotEmpty()) onPendingImagesChange(pendingImages + loaded)
    }

    val singleGalleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val bitmap = runCatching {
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
        }.getOrNull() ?: return@rememberLauncherForActivityResult
        onPendingImagesChange(pendingImages + PendingAssetImage("image/jpeg", bitmap.toUploadJpegBytes()))
    }

    val launchCamera = rememberFullResCameraLauncher { image ->
        onPendingImagesChange(pendingImages + image)
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FormSectionTitle(L10n.string("photos"))

        pendingImages.forEachIndexed { index, image ->
            val previewBitmap = remember(image) {
                BitmapFactory.decodeByteArray(image.bytes, 0, image.bytes.size)
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Image(
                    bitmap = previewBitmap.asImageBitmap(),
                    contentDescription = L10n.string("image"),
                    modifier = Modifier
                        .weight(1f)
                        .heightIn(max = 120.dp)
                        .clip(RoundedCornerShape(12.dp)),
                    contentScale = ContentScale.Fit,
                )
                OutlinedButton(
                    onClick = { onPendingImagesChange(pendingImages.filterIndexed { i, _ -> i != index }) },
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) {
                    Icon(Icons.Filled.Delete, contentDescription = L10n.string("delete"), modifier = Modifier.size(18.dp))
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(
                onClick = {
                    if (ActivityResultContracts.PickVisualMedia.isPhotoPickerAvailable(context)) {
                        galleryLauncher.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    } else {
                        singleGalleryLauncher.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    }
                },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Filled.PhotoLibrary, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("choose_from_library"), maxLines = 1)
            }
            OutlinedButton(
                onClick = launchCamera,
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Filled.CameraAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("take_photo"), maxLines = 1)
            }
        }
    }
}
