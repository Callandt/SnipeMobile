package com.callandt.snipemobile.ui.util

data class FilterDimension<T>(
    val title: String,
    val value: (T) -> String,
)

/** Selected value per dimension title. */
data class ListFilter(
    val selections: Map<String, String> = emptyMap(),
) {
    val isActive: Boolean get() = selections.isNotEmpty()
    val activeCount: Int get() = selections.size

    fun clear(): ListFilter = ListFilter()

    fun withSelection(title: String, value: String?): ListFilter {
        val next = selections.toMutableMap()
        if (value.isNullOrBlank()) next.remove(title) else next[title] = value
        return copy(selections = next)
    }

    fun <T> matches(item: T, dimensions: List<FilterDimension<T>>): Boolean {
        for (dim in dimensions) {
            val selected = selections[dim.title] ?: continue
            if (dim.value(item) != selected) return false
        }
        return true
    }
}

data class ListFilterOption(
    val title: String,
    val values: List<String>,
)

fun distinctSortedFilterValues(values: List<String>): List<String> =
    values.map { it.trim() }
        .filter { it.isNotEmpty() }
        .distinct()
        .sortedBy { it.lowercase() }

/** Catalog names first; fall back to values present on loaded items. */
fun listFilterValues(catalog: List<String>, itemValues: List<String>): List<String> {
    val fromCatalog = distinctSortedFilterValues(catalog)
    if (fromCatalog.isNotEmpty()) return fromCatalog
    return distinctSortedFilterValues(itemValues)
}

fun <T> listFilterOptions(
    dimensions: List<FilterDimension<T>>,
    catalogByTitle: Map<String, List<String>> = emptyMap(),
    items: List<T>,
): List<ListFilterOption> =
    dimensions.map { dim ->
        ListFilterOption(
            title = dim.title,
            values = listFilterValues(
                catalog = catalogByTitle[dim.title].orEmpty(),
                itemValues = items.map { dim.value(it) },
            ),
        )
    }
