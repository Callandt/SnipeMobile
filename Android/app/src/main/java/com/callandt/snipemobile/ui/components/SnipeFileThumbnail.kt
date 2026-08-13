package com.callandt.snipemobile.ui.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.api.SnipeApiClient
import kotlinx.coroutines.isActive
import kotlin.math.max

object SnipeFileThumbnailCache {
    private val cache = LruCache<String, ImageBitmap>(40)

    fun get(key: String): ImageBitmap? = cache.get(key)

    fun put(key: String, image: ImageBitmap) {
        cache.put(key, image)
    }

    fun cacheKey(objectType: String, objectId: Int, fileId: Int): String =
        "${objectType.lowercase()}:$objectId:$fileId"
}

@Composable
fun SnipeFileThumbnail(
    apiClient: SnipeApiClient,
    objectType: String,
    objectId: Int,
    fileId: Int,
    filename: String = "",
    size: Dp = 44.dp,
    cornerRadius: Dp = 10.dp,
) {
    val cacheKey = remember(objectType, objectId, fileId) {
        SnipeFileThumbnailCache.cacheKey(objectType, objectId, fileId)
    }
    var image by remember(cacheKey) { mutableStateOf(SnipeFileThumbnailCache.get(cacheKey)) }
    var failed by remember(cacheKey) { mutableStateOf(false) }
    val maxPx = with(LocalDensity.current) { max((size * 3).roundToPx(), 180) }

    LaunchedEffect(cacheKey) {
        if (image != null) return@LaunchedEffect
        failed = false
        val file = apiClient.downloadObjectFile(
            objectType = objectType,
            objectId = objectId,
            fileId = fileId,
            preferredFilename = filename.ifEmpty { "thumb-$fileId.jpg" },
        )
        if (!isActive) {
            file?.delete()
            return@LaunchedEffect
        }
        if (file == null) {
            failed = true
            return@LaunchedEffect
        }
        val bitmap = decodeThumbnail(file.absolutePath, maxPx)
        file.delete()
        if (!isActive) return@LaunchedEffect
        if (bitmap == null) {
            failed = true
            return@LaunchedEffect
        }
        val imageBitmap = bitmap.asImageBitmap()
        SnipeFileThumbnailCache.put(cacheKey, imageBitmap)
        image = imageBitmap
    }

    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = Modifier
            .size(size)
            .clip(shape)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
        contentAlignment = Alignment.Center,
    ) {
        when {
            image != null -> Image(
                bitmap = image as ImageBitmap,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
            failed -> Icon(
                imageVector = Icons.Default.Image,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(size * 0.38f),
            )
            else -> CircularProgressIndicator(
                modifier = Modifier.size(size * 0.35f),
                strokeWidth = 2.dp,
            )
        }
    }
}

private fun decodeThumbnail(path: String, maxPx: Int): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    val largest = max(bounds.outWidth, bounds.outHeight).coerceAtLeast(1)
    var sample = 1
    while (largest / sample > maxPx * 2) sample *= 2
    val opts = BitmapFactory.Options().apply { inSampleSize = sample }
    val decoded = BitmapFactory.decodeFile(path, opts) ?: return null
    val w = decoded.width
    val h = decoded.height
    val longest = max(w, h).coerceAtLeast(1)
    if (longest <= maxPx) return decoded
    val scale = maxPx.toFloat() / longest
    return Bitmap.createScaledBitmap(
        decoded,
        (w * scale).toInt().coerceAtLeast(1),
        (h * scale).toInt().coerceAtLeast(1),
        true,
    ).also { if (it != decoded) decoded.recycle() }
}
