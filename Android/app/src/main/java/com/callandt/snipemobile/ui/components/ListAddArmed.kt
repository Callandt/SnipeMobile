package com.callandt.snipemobile.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import kotlinx.coroutines.delay

/**
 * False until this destination has settled after a NavHost pop/push.
 * Clicks during the back animation otherwise open a blank screen.
 */
@Composable
fun rememberListReadyAfterResume(): Boolean {
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    var armed by remember { mutableStateOf(false) }
    LaunchedEffect(lifecycleState) {
        if (lifecycleState.isAtLeast(Lifecycle.State.RESUMED)) {
            armed = false
            withFrameNanos { }
            withFrameNanos { }
            delay(280)
            armed = true
        } else {
            armed = false
        }
    }
    return armed
}
