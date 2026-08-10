package com.callandt.snipemobile.util

/**
 * Strip HTML tags and decode common HTML entities, matching the iOS [HTMLDecoder].
 */
object HtmlDecoder {
    private val TAG_PATTERN = Regex("<[^>]+>")
    private val NUMERIC_ENTITY_PATTERN = Regex("&#(\\d+);")

    private val NAMED_ENTITIES = mapOf(
        "&quot;" to "\"",
        "&apos;" to "'",
        "&amp;" to "&",
        "&lt;" to "<",
        "&gt;" to ">",
        "&euro;" to "€",
        "&nbsp;" to " ",
    )

    fun decode(htmlString: String): String {
        var result = htmlString.replace(TAG_PATTERN, "")
        for ((entity, character) in NAMED_ENTITIES) {
            result = result.replace(entity, character)
        }
        result = NUMERIC_ENTITY_PATTERN.replace(result) { match ->
            val code = match.groupValues[1].toIntOrNull()
            if (code != null) {
                code.toChar().toString()
            } else {
                match.value
            }
        }
        return result
    }
}
