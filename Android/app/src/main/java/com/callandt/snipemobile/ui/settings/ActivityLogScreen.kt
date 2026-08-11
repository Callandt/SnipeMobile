package com.callandt.snipemobile.ui.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.Activity
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.ActivityTimelineEmpty
import com.callandt.snipemobile.ui.components.ActivityTimelineList
import com.callandt.snipemobile.ui.components.ActivityTimelineLoading
import com.callandt.snipemobile.ui.components.SearchTopBar
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActivityLogScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
) {
    var activities by remember { mutableStateOf<List<Activity>>(emptyList()) }
    var isInitialLoading by remember { mutableStateOf(true) }
    var isLoadingMore by remember { mutableStateOf(false) }
    var canLoadMore by remember { mutableStateOf(true) }
    var offset by remember { mutableIntStateOf(0) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var searchQuery by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val pageSize = 50
    val baseUrl by viewModel.baseUrl.collectAsState()

    val filtered = remember(activities, searchQuery) {
        val q = searchQuery.trim().lowercase()
        if (q.isEmpty()) activities
        else activities.filter { activity ->
            activity.decodedNote.lowercase().contains(q) ||
                activity.item?.decodedName?.lowercase()?.contains(q) == true ||
                activity.target?.decodedName?.lowercase()?.contains(q) == true ||
                activity.file?.decodedFilename?.lowercase()?.contains(q) == true ||
                activity.actionType.lowercase().contains(q) ||
                (activity.admin ?: activity.createdBy)?.decodedName?.lowercase()?.contains(q) == true
        }
    }

    suspend fun loadFirstPage() {
        isInitialLoading = true
        loadError = null
        val page = viewModel.apiClient.fetchActivityPage(limit = pageSize, offset = 0)
        isInitialLoading = false
        activities = page
        offset = page.size
        canLoadMore = page.size == pageSize
        if (page.isEmpty() && !viewModel.apiClient.isConfigured.value) {
            loadError = L10n.string("settings_not_configured")
        }
    }

    suspend fun loadMore() {
        if (!canLoadMore || isLoadingMore) return
        isLoadingMore = true
        val page = viewModel.apiClient.fetchActivityPage(limit = pageSize, offset = offset)
        isLoadingMore = false
        if (page.isEmpty()) {
            canLoadMore = false
            return
        }
        val existingIds = activities.map { it.id }.toSet()
        activities = activities + page.filter { it.id !in existingIds }
        offset += page.size
        canLoadMore = page.size == pageSize
    }

    LaunchedEffect(Unit) {
        if (activities.isEmpty()) loadFirstPage()
    }

    Scaffold(
        topBar = {
            SearchTopBar(
                title = L10n.string("settings_activity_log"),
                searchQuery = searchQuery,
                onSearchQueryChange = { searchQuery = it },
                onBack = onBack,
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isInitialLoading && activities.isNotEmpty(),
            onRefresh = {
                scope.launch {
                    activities = emptyList()
                    offset = 0
                    canLoadMore = true
                    loadFirstPage()
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                isInitialLoading && activities.isEmpty() -> {
                    ActivityTimelineLoading()
                }
                loadError != null && activities.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(loadError ?: L10n.string("mgmt_load_failed"))
                            TextButton(onClick = { scope.launch { loadFirstPage() } }) {
                                Text(L10n.string("retry"))
                            }
                        }
                    }
                }
                activities.isEmpty() -> {
                    ActivityTimelineEmpty()
                }
                else -> {
                    ActivityTimelineList(
                        activities = filtered,
                        showItemType = true,
                        preferItemHeadline = true,
                        baseUrl = baseUrl,
                        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 24.dp),
                        footer = {
                            if (searchQuery.isEmpty() && canLoadMore) {
                                item {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(vertical = 12.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        CircularProgressIndicator()
                                        LaunchedEffect(offset) { loadMore() }
                                    }
                                }
                            }
                        },
                    )
                }
            }
        }
    }
}
