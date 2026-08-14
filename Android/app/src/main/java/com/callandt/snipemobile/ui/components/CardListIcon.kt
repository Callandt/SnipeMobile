package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.annotation.ExperimentalCoilApi
import coil.compose.AsyncImagePainter
import coil.compose.SubcomposeAsyncImage
import coil.compose.SubcomposeAsyncImageContent
import coil.imageLoader
import coil.request.CachePolicy
import coil.request.ImageRequest
import com.callandt.snipemobile.ui.util.resolveSnipeImageUrl
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class CardPhotoSettings(
    val enabled: Boolean = false,
    val baseUrl: String = "",
)

val LocalCardPhotoSettings = compositionLocalOf { CardPhotoSettings() }

object CardPhotoCache {
    private val _generation = MutableStateFlow(0)
    val generation: StateFlow<Int> = _generation.asStateFlow()

    @OptIn(ExperimentalCoilApi::class)
    fun evict(context: android.content.Context, path: String?, baseUrl: String) {
        val url = resolveSnipeImageUrl(baseUrl, path)
        val loader = context.imageLoader
        val candidates = listOfNotNull(url, url?.substringBefore("?"))
        if (candidates.isEmpty()) {
            _generation.value += 1
            return
        }
        loader.memoryCache?.let { mem ->
            mem.keys.filter { key -> candidates.any { it in key.key } }.forEach { mem.remove(it) }
        }
        loader.diskCache?.let { disk ->
            candidates.forEach { disk.remove(it) }
        }
        _generation.value += 1
    }
}

/** Card icon, or the item photo if that setting is on. */
@Composable
fun CardListIcon(
    imageVector: ImageVector,
    imagePath: String?,
    modifier: Modifier = Modifier,
    cacheBuster: String? = null,
    size: Dp = 36.dp,
    cornerRadius: Dp = 8.dp,
    tint: Color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.45f),
    iconBackground: Color? = null,
    iconPadding: Dp = 0.dp,
) {
    val settings = LocalCardPhotoSettings.current
    val url = if (settings.enabled) {
        resolveSnipeImageUrl(settings.baseUrl, imagePath, cacheBuster)
    } else {
        null
    }
    val photoSize = maxOf(size, 44.dp)
    val photoCorner = maxOf(cornerRadius, 10.dp)
    val context = LocalContext.current
    val px = with(LocalDensity.current) { photoSize.roundToPx() }
    val generation by CardPhotoCache.generation.collectAsState()
    val request = remember(url, px, generation) {
        url?.let {
            ImageRequest.Builder(context)
                .data(it)
                .size(px)
                .memoryCachePolicy(CachePolicy.ENABLED)
                .diskCachePolicy(CachePolicy.ENABLED)
                .crossfade(false)
                .build()
        }
    }

    if (request != null) {
        Box(
            modifier = modifier
                .size(photoSize)
                .clip(RoundedCornerShape(photoCorner))
                .background(MaterialTheme.colorScheme.surface),
            contentAlignment = Alignment.Center,
        ) {
            SubcomposeAsyncImage(
                model = request,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                alignment = Alignment.Center,
                contentScale = ContentScale.Fit,
            ) {
                when (painter.state) {
                    is AsyncImagePainter.State.Success -> SubcomposeAsyncImageContent(
                        modifier = Modifier.fillMaxSize(),
                        alignment = Alignment.Center,
                        contentScale = ContentScale.Fit,
                    )
                    else -> CardListFallbackIcon(
                        imageVector = imageVector,
                        size = photoSize,
                        cornerRadius = photoCorner,
                        tint = tint,
                        iconBackground = iconBackground,
                        iconPadding = iconPadding,
                    )
                }
            }
        }
    } else {
        CardListFallbackIcon(
            imageVector = imageVector,
            modifier = modifier,
            size = size,
            cornerRadius = cornerRadius,
            tint = tint,
            iconBackground = iconBackground,
            iconPadding = iconPadding,
        )
    }
}

@Composable
private fun CardListFallbackIcon(
    imageVector: ImageVector,
    size: Dp,
    cornerRadius: Dp,
    tint: Color,
    iconBackground: Color?,
    iconPadding: Dp,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .size(size)
            .then(
                if (iconBackground != null) {
                    Modifier
                        .clip(RoundedCornerShape(cornerRadius))
                        .background(iconBackground)
                        .padding(iconPadding)
                } else {
                    Modifier
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(if (iconBackground != null && iconPadding > 0.dp) size - iconPadding * 2 else size),
        )
    }
}
