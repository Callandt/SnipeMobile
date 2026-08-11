package com.callandt.snipemobile.data.cache

import android.content.Context
import com.callandt.snipemobile.data.model.SnipeDataCacheSnapshot
import com.callandt.snipemobile.data.model.SnipeJson
import java.io.File
import kotlinx.serialization.encodeToString

/** Local JSON cache per server. */
object LocalCacheStore {
    private const val CACHE_DIR = "SnipeDataCache"

    private fun directory(context: Context): File {
        val dir = File(context.filesDir, CACHE_DIR)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    private fun file(context: Context, key: String): File =
        File(directory(context), "$key.json")

    /** Stable, filename-safe key from a base URL. */
    fun keyForBaseURL(baseURL: String): String = keyForBaseUrl(baseURL)

    fun keyForBaseUrl(baseURL: String): String {
        val raw = baseURL.ifEmpty { "default" }
        val allowed = ('A'..'Z') + ('a'..'z') + ('0'..'9')
        val safe = raw.map { ch -> if (ch in allowed) ch else '_' }.joinToString("")
        return safe.ifEmpty { "default" }
    }

    fun load(context: Context, key: String): SnipeDataCacheSnapshot? {
        val file = file(context, key)
        if (!file.exists()) return null
        return runCatching {
            SnipeJson.decodeFromString(SnipeDataCacheSnapshot.serializer(), file.readText())
        }.getOrNull()
    }

    fun save(context: Context, snapshot: SnipeDataCacheSnapshot, key: String) {
        val file = file(context, key)
        runCatching {
            val data = SnipeJson.encodeToString(snapshot)
            file.writeText(data)
        }
    }

    /** Wipe all cached files (on data wipe). */
    fun clearAll(context: Context) {
        val dir = directory(context)
        dir.listFiles()?.forEach { it.delete() }
        if (dir.exists()) {
            dir.delete()
        }
    }
}
