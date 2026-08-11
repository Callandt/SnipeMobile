package com.callandt.snipemobile.ui.asset

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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.callandt.snipemobile.data.api.SnipeITQRLink
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.PickerItem
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.components.SearchablePickerField
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.matchesSearch
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import kotlinx.coroutines.launch
import java.util.Date
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** Bulk audit: pick assets, shared options, one audit call each. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BulkAuditSheet(
    viewModel: AppViewModel,
    onDismiss: () -> Unit,
    onSaved: () -> Unit = {},
) {
    val assets by viewModel.assets.collectAsState()
    val locations by viewModel.locations.collectAsState()

    var selectedAssetIds by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var showAssetPicker by remember { mutableStateOf(false) }
    var showScanner by remember { mutableStateOf(false) }

    var selectedLocationId by remember { mutableIntStateOf(0) }
    var updateLocation by remember { mutableStateOf(false) }
    var setNextAuditDate by remember { mutableStateOf(false) }
    var nextAuditDateText by remember { mutableStateOf(formatApiDate(Date())) }
    var notes by remember { mutableStateOf("") }

    var isSaving by remember { mutableStateOf(false) }
    var resultMessage by remember { mutableStateOf<String?>(null) }

    val scope = rememberCoroutineScope()
    val canSave = selectedAssetIds.isNotEmpty() && !isSaving

    val selectedAssets = remember(assets, selectedAssetIds) {
        assets.filter { selectedAssetIds.contains(it.id) }
            .sortedBy { it.decodedAssetTag.lowercase() }
    }

    LaunchedEffect(Unit) {
        if (locations.isEmpty()) viewModel.apiClient.fetchLocations()
    }

    suspend fun save() {
        isSaving = true
        val nextStr = if (setNextAuditDate) parseApiDate(nextAuditDateText)?.let { formatApiDate(it) } else null
        val locationIdOpt = selectedLocationId.takeIf { it > 0 }
        val noteOpt = notes.trim().takeIf { it.isNotEmpty() }

        var successCount = 0
        var failedCount = 0
        for (id in selectedAssetIds) {
            val asset = assets.firstOrNull { it.id == id }
            val tag = asset?.decodedAssetTag.orEmpty()
            if (asset == null || tag.isEmpty()) {
                failedCount += 1
                continue
            }
            val ok = viewModel.apiClient.auditAsset(
                assetTag = tag,
                assetId = asset.id,
                locationId = locationIdOpt,
                updateLocation = updateLocation,
                nextAuditDate = nextStr,
                note = noteOpt,
            )
            if (ok) successCount += 1 else failedCount += 1
        }

        viewModel.syncInBackground()
        onSaved()
        isSaving = false
        if (failedCount == 0) {
            onDismiss()
        } else {
            resultMessage = L10n.string("bulk_audit_result_success", successCount) +
                "\n" + L10n.string("bulk_audit_result_partial", failedCount)
        }
    }

    AssetFullScreenSheet(onDismiss = { if (!isSaving) onDismiss() }) {
        AssetFormSheetScaffold(
            title = L10n.string("add_audit"),
            saveLabel = L10n.string("bulk_audit_run", selectedAssetIds.size),
            isSaving = isSaving,
            canSave = canSave,
            onDismiss = { if (!isSaving) onDismiss() },
            onSave = { scope.launch { save() } },
        ) {
            FormSectionTitle(L10n.string("assets"))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    L10n.string("assets_selected_count", selectedAssetIds.size),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            TextButton(onClick = { showAssetPicker = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.Checklist, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("select_assets"))
            }
            TextButton(onClick = { showScanner = true }, modifier = Modifier.fillMaxWidth()) {
                Icon(Icons.Filled.QrCodeScanner, contentDescription = null, modifier = Modifier.size(18.dp))
                Text(" " + L10n.string("scan_assets"))
            }
            if (selectedAssets.isNotEmpty()) {
                Column {
                    selectedAssets.forEach { asset ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { selectedAssetIds = selectedAssetIds - asset.id }
                                .padding(vertical = 6.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    asset.decodedModelName.ifEmpty { asset.decodedName },
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                val subtitle = listOf(asset.decodedAssetTag, asset.decodedName)
                                    .filter { it.isNotEmpty() }
                                    .joinToString(" · ")
                                if (subtitle.isNotEmpty()) {
                                    Text(
                                        subtitle,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            Icon(Icons.Filled.Close, contentDescription = L10n.string("delete"))
                        }
                    }
                    TextButton(onClick = { selectedAssetIds = emptySet() }) {
                        Text(L10n.string("clear_selection"))
                    }
                }
            }

            FormSectionTitle(L10n.string("bulk_audit_options"))
            if (locations.isNotEmpty()) {
                SearchablePickerField(
                    label = L10n.string("location_optional"),
                    items = locations.map { PickerItem(it.id, it.decodedName) },
                    selectedId = selectedLocationId.takeIf { it > 0 },
                    placeholder = L10n.string("none"),
                    onSelected = { selectedLocationId = it.id },
                )
                if (selectedLocationId != 0) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(L10n.string("bulk_audit_update_location"), modifier = Modifier.weight(1f))
                        Switch(checked = updateLocation, onCheckedChange = { updateLocation = it })
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L10n.string("bulk_audit_set_next_audit"), modifier = Modifier.weight(1f))
                Switch(checked = setNextAuditDate, onCheckedChange = { setNextAuditDate = it })
            }
            if (setNextAuditDate) {
                OutlinedTextField(
                    value = nextAuditDateText,
                    onValueChange = { nextAuditDateText = it },
                    label = { Text(L10n.string("next_audit_date")) },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                )
            }
            OutlinedTextField(
                value = notes,
                onValueChange = { notes = it },
                label = { Text(L10n.string("notes")) },
                modifier = Modifier.fillMaxWidth(),
                minLines = 2,
            )
        }
    }

    if (showAssetPicker) {
        AssetFullScreenSheet(onDismiss = { showAssetPicker = false }) {
            AssetMultiSelectScreen(
                assets = assets,
                selectedAssetIds = selectedAssetIds,
                onSelectionChange = { selectedAssetIds = it },
                onDone = { showAssetPicker = false },
            )
        }
    }

    if (showScanner) {
        AssetFullScreenSheet(onDismiss = { showScanner = false }) {
            BulkAssetScannerScreen(
                viewModel = viewModel,
                onAssetResolved = { asset -> selectedAssetIds = selectedAssetIds + asset.id },
                onDone = { showScanner = false },
            )
        }
    }

    if (resultMessage != null) {
        AlertDialog(
            onDismissRequest = { resultMessage = null; onDismiss() },
            title = { Text(L10n.string("add_audit")) },
            text = { Text(resultMessage.orEmpty()) },
            confirmButton = {
                TextButton(onClick = { resultMessage = null; onDismiss() }) { Text(L10n.string("ok")) }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AssetMultiSelectScreen(
    assets: List<Asset>,
    selectedAssetIds: Set<Int>,
    onSelectionChange: (Set<Int>) -> Unit,
    onDone: () -> Unit,
) {
    var searchQuery by remember { mutableStateOf("") }
    val filtered = remember(assets, searchQuery) {
        assets.filter {
            matchesSearch(
                it.decodedName,
                it.decodedModelName,
                it.decodedAssetTag,
                it.decodedAssignedToName,
                query = searchQuery,
            )
        }
    }

    Scaffold(
        topBar = {
            SearchTopBar(
                title = L10n.string("select_assets"),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                onBack = onDone,
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    L10n.string("assets_selected_count", selectedAssetIds.size),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
                if (selectedAssetIds.isNotEmpty()) {
                    TextButton(onClick = { onSelectionChange(emptySet()) }) {
                        Text(L10n.string("clear_selection"))
                    }
                }
            }
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                items(filtered, key = { it.id }) { asset ->
                    val isSelected = selectedAssetIds.contains(asset.id)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onSelectionChange(
                                    if (isSelected) selectedAssetIds - asset.id else selectedAssetIds + asset.id,
                                )
                            }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            if (isSelected) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
                            contentDescription = null,
                            tint = if (isSelected) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                asset.decodedModelName.ifEmpty { asset.decodedName },
                                style = MaterialTheme.typography.bodyLarge,
                            )
                            val subtitle = listOf(asset.decodedAssetTag, asset.decodedName)
                                .filter { it.isNotEmpty() }
                                .joinToString(" · ")
                            if (subtitle.isNotEmpty()) {
                                Text(
                                    subtitle,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Resolves a scanned/typed value to a local or remote [Asset]. */
private suspend fun resolveScannedAsset(raw: String, viewModel: AppViewModel): Asset? {
    val trimmed = raw.trim()
    if (trimmed.isEmpty()) return null
    val assets = viewModel.assets.value

    fun resolveLocally(value: String): Asset? {
        val normalized = value.trim().lowercase()
        if (normalized.isEmpty()) return null
        return assets.firstOrNull { asset ->
            asset.decodedAssetTag.trim().lowercase() == normalized ||
                asset.decodedSerial.trim().lowercase() == normalized ||
                asset.altBarcode?.trim()?.lowercase() == normalized
        }
    }

    resolveLocally(trimmed)?.let { return it }

    when (val link = SnipeITQRLink.parse(trimmed)) {
        is SnipeITQRLink.Hardware -> assets.firstOrNull { it.id == link.id }?.let { return it }
        is SnipeITQRLink.HardwareByTag -> {
            resolveLocally(link.tag)?.let { return it }
            return viewModel.apiClient.fetchHardwareByTag(link.tag)
        }
        else -> Unit
    }

    return viewModel.apiClient.fetchHardwareByTag(trimmed)
}

/** Continuous scan-to-add screen with a manual entry fallback. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BulkAssetScannerScreen(
    viewModel: AppViewModel,
    onAssetResolved: (Asset) -> Unit,
    onDone: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasCameraPermission = granted }
    LaunchedEffect(Unit) { if (!hasCameraPermission) permissionLauncher.launch(Manifest.permission.CAMERA) }

    var manualTag by remember { mutableStateOf("") }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var statusIsError by remember { mutableStateOf(false) }
    var addedAssets by remember { mutableStateOf<List<Asset>>(emptyList()) }
    var isResolving by remember { mutableStateOf(false) }

    fun show(message: String, isError: Boolean) {
        statusMessage = message
        statusIsError = isError
    }

    fun handleRaw(raw: String) {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || isResolving) return
        isResolving = true
        scope.launch {
            val asset = resolveScannedAsset(trimmed, viewModel)
            isResolving = false
            if (asset == null) {
                show(L10n.string("asset_not_found_short", trimmed), true)
                return@launch
            }
            if (addedAssets.any { it.id == asset.id }) {
                show(L10n.string("asset_already_added", asset.decodedAssetTag.ifEmpty { trimmed }), true)
                return@launch
            }
            addedAssets = listOf(asset) + addedAssets
            onAssetResolved(asset)
            show(L10n.string("asset_added", asset.decodedAssetTag.ifEmpty { trimmed }), false)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("scan_assets")) },
                actions = {
                    TextButton(onClick = onDone) {
                        Text(L10n.string("done"), fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Box(modifier = Modifier.fillMaxWidth().height(260.dp)) {
                if (!hasCameraPermission) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            L10n.string("camera_permission_required"),
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(24.dp),
                            textAlign = TextAlign.Center,
                        )
                    }
                } else {
                    val lastScanValue = remember { java.util.concurrent.atomic.AtomicReference("") }
                    val lastScanTime = remember { AtomicLong(0L) }
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
                                        if (mediaImage != null) {
                                            val image = InputImage.fromMediaImage(
                                                mediaImage,
                                                imageProxy.imageInfo.rotationDegrees,
                                            )
                                            scanner.process(image)
                                                .addOnSuccessListener { barcodes ->
                                                    val raw = barcodes.firstOrNull()?.rawValue?.trim()
                                                    if (!raw.isNullOrEmpty()) {
                                                        val now = System.currentTimeMillis()
                                                        val isDuplicate = raw == lastScanValue.get() &&
                                                            now - lastScanTime.get() < 2500
                                                        if (!isDuplicate) {
                                                            lastScanValue.set(raw)
                                                            lastScanTime.set(now)
                                                            previewView.post { handleRaw(raw) }
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
                            .fillMaxSize()
                            .padding(24.dp)
                            .border(2.dp, Color.White, RoundedCornerShape(16.dp)),
                    )
                }
                if (statusMessage != null) {
                    Text(
                        text = statusMessage.orEmpty(),
                        color = Color.White,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = 12.dp)
                            .background(
                                (if (statusIsError) Color.Red else Color(0xFF2E7D32)).copy(alpha = 0.85f),
                                RoundedCornerShape(50),
                            )
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                } else {
                    Text(
                        text = L10n.string("bulk_audit_scan_hint"),
                        color = Color.White,
                        style = MaterialTheme.typography.bodySmall,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = 12.dp)
                            .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(50))
                            .padding(horizontal = 12.dp, vertical = 6.dp),
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                OutlinedTextField(
                    value = manualTag,
                    onValueChange = { manualTag = it },
                    modifier = Modifier.weight(1f),
                    placeholder = { Text(L10n.string("bulk_audit_manual_placeholder")) },
                    singleLine = true,
                )
                TextButton(
                    onClick = { handleRaw(manualTag); manualTag = "" },
                    enabled = manualTag.trim().isNotEmpty(),
                ) { Text(L10n.string("add")) }
            }

            FormSectionTitle(
                L10n.string("added_assets") + " (${addedAssets.size})",
            )
            if (addedAssets.isEmpty()) {
                Text(
                    L10n.string("bulk_audit_empty"),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            } else {
                LazyColumn(modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
                    items(addedAssets, key = { it.id }) { asset ->
                        Column(modifier = Modifier.padding(vertical = 6.dp)) {
                            Text(
                                asset.decodedModelName.ifEmpty { asset.decodedName },
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            val subtitle = listOf(asset.decodedAssetTag, asset.decodedName)
                                .filter { it.isNotEmpty() }
                                .joinToString(" · ")
                            if (subtitle.isNotEmpty()) {
                                Text(
                                    subtitle,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
