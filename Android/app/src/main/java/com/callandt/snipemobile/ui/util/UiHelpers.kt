package com.callandt.snipemobile.ui.util

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Person
import androidx.compose.ui.graphics.vector.ImageVector
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.DateInfo
import com.callandt.snipemobile.util.HtmlDecoder
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

enum class AuditListFilter { All, DueToday, DueSoon, Overdue }

object AuditDateHelper {
    private val utc: TimeZone = TimeZone.getTimeZone("UTC")

    /** Next audit day (UTC midnight), from date / datetime / formatted. */
    fun nextAuditDate(asset: Asset): Date? {
        val info = asset.nextAuditDate ?: return null
        val raw = sequenceOf(info.date, info.datetime, info.formatted)
            .mapNotNull { it?.trim()?.takeIf { value -> value.isNotEmpty() } }
            .firstOrNull()
            ?: return null
        DateInfo.parseAPIDate(raw)?.let { return it }
        // Try yyyy-MM-dd inside locale-formatted strings.
        val match = Regex("""(\d{4}-\d{2}-\d{2})""").find(raw)?.groupValues?.getOrNull(1)
        return DateInfo.parseAPIDate(match)
    }

    private fun dayFormatter(): SimpleDateFormat =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = utc
            isLenient = false
        }

    private fun todayStart(now: Date): Date {
        val fmt = dayFormatter()
        val todayStr = fmt.format(now)
        return runCatching { fmt.parse(todayStr) }.getOrNull() ?: now
    }

    private fun addDays(dayStart: Date, days: Int): Date {
        val cal = Calendar.getInstance(utc)
        cal.time = dayStart
        cal.add(Calendar.DAY_OF_YEAR, days)
        return cal.time
    }

    fun isDueToday(asset: Asset, now: Date = Date()): Boolean {
        val next = nextAuditDate(asset) ?: return false
        val today = todayStart(now)
        val tomorrow = addDays(today, 1)
        return !next.before(today) && next.before(tomorrow)
    }

    fun isDueSoon(asset: Asset, dueSoonDays: Int = 7, now: Date = Date()): Boolean {
        if (dueSoonDays <= 0) return false
        val next = nextAuditDate(asset) ?: return false
        val today = todayStart(now)
        val start = addDays(today, 1)
        val end = addDays(today, dueSoonDays)
        return !next.before(start) && next.before(end)
    }

    fun isOverdue(asset: Asset, now: Date = Date()): Boolean {
        val next = nextAuditDate(asset) ?: return false
        return next.before(todayStart(now))
    }

    fun filterAssets(assets: List<Asset>, filter: AuditListFilter): List<Asset> =
        when (filter) {
            // All = overdue + today + soon (not every asset).
            AuditListFilter.All -> assets.filter { isOverdue(it) || isDueToday(it) || isDueSoon(it) }
            AuditListFilter.DueToday -> assets.filter { isDueToday(it) }
            AuditListFilter.DueSoon -> assets.filter { isDueSoon(it) }
            AuditListFilter.Overdue -> assets.filter { isOverdue(it) }
        }.sortedWith(
            compareBy(
                { nextAuditDate(it) ?: Date(Long.MAX_VALUE) },
                { it.decodedAssetTag.lowercase() },
            ),
        )

    fun overdueAssets(assets: List<Asset>): List<Asset> = filterAssets(assets, AuditListFilter.Overdue)
    fun dueTodayAssets(assets: List<Asset>): List<Asset> = filterAssets(assets, AuditListFilter.DueToday)
    fun dueSoonAssets(assets: List<Asset>): List<Asset> = filterAssets(assets, AuditListFilter.DueSoon)
}

fun matchesSearch(vararg fields: String?, query: String): Boolean {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return true
    return fields.any { it?.lowercase()?.contains(q) == true }
}

fun assetCardTitle(asset: Asset): String =
    asset.decodedModelName.ifEmpty { asset.decodedName.ifEmpty { asset.decodedAssetTag } }

fun assetResolvedStatus(asset: Asset): String? {
    val name = asset.decodedStatusLabelName.trim()
    if (name.isNotEmpty()) return name
    val meta = asset.statusLabel.statusMeta?.trim().orEmpty()
    return meta.ifEmpty { null }
}

fun assetCheckedOutAssignee(asset: Asset): String? {
    val assignee = asset.decodedAssignedToName.trim()
    if (assignee.isEmpty() || asset.assignedTo == null) return null
    return assignee
}

