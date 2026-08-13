package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.callandt.snipemobile.data.model.Activity
import com.callandt.snipemobile.ui.AppViewModel

@Composable
fun ItemHistoryTab(
    itemType: String,
    itemId: Int,
    viewModel: AppViewModel,
    reloadToken: Int = 0,
) {
    var activities by remember(itemType, itemId) { mutableStateOf<List<Activity>>(emptyList()) }
    var loading by remember(itemType, itemId) { mutableStateOf(true) }
    val filePreview = rememberSnipeFilePreviewState(viewModel)

    LaunchedEffect(itemType, itemId, reloadToken) {
        loading = true
        activities = viewModel.apiClient.fetchActivityForItem(itemType, itemId)
        loading = false
    }

    when {
        loading -> ActivityTimelineLoading(modifier = Modifier.fillMaxSize())
        activities.isEmpty() -> ActivityTimelineEmpty(modifier = Modifier.fillMaxSize())
        else -> ActivityTimelineList(
            activities = activities,
            preferItemHeadline = false,
            modifier = Modifier.fillMaxSize(),
            apiClient = viewModel.apiClient,
            fileObjectType = itemType,
            fileObjectId = itemId,
            onFileClick = { filePreview.openActivityFile(itemType, itemId, it) },
        )
    }
    SnipeFilePreviewHost(filePreview)
}
