package com.callandt.snipemobile.ui.asset

import org.junit.Assert.assertEquals
import org.junit.Test

class CustomFieldOptionsTest {
    @Test
    fun bareLineFeedsInOneArrayEntryBecomeSeparateOptions() {
        val options = customFieldOptions(listOf("8 GB\n16 GB\n32 GB"))
        assertEquals(listOf("8 GB", "16 GB", "32 GB"), options.map { it.value })
        assertEquals(options.map { it.value }, options.map { it.label })
    }

    @Test
    fun alreadySplitCrlfEntriesStaySeparate() {
        val options = customFieldOptions(listOf("Red", "Green", "Blue"))
        assertEquals(listOf("Red", "Green", "Blue"), options.map { it.value })
    }

    @Test
    fun rawFieldValuesWinOverACollapsedArray() {
        val options = customFieldOptions(listOf("everything"), raw = "Alpha\nBeta")
        assertEquals(listOf("Alpha", "Beta"), options.map { it.value })
    }

    @Test
    fun valuePipeLabelMatchesTheWebsite() {
        val options = customFieldOptions(listOf("desk|Desk\nlaptop|Laptop\nA|B|C"))
        assertEquals(listOf("desk", "laptop", "A"), options.map { it.value })
        assertEquals(listOf("Desk", "Laptop", "B"), options.map { it.label })
    }

    @Test
    fun htmlEntitiesFromTheApiAreDecoded() {
        val options = customFieldOptions(listOf("AT&amp;T\nO&#039;Reilly"))
        assertEquals(listOf("AT&T", "O'Reilly"), options.map { it.value })
    }

    @Test
    fun blankLinesAndDuplicateValuesCollapse() {
        val options = customFieldOptions(listOf("A\n\nA|First\nB\nA|Second"))
        assertEquals(listOf("A", "B"), options.map { it.value })
        assertEquals(listOf("Second", "B"), options.map { it.label })
    }

    @Test
    fun aSplitArrayBeatsAnUnsplitRawString() {
        val options = customFieldOptions(listOf("Red", "Blue"), raw = "Red Blue")
        assertEquals(listOf("Red", "Blue"), options.map { it.value })
    }

    @Test
    fun commasStayInsideAnOption() {
        val options = customFieldOptions(listOf("New York, NY\nBoston, MA"))
        assertEquals(listOf("New York, NY", "Boston, MA"), options.map { it.value })
    }
}
