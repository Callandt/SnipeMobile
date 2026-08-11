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
        fun parse(url: URI): SnipeITQRLink? {
            val lowerPath = url.path.lowercase()

            if (lowerPath.contains("/hardware/bytag")) {
                val query = url.rawQuery.orEmpty()
                val tag = query.split("&")
                    .mapNotNull { part ->
                        val idx = part.indexOf('=')
                        if (idx <= 0) return@mapNotNull null
                        val name = part.substring(0, idx).lowercase()
                        if (name != "assettag" && name != "asset_tag") return@mapNotNull null
                        URLDecoder.decode(part.substring(idx + 1), Charsets.UTF_8.name())
                    }
                    .firstOrNull()
                    ?.trim()
                    .orEmpty()
                return if (tag.isNotEmpty()) HardwareByTag(tag) else null
            }

            val segments = url.path.split("/").filter { it.isNotEmpty() }
            for (index in 0 until segments.size - 1) {
                val segment = segments[index].lowercase()
                val next = segments[index + 1]

                if (segment == "ht") {
                    val tag = URLDecoder.decode(next, Charsets.UTF_8.name()).trim()
                    return if (tag.isNotEmpty()) HardwareByTag(tag) else null
                }

                val id = next.toIntOrNull() ?: continue
                return when (segment) {
                    "hardware" -> Hardware(id)
                    "components" -> Component(id)
                    "accessories" -> Accessory(id)
                    "licenses" -> License(id)
                    "consumables" -> Consumable(id)
                    else -> continue
                }
            }
            return null
        }

        fun parse(urlString: String): SnipeITQRLink? =
            runCatching { parse(URI(urlString)) }.getOrNull()
    }
}
