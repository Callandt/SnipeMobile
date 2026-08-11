package com.callandt.snipemobile.ui.util

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration

/** Phone vs tablet layout breakpoint. */
object WindowAdaptive {
    /** `sw600dp` and up. */
    const val TABLET_MIN_WIDTH_DP = 600

    @Composable
    fun isTabletLayout(): Boolean =
        LocalConfiguration.current.screenWidthDp >= TABLET_MIN_WIDTH_DP
}
