package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
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
) {
    var activities by remember(itemType, itemId) { mutableStateOf<List<Activity>>(emptyList()) }
    var loading by remember(itemType, itemId) { mutableStateOf(true) }
    val baseUrl by viewModel.baseUrl.collectAsState()

    LaunchedEffect(itemType, itemId) {
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
            baseUrl = baseUrl,
            modifier = Modifier.fillMaxSize(),
        )
    }
}
