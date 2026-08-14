package com.callandt.snipemobile.ui.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date

class ListSortTest {
    private data class Row(val id: Int, val tag: String, val name: String = "", val date: Date? = null)

    private val tagKeys = listOf(
        ListSortKey<Row>(ListSortField.AssetTag) { ListSortComparable.NumericText(it.tag) },
    )
    private val nameKeys = listOf(
        ListSortKey<Row>(ListSortField.Name) { ListSortComparable.Text(it.name) },
    )
    private val dateKeys = listOf(
        ListSortKey<Row>(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.date) },
    )

    @Test
    fun numericTagsSortNaturally() {
        val rows = listOf(
            Row(1, "IMG_10"),
            Row(2, "IMG_2"),
            Row(3, "2"),
            Row(4, "10"),
            Row(5, "A10"),
            Row(6, "A2"),
        )
        val sorted = rows.sortedByListSort(
            ListSort(ListSortField.AssetTag, ListSortOrder.Ascending),
            tagKeys,
        ) { it.id }
        assertEquals(listOf("2", "10", "A2", "A10", "IMG_2", "IMG_10"), sorted.map { it.tag })
    }

    @Test
    fun numericTagsIgnoreCaseAndLeadingZeros() {
        val rows = listOf(Row(1, "a10"), Row(2, "A2"), Row(3, "01"), Row(4, "1"))
        val sorted = rows.sortedByListSort(
            ListSort(ListSortField.AssetTag, ListSortOrder.Ascending),
            tagKeys,
        ) { it.id }
        assertEquals(listOf("01", "1", "A2", "a10"), sorted.map { it.tag })
    }

    @Test
    fun namesAreCaseInsensitive() {
        val rows = listOf(Row(1, "", "banana"), Row(2, "", "Apple"), Row(3, "", "cherry"))
        val sorted = rows.sortedByListSort(ListSort.nameAscending, nameKeys) { it.id }
        assertEquals(listOf("Apple", "banana", "cherry"), sorted.map { it.name })
    }

    @Test
    fun nullDatesStayLastInBothOrders() {
        val early = Date(1_000)
        val late = Date(2_000)
        val rows = listOf(
            Row(1, "", date = null),
            Row(2, "", date = late),
            Row(3, "", date = early),
            Row(4, "", date = null),
        )
        val asc = rows.sortedByListSort(
            ListSort(ListSortField.UpdatedAt, ListSortOrder.Ascending),
            dateKeys,
        ) { it.id }
        assertEquals(listOf(3, 2, 1, 4), asc.map { it.id })

        val desc = rows.sortedByListSort(
            ListSort(ListSortField.UpdatedAt, ListSortOrder.Descending),
            dateKeys,
        ) { it.id }
        assertEquals(listOf(2, 3, 1, 4), desc.map { it.id })
    }

    @Test
    fun largeMixedTagListDoesNotViolateTimSort() {
        val tags = (0 until 2_500).map { index ->
            when (index % 7) {
                0 -> "ASSET-$index"
                1 -> "asset-${index / 2}"
                2 -> index.toString()
                3 -> "IMG_${index % 50}"
                4 -> "00$index"
                5 -> "Tag ${index % 13}"
                else -> "x${index}y${index % 9}"
            }
        }
        val rows = tags.mapIndexed { id, tag -> Row(id, tag) }
        val sorted = rows.sortedByListSort(ListSort.assetTagDescending, tagKeys) { it.id }
        assertEquals(2_500, sorted.size)
        assertTrue(sorted.map { it.id }.toSet().size == 2_500)
    }
}
