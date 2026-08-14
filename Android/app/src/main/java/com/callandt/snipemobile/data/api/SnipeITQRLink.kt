package com.callandt.snipemobile.data.api

import com.callandt.snipemobile.ui.util.L10n
import java.net.URLDecoder

sealed class SnipeITQRLink {
    data class Hardware(val id: Int) : SnipeITQRLink()
    data class Component(val id: Int) : SnipeITQRLink()
    data class Accessory(val id: Int) : SnipeITQRLink()
    data class License(val id: Int) : SnipeITQRLink()
    data class Consumable(val id: Int) : SnipeITQRLink()
    data class Location(val id: Int) : SnipeITQRLink()
    data class User(val id: Int) : SnipeITQRLink()
    data class Maintenance(val id: Int) : SnipeITQRLink()
    data class HardwareByTag(val tag: String) : SnipeITQRLink()

    fun notFoundMessage(id: Int): String = when (this) {
        is Hardware, is HardwareByTag -> L10n.string("asset_not_found_id", id.toString())
        is Component -> L10n.string("component_not_found_id", id.toString())
        is Accessory -> L10n.string("accessory_not_found_id", id.toString())
        is License -> L10n.string("license_not_found_id", id.toString())
        is Consumable -> L10n.string("consumable_not_found_id", id.toString())
        is Location -> L10n.string("location_not_found_id", id.toString())
        is User -> L10n.string("user_not_found_id", id.toString())
        is Maintenance -> L10n.string("maintenance_not_found_id", id.toString())
    }

    companion object {
        private val reservedTokens = setOf(
            "bytag", "create", "bulkedit", "bulkdelete", "bulkaudit", "labels",
            "audit", "requested", "clone", "restore", "import", "export",
            "quickscan", "quickadd", "checkout", "checkin", "edit", "delete",
            "view", "files", "history", "maintenances", "api", "v1",
        )

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
                    "hardware", "assets", "asset" -> return hardwareToken(next)
                    "components", "component" -> entityId(next)?.let { return Component(it) }
                    "accessories", "accessory" -> entityId(next)?.let { return Accessory(it) }
                    "licenses", "license" -> entityId(next)?.let { return License(it) }
                    "consumables", "consumable" -> entityId(next)?.let { return Consumable(it) }
                    "locations", "location" -> entityId(next)?.let { return Location(it) }
                    "users", "user" -> entityId(next)?.let { return User(it) }
                    "maintenances", "maintenance" -> entityId(next)?.let { return Maintenance(it) }
                }
            }
            return null
        }

        /** Digits = id; anything else = asset tag. */
        private fun hardwareToken(token: String): SnipeITQRLink {
            val id = entityId(token)
            return if (id != null) Hardware(id) else HardwareByTag(token)
        }

        private fun entityId(token: String): Int? {
            val id = token.toIntOrNull()
            return if (id != null && id.toString() == token) id else null
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
