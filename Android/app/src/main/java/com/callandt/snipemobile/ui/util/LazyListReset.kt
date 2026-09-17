package com.callandt.snipemobile.ui.util

import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.saveable.rememberSaveable

/** Keep scroll; reset when search, filter or sort changes. */
@Composable
fun rememberResettingLazyListState(resetKey: Any?): LazyListState =
    rememberSaveable(resetKey, saver = LazyListState.Saver) { LazyListState() }
