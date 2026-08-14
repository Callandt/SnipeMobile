package com.callandt.snipemobile.ui.util

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember

/** Reset scroll when search, filter or sort changes. */
@Composable
fun rememberResettingLazyListState(resetKey: Any?): LazyListState =
    remember(resetKey) { LazyListState() }
