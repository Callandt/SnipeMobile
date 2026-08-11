package com.callandt.snipemobile.data.api

import java.net.URI
import java.net.URLDecoder

/** Dell service-tag QR URL parsing. */
object DellQrLink {

    fun isDellUrl(url: URI): Boolean =
        url.host?.lowercase()?.contains("dell") == true

    fun extractServiceTag(url: URI): String? {
        val pathParts = url.path.split("/").filter { it.isNotEmpty() }
        val serviceTagIndex = pathParts.indexOfFirst { it.equals("servicetag", ignoreCase = true) }
        if (serviceTagIndex >= 0 && serviceTagIndex + 1 < pathParts.size) {
            val tag = pathParts[serviceTagIndex + 1].trim()
            if (tag.isNotEmpty()) return tag
        }

        val query = url.rawQuery.orEmpty()
        if (query.isEmpty()) return null
        val keys = setOf("servicetag", "serviceTag", "st", "ST", "t", "T")
        return query.split("&").mapNotNull { part ->
            val idx = part.indexOf('=')
            if (idx <= 0) return@mapNotNull null
            val name = part.substring(0, idx)
            if (name !in keys) return@mapNotNull null
            URLDecoder.decode(part.substring(idx + 1), Charsets.UTF_8.name()).trim()
        }.firstOrNull { it.isNotEmpty() }
    }

    fun parse(raw: String): URI? = runCatching { URI(raw.trim()) }.getOrNull()

    fun parseServiceTag(raw: String): String? {
        val url = parse(raw) ?: return null
        if (!isDellUrl(url)) return null
        return extractServiceTag(url)
    }
}
