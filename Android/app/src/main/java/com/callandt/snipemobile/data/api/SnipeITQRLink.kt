package com.callandt.snipemobile.data.api

import java.net.URI
import java.net.URLDecoder

sealed class SnipeITQRLink {
    data class Hardware(val id: Int) : SnipeITQRLink()
    data class Component(val id: Int) : SnipeITQRLink()
    data class Accessory(val id: Int) : SnipeITQRLink()
    data class License(val id: Int) : SnipeITQRLink()
    data class Consumable(val id: Int) : SnipeITQRLink()
    data class HardwareByTag(val tag: String) : SnipeITQRLink()

    fun notFoundMessage(id: Int): String = when (this) {
        is Hardware, is HardwareByTag -> "Asset not found (id: $id)"
        is Component -> "Component not found (id: $id)"
        is Accessory -> "Accessory not found (id: $id)"
        is License -> "License not found (id: $id)"
        is Consumable -> "Consumable not found (id: $id)"
    }

    companion object {
        private val reservedTokens = setOf(
            "bytag", "create", "bulkedit", "bulkdelete", "bulkaudit", "labels",
            "audit", "requested", "clone", "restore", "import", "export",
            "quickscan", "quickadd", "checkout", "checkin", "edit", "delete",
            "view", "files", "history", "maintenances", "api", "v1",
        )

        fun parse(url: URI): SnipeITQRLink? = parse(url.toString())

        /** Parse Snipe-IT item URLs. */
        fun parse(urlString: String): SnipeITQRLink? {
            val text = urlString.trim()
            if (text.isEmpty()) return null
            return parsePath(pathLike(text), queryString(text))
        }

        private fun parsePath(path: String, query: String?): SnipeITQRLink? {
            if (path.contains("hardware", ignoreCase = true)) {
                assetTagFromQuery(query)?.let { return HardwareByTag(it) }
            }

            val segments = path
                .split('/', '#')
                .map { decode(it) }
                .filter { it.isNotEmpty() }

            for (index in segments.indices) {
                val segment = segments[index].lowercase()
                val next = segments.getOrNull(index + 1)

                if (segment == "hardware" && next?.equals("bytag", ignoreCase = true) == true) {
                    val tag = segments.getOrNull(index + 2)
                    if (!tag.isNullOrEmpty() && !isReserved(tag)) return HardwareByTag(tag)
                    return assetTagFromQuery(query)?.let { HardwareByTag(it) }
                }

                if (next.isNullOrEmpty() || isReserved(next)) continue

                if (segment == "ht") return HardwareByTag(next)

                when (segment) {
                    "hardware" -> return hardwareToken(next)
                    "components" -> next.toIntOrNull()?.let { return Component(it) }
                    "accessories" -> next.toIntOrNull()?.let { return Accessory(it) }
                    "licenses" -> next.toIntOrNull()?.let { return License(it) }
                    "consumables" -> next.toIntOrNull()?.let { return Consumable(it) }
                }
            }
            return null
        }

        /** Digits = id; anything else = asset tag. */
        private fun hardwareToken(token: String): SnipeITQRLink {
            val id = token.toIntOrNull()
            return if (id != null && id.toString() == token) Hardware(id) else HardwareByTag(token)
        }

        private fun isReserved(token: String): Boolean =
            token.lowercase() in reservedTokens

        private fun pathLike(text: String): String {
            var value = text
            val scheme = value.indexOf("://")
            if (scheme >= 0) {
                value = value.substring(scheme + 3)
                val hostEnd = value.indexOfFirst { it == '/' || it == '?' || it == '#' }
                value = if (hostEnd >= 0) value.substring(hostEnd) else ""
            }
            val queryStart = value.indexOf('?')
            if (queryStart >= 0) value = value.substring(0, queryStart)
            return value.replace('#', '/')
        }

        private fun queryString(text: String): String? {
            val start = text.indexOf('?')
            if (start < 0) return null
            var query = text.substring(start + 1)
            val hash = query.indexOf('#')
            if (hash >= 0) query = query.substring(0, hash)
            return query
        }

        private fun assetTagFromQuery(query: String?): String? {
            if (query.isNullOrEmpty()) return null
            for (part in query.split('&')) {
                val idx = part.indexOf('=')
                if (idx <= 0) continue
                val name = part.substring(0, idx).lowercase()
                if (name != "assettag" && name != "asset_tag") continue
                val tag = decode(part.substring(idx + 1)).trim()
                if (tag.isNotEmpty()) return tag
            }
            return null
        }

        private fun decode(value: String): String =
            runCatching { URLDecoder.decode(value, Charsets.UTF_8.name()) }.getOrDefault(value)
    }
}
