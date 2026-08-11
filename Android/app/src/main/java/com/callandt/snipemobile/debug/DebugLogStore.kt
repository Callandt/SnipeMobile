package com.callandt.snipemobile.debug

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import com.callandt.snipemobile.data.api.SnipeApiClient
import com.callandt.snipemobile.ui.util.L10n
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.locks.ReentrantLock
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import kotlin.concurrent.withLock
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Privacy-scrubbed diagnostic lines for support (safe for public GitHub issues). */
object AppLog {
    fun info(message: String, category: String = "app") {
        DebugLogStore.append(message, category)
    }

    fun network(message: String) {
        info(message, category = "network")
    }
}

object DebugLogStore {
    private const val MAX_LINES = 2_500

    private val lock = ReentrantLock()
    private val lines = ArrayDeque<String>()
    private val iso: SimpleDateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    @Volatile
    private var started = false

    fun startIfNeeded() {
        if (started) return
        started = true
        append("Debug log started", "app")
    }

    fun append(message: String, category: String = "app") {
        startIfNeeded()
        val stamped = "${iso.stringNow()} [$category] ${redactForPublic(message)}"
        lock.withLock {
            lines.addLast(stamped)
            while (lines.size > MAX_LINES) lines.removeFirst()
        }
    }

    fun snapshot(): List<String> = lock.withLock { lines.toList() }

    /**
     * Builds a public-safe zip with diagnostics + recent log.
     * Runs a live connection check first so the zip shows connect OK/FAIL.
     */
    suspend fun exportZip(context: Context, apiClient: SnipeApiClient): File {
        startIfNeeded()
        val extras = knownPrivateStrings(apiClient)
        append("Building public-safe debug zip", "debug")
        append("Running connection check…", "network")

        val connectionResult = when {
            apiClient.baseUrl.isEmpty() || apiClient.apiToken.isEmpty() -> {
                append("Connection check FAILED: not configured", "network")
                "FAILED: not configured"
            }
            else -> {
                val error = apiClient.validateApiCredentials()
                if (error != null) {
                    append("Connection check FAILED: $error", "network")
                    "FAILED: $error"
                } else {
                    append("Connection check OK", "network")
                    "OK"
                }
            }
        }

        val diagnostics = redactForPublic(
            diagnosticsText(context, apiClient, connectionResult),
            extras,
        )
        val logText = redactForPublic(
            snapshot().joinToString("\n") + "\n",
            extras,
        )

        val exportDir = File(context.cacheDir, "DebugExports").apply {
            mkdirs()
            listFiles()?.forEach { runCatching { it.delete() } }
        }
        val zipFile = File(exportDir, "SnipeMobile-Debug-${fileStamp()}.zip")
        ZipOutputStream(BufferedOutputStream(FileOutputStream(zipFile))).use { zip ->
            zip.putNextEntry(ZipEntry("diagnostics.txt"))
            zip.write(diagnostics.toByteArray(Charsets.UTF_8))
            zip.closeEntry()
            zip.putNextEntry(ZipEntry("app.log"))
            zip.write(logText.toByteArray(Charsets.UTF_8))
            zip.closeEntry()
        }
        return zipFile
    }

    fun shareZip(context: Context, file: File) {
        val uri: Uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/zip"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "SnipeMobile debug log")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(
            Intent.createChooser(intent, L10n.string("debug_export")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }

    private fun diagnosticsText(
        context: Context,
        apiClient: SnipeApiClient,
        connectionResult: String,
    ): String {
        val parsed = apiClient.baseUrl.toHttpUrlOrNull()
        val scheme = parsed?.scheme?.lowercase(Locale.US) ?: "(none)"
        val host = parsed?.host.orEmpty()
        val token = apiClient.apiToken
        val tokenMeta = when {
            token.isEmpty() -> "missing"
            else -> {
                val trimmed = token.trim()
                "present length=${token.length} hasWhitespace=${token != trimmed} " +
                    "hasBearerPrefix=${token.lowercase(Locale.US).startsWith("bearer ")}"
            }
        }
        val hostKind = when {
            host.isEmpty() -> "missing"
            looksLikeIp(host) -> "ip_literal"
            host.contains("localhost", ignoreCase = true) -> "localhost"
            else -> "hostname"
        }
        val storedRaw = apiClient.baseUrl
        val lowerRaw = storedRaw.lowercase(Locale.US)
        val urlHints = buildList {
            when {
                lowerRaw.contains("/api/v1") -> add("stored_value_contains_/api/v1")
                lowerRaw.contains("/api") -> add("stored_value_contains_/api")
            }
            if (lowerRaw.startsWith("http://")) add("stored_scheme_http")
            if (storedRaw.isNotEmpty() &&
                !lowerRaw.startsWith("http://") &&
                !lowerRaw.startsWith("https://")
            ) {
                add("stored_value_missing_scheme")
            }
        }

        val packageInfo = runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0)
        }.getOrNull()
        val versionName = packageInfo?.versionName ?: "—"
        val versionCode = packageInfo?.longVersionCode ?: 0L

