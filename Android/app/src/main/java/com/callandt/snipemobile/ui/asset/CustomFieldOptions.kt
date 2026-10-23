package com.callandt.snipemobile.ui.asset

import com.callandt.snipemobile.util.HtmlDecoder

internal data class CustomFieldOption(val value: String, val label: String)

private val customFieldLineBreaks = Regex("\\r\\n|\\n|\\r|\\u0085|\\u2028|\\u2029")

// API array only splits on CRLF. Web splits every newline and `value|label`.
internal fun customFieldOptions(values: List<String>?, raw: String? = null): List<CustomFieldOption> {
    val fromRaw = splitFieldLines(raw.orEmpty())
    val fromArray = values.orEmpty().flatMap { splitFieldLines(it) }
    // Use whichever side actually split the options.
    val lines = when {
        fromRaw.size > fromArray.size -> fromRaw
        fromArray.isNotEmpty() -> fromArray
        else -> fromRaw
    }
    val result = mutableListOf<CustomFieldOption>()
    val indexByValue = HashMap<String, Int>()
    for (line in lines) {
        val decoded = HtmlDecoder.decode(line).trim()
        if (decoded.isEmpty()) continue
        val pieces = decoded.split('|')
        val value = pieces.first().trim()
        if (value.isEmpty()) continue
        val second = pieces.getOrNull(1)?.trim().orEmpty()
        val label = second.ifEmpty { value }
        val option = CustomFieldOption(value, label)
        val existing = indexByValue[value]
        if (existing != null) {
            result[existing] = option
        } else {
            indexByValue[value] = result.size
            result.add(option)
        }
    }
    return result
}

private fun splitFieldLines(text: String): List<String> =
    text.split(customFieldLineBreaks).map { it.trim() }.filter { it.isNotEmpty() }