fun assetCheckedOutIcon(asset: Asset): ImageVector {
    val assigned = asset.assignedTo ?: return Icons.Default.Person
    return when {
        assigned.isLocation -> Icons.Default.LocationOn
        assigned.isAsset -> Icons.Default.Laptop
        else -> Icons.Default.Person
    }
}

/** Location line shown on asset cards. */
fun assetCardLocationName(asset: Asset): String? {
    val assigned = asset.assignedTo
    if (assigned == null) {
        val defaultName = HtmlDecoder.decode(asset.rtdLocation?.name.orEmpty()).trim()
        if (defaultName.isNotEmpty()) return defaultName
        val current = asset.decodedLocationName.trim()
        return current.ifEmpty { null }
    }
    if (assigned.isLocation) return null
    val location = asset.decodedLocationName.trim()
    if (location.isEmpty()) return null
    val assignee = asset.decodedAssignedToName.trim()
    if (assignee.isNotEmpty() && assignee.equals(location, ignoreCase = true)) return null
    return location
}

@Deprecated("Use AssetCard helpers")
fun assetCardSubtitle(asset: Asset): String =
    "Tag: ${asset.decodedAssetTag}" +
        if (asset.decodedSerial.isNotEmpty()) " · SN: ${asset.decodedSerial}" else ""

@Deprecated("Use assetCheckedOutAssignee")
fun assetAssigneeLine(asset: Asset): String? =
    assetCheckedOutAssignee(asset)?.let { "Toegewezen aan: $it" }

@Deprecated("Use assetCardLocationName")
fun assetLocationLine(asset: Asset): String? =
    assetCardLocationName(asset)?.let { "Locatie: $it" }

/** Resolve relative Snipe-IT image paths (and optional cache-buster). */
fun resolveSnipeImageUrl(baseUrl: String, path: String?, cacheBuster: String? = null): String? {
    val trimmed = path?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    val lower = trimmed.lowercase(Locale.US)
    if (lower.endsWith("/uploads/default.png") || lower.endsWith("/uploads/default.jpg")) {
        return null
    }

    val base = when {
        trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true) -> trimmed
        trimmed.startsWith("/") && baseUrl.isNotEmpty() -> baseUrl.trimEnd('/') + trimmed
        else -> null
    } ?: return null

    val buster = cacheBuster?.trim().orEmpty()
    if (buster.isEmpty()) return base

    val separator = if (base.contains('?')) '&' else '?'
    val withoutV = base.replace(Regex("[?&]v=[^&]*"), "").trimEnd('?', '&')
    return "$withoutV${if (withoutV.contains('?')) '&' else separator}v=$buster"
}

fun formatPurchaseDate(raw: String?): String? {
    val trimmed = raw?.trim().orEmpty()
    if (trimmed.isEmpty()) return null
    return trimmed.take(10)
}

/** Warranty expiry: API date, else purchase date + months. */
object WarrantyHelper {
    fun expiresDate(asset: Asset): Date? {
        val fromApi = sequenceOf(
            asset.warrantyExpires?.date,
            asset.warrantyExpires?.datetime,
            asset.warrantyExpires?.formatted,
        ).mapNotNull { it?.trim()?.takeIf { value -> value.isNotEmpty() } }
            .firstNotNullOfOrNull { DateInfo.parseAPIDate(it) }
        if (fromApi != null) return startOfDay(fromApi)

        val purchaseRaw = asset.purchaseDate?.date?.trim().orEmpty()
        val months = asset.warrantyMonths
            ?.filter { it.isDigit() }
            ?.toIntOrNull()
            ?.takeIf { it > 0 }
            ?: return null
        val purchase = DateInfo.parseAPIDate(purchaseRaw) ?: return null
        val cal = Calendar.getInstance()
        cal.time = purchase
        cal.add(Calendar.MONTH, months)
        return startOfDay(cal.time)
    }

    fun isExpired(expires: Date, now: Date = Date()): Boolean =
        expires.before(startOfDay(now))

    fun formattedExpires(expires: Date): String {
        val formatter = SimpleDateFormat.getDateInstance(SimpleDateFormat.MEDIUM, Locale.getDefault())
        return formatter.format(expires)
    }

    private fun startOfDay(date: Date): Date {
        val cal = Calendar.getInstance()
        cal.time = date
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.time
    }
}