        return buildString {
            appendLine("SnipeMobile diagnostics (public-safe)")
            appendLine("Generated: ${iso.stringNow()}")
            appendLine()
            appendLine("App: $versionName ($versionCode)")
            appendLine("Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
            appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
            appendLine("Locale: ${Locale.getDefault().toLanguageTag()}")
            appendLine()
            appendLine("Configured: ${apiClient.isConfigured.value}")
            appendLine("Connection check: $connectionResult")
            appendLine("URL scheme: $scheme")
            appendLine("Host kind: $hostKind")
            appendLine(
                "URL hints: ${
                    if (urlHints.isEmpty()) "(none)" else urlHints.joinToString(", ")
                }",
            )
            appendLine("API token: $tokenMeta")
            appendLine()
            appendLine("Cache counts:")
            appendLine("  assets=${apiClient.assets.value.size}")
            appendLine("  users=${apiClient.users.value.size}")
            appendLine("  accessories=${apiClient.accessories.value.size}")
            appendLine("  licenses=${apiClient.licenses.value.size}")
            appendLine("  consumables=${apiClient.consumables.value.size}")
            appendLine("  components=${apiClient.components.value.size}")
            appendLine("  locations=${apiClient.locations.value.size}")
            appendLine("  hasCompletedInitialLoad=${apiClient.hasCompletedInitialLoad.value}")
            appendLine("  lastError=${redactForPublic(apiClient.errorMessage.value ?: "(none)")}")
            appendLine("  refreshError=${redactForPublic(apiClient.refreshErrorMessage.value ?: "(none)")}")
            appendLine("  lastApiMessage=${summarizeServerMessage(apiClient.lastApiMessage.value)}")
        }
    }

    private fun knownPrivateStrings(apiClient: SnipeApiClient): List<String> {
        val extras = mutableListOf<String>()
        val base = apiClient.baseUrl
        if (base.isNotEmpty()) extras += base
        base.toHttpUrlOrNull()?.host?.takeIf { it.isNotEmpty() }?.let { host ->
            extras += host
            host.substringBefore(':').takeIf { it != host && it.isNotEmpty() }?.let { extras += it }
        }
        val token = apiClient.apiToken
        if (token.length >= 8) extras += token
        return extras
    }

    fun redactForPublic(text: String, alsoReplacing: List<String> = emptyList()): String {
        var out = text
        for (extra in alsoReplacing.sortedByDescending { it.length }) {
            if (extra.length < 3) continue
            out = out.replace(extra, "<redacted>", ignoreCase = true)
        }
        out = Regex("""https?://[^\s"'<>]+""", RegexOption.IGNORE_CASE).replace(out, "<url>")
        out = Regex("""[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}""", RegexOption.IGNORE_CASE)
            .replace(out, "<email>")
        out = Regex("""\b\d{1,3}(?:\.\d{1,3}){3}\b""").replace(out, "<ip>")
        out = Regex("""\b(?:[0-9a-f]{1,4}:){2,7}[0-9a-f]{1,4}\b""", RegexOption.IGNORE_CASE)
            .replace(out, "<ip>")
        out = Regex("""(?i)(Bearer\s+)([^\s"']+)""").replace(out, "$1<redacted>")
        out = Regex(
            """(?i)(api[_ -]?key|token|authorization|password|secret)(["'=\s:]+)([A-Za-z0-9._\-+/=]{8,})""",
        ).replace(out, "$1$2<redacted>")
        out = Regex("""(?i)\bhost=([^\s,]+)""").replace(out, "host=<redacted>")
        out = Regex(
            """(?i)("(?:email|username|name|first_name|last_name|employee_num)"\s*:\s*")([^"]*)(")""",
        ).replace(out, "$1<redacted>$3")
        return out
    }

    private fun summarizeServerMessage(message: String?): String {
        if (message.isNullOrEmpty()) return "(none)"
        val scrubbed = redactForPublic(message)
        return if (scrubbed.length <= 80) scrubbed
        else "length=${message.length} preview=${scrubbed.take(60)}…"
    }

    private fun looksLikeIp(host: String): Boolean {
        val v4 = Regex("""^\d{1,3}(?:\.\d{1,3}){3}$""").matches(host)
        return v4 || host.contains(':')
    }

    private fun fileStamp(): String =
        SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())

    private fun SimpleDateFormat.stringNow(): String = format(Date())
}
