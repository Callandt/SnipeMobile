package com.callandt.snipemobile.ui.scanner

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.callandt.snipemobile.data.api.DellQrLink
import com.callandt.snipemobile.data.api.SnipeITQRLink
import com.callandt.snipemobile.ui.util.L10n
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import java.net.URI
import java.util.concurrent.Executors

enum class QrScannerMode {
    SnipeIT,
    Dell,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QrScannerScreen(
    onBack: () -> Unit,
    onLinkParsed: (SnipeITQRLink) -> Unit,
    onError: (String) -> Unit,
    mode: QrScannerMode = QrScannerMode.SnipeIT,
    onDellUrlScanned: (URI) -> Unit = {},
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    var handled by remember { mutableStateOf(false) }
    val errorThrottle = remember { java.util.concurrent.atomic.AtomicLong(0L) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasCameraPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    val title = when (mode) {
        QrScannerMode.SnipeIT -> L10n.string("scan_qr")
        QrScannerMode.Dell -> L10n.string("scan_dell_qr")
    }
    val hint = when (mode) {
        QrScannerMode.SnipeIT -> L10n.string("scan_hint")
        QrScannerMode.Dell -> L10n.string("dell_qr_scan_footer")
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                actions = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.Close, contentDescription = L10n.string("close"))
                    }
                },
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentAlignment = Alignment.Center,
        ) {
            if (!hasCameraPermission) {
                Text(
                    L10n.string("camera_permission_required"),
                    style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.padding(24.dp),
                    textAlign = TextAlign.Center,
                )
            } else {
                AndroidView(
                    factory = { ctx ->
                        PreviewView(ctx).also { previewView ->
                            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                            cameraProviderFuture.addListener({
                                val cameraProvider = cameraProviderFuture.get()
                                val preview = Preview.Builder().build().also {
                                    it.surfaceProvider = previewView.surfaceProvider
                                }
                                val scanner = BarcodeScanning.getClient()
                                val analysis = ImageAnalysis.Builder()
                                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                                    .build()
                                analysis.setAnalyzer(Executors.newSingleThreadExecutor()) { imageProxy ->
                                    val mediaImage = imageProxy.image
                                    if (mediaImage != null && !handled) {
                                        val image = InputImage.fromMediaImage(
                                            mediaImage,
                                            imageProxy.imageInfo.rotationDegrees,
                                        )
                                        scanner.process(image)
                                            .addOnSuccessListener { barcodes ->
                                                val raw = barcodes.firstOrNull()?.rawValue
                                                    ?: return@addOnSuccessListener
                                                if (handled) return@addOnSuccessListener

                                                when (mode) {
                                                    QrScannerMode.Dell -> {
                                                        val url = DellQrLink.parse(raw)
                                                        if (url != null &&
                                                            DellQrLink.isDellUrl(url) &&
                                                            !DellQrLink.extractServiceTag(url).isNullOrBlank()
                                                        ) {
                                                            handled = true
                                                            previewView.post { onDellUrlScanned(url) }
                                                        } else {
                                                            reportInvalid(previewView, errorThrottle, onError, L10n.string("invalid_dell_qr"))
                                                        }
                                                    }
                                                    QrScannerMode.SnipeIT -> {
                                                        val link = SnipeITQRLink.parse(raw)
                                                        if (link != null) {
                                                            handled = true
                                                            previewView.post { onLinkParsed(link) }
                                                        } else {
                                                            val dellUrl = DellQrLink.parse(raw)
                                                            if (dellUrl != null &&
                                                                DellQrLink.isDellUrl(dellUrl) &&
                                                                !DellQrLink.extractServiceTag(dellUrl).isNullOrBlank()
                                                            ) {
                                                                handled = true
                                                                previewView.post { onDellUrlScanned(dellUrl) }
                                                            } else {
                                                                reportInvalid(
                                                                    previewView,
                                                                    errorThrottle,
                                                                    onError,
                                                                    L10n.string("invalid_qr_unrecognized"),
                                                                )
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            .addOnCompleteListener { imageProxy.close() }
                                    } else {
                                        imageProxy.close()
                                    }
                                }
                                runCatching {
                                    cameraProvider.unbindAll()
                                    cameraProvider.bindToLifecycle(
                                        lifecycleOwner,
                                        CameraSelector.DEFAULT_BACK_CAMERA,
                                        preview,
                                        analysis,
                                    )
                                }
                            }, ContextCompat.getMainExecutor(ctx))
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )

                Box(
                    modifier = Modifier
                        .size(260.dp)
                        .border(2.dp, Color.White, RoundedCornerShape(16.dp))
                        .background(Color.Transparent),
                )

                Text(
                    text = hint,
                    style = MaterialTheme.typography.bodyLarge,
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .background(Color.Black.copy(alpha = 0.45f))
                        .padding(horizontal = 24.dp, vertical = 20.dp),
                )
            }
        }
    }
}

private fun reportInvalid(
    previewView: PreviewView,
    errorThrottle: java.util.concurrent.atomic.AtomicLong,
    onError: (String) -> Unit,
    message: String,
) {
    val now = System.currentTimeMillis()
    if (now - errorThrottle.get() > 2500) {
        errorThrottle.set(now)
        previewView.post { onError(message) }
    }
}
