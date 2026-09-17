package com.callandt.snipemobile.ui.util

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.assertEquals
import org.junit.Test

class ListUiStateSaverTest {
    @Test
    fun listSortRoundTrips() {
        val original = ListSort(ListSortField.NextAuditDate, ListSortOrder.Ascending)
        assertEquals(original, ListSortSaver.roundTrip(original))
    }

    @Test
    fun listFilterRoundTrips() {
        val original = ListFilter(mapOf("Category" to "Laptops", "Location" to "HQ"))
        assertEquals(original, ListFilterSaver.roundTrip(original))
    }

    @Test
    fun emptyListFilterSavesAsNull() {
        val saved = with(ListFilterSaver) {
            with(AlwaysSaveable) { save(ListFilter()) }
        }
        // listSaver omits empty maps.
        assertEquals(null, saved)
    }

    @Test
    fun defaultAssetFilterRoundTrips() {
        assertEquals(AssetFilter(), AssetFilterSaver.roundTrip(AssetFilter()))
    }

    @Test
    fun assetFilterRoundTripsStatusIdAndDimensions() {
        val original = AssetFilter(
            statusSelection = AssetStatusSelection.Status(12),
            category = "Laptops",
            model = "MacBook",
            manufacturer = "Apple",
            location = "HQ",
        )
        assertEquals(original, AssetFilterSaver.roundTrip(original))
    }

    @Test
    fun assetFilterRoundTripsReadyToDeploy() {
        val original = AssetFilter(statusSelection = AssetStatusSelection.ReadyToDeploy)
        assertEquals(original, AssetFilterSaver.roundTrip(original))
    }

    private fun <Original, Saveable : Any> Saver<Original, Saveable>.roundTrip(value: Original): Original {
        val saved = with(AlwaysSaveable) { save(value) }
        @Suppress("UNCHECKED_CAST")
        return restore(saved as Saveable) as Original
    }

    private object AlwaysSaveable : SaverScope {
        override fun canBeSaved(value: Any): Boolean = true
    }
}
