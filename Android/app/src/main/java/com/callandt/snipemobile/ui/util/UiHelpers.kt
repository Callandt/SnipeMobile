package com.callandt.snipemobile.ui.util

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Person
import androidx.compose.ui.graphics.vector.ImageVector
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.data.model.Component
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.data.model.DateInfo
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.data.model.Location
import com.callandt.snipemobile.data.model.User
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

fun assetMatchesSearch(asset: Asset, query: String): Boolean {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return true
    if (
        matchesSearch(
            asset.decodedName,
            asset.decodedAssetTag,
            asset.decodedSerial,
            asset.decodedModelName,
            asset.modelNumber,
            asset.decodedStatusLabelName,
            asset.decodedCategoryName,
            asset.decodedManufacturerName,
            asset.decodedSupplierName,
            asset.decodedCompanyName,
            asset.decodedLocationName,
            asset.rtdLocation?.name?.let(HtmlDecoder::decode),
            asset.decodedAssignedToName,
            asset.decodedNotes,
            asset.orderNumber,
            asset.altBarcode,
            asset.jobtitle?.let(HtmlDecoder::decode),
            query = q,
        )
    ) {
        return true
    }
    return asset.customFields?.values?.any { field ->
        field.decodedValue.lowercase().contains(q) || field.field.lowercase().contains(q)
    } == true
}

fun userMatchesSearch(user: User, query: String): Boolean =
    matchesSearch(
        user.decodedName,
        user.decodedFirstName,
        user.decodedLastName,
        user.decodedUsername,
        user.decodedEmail,
        user.decodedPhone,
        user.decodedEmployeeNumber,
        user.decodedJobtitle,
        user.decodedNotes,
        user.decodedLocationName,
        user.decodedCompanyName,
        query = query,
    )

fun accessoryMatchesSearch(accessory: Accessory, query: String): Boolean =
    matchesSearch(
        accessory.decodedName,
        accessory.decodedAssetTag,
        accessory.statusLabel?.name?.let(HtmlDecoder::decode),
        accessory.decodedAssignedToName,
        accessory.decodedLocationName,
        accessory.decodedManufacturerName,
        accessory.decodedCategoryName,
        accessory.company?.name?.let(HtmlDecoder::decode),
        accessory.supplier?.name?.let(HtmlDecoder::decode),
        accessory.modelNumber,
        accessory.orderNumber,
        query = query,
    )

fun licenseMatchesSearch(license: License, query: String): Boolean =
    matchesSearch(
        license.decodedName,
        license.decodedProductKey,
        license.decodedLicenseName,
        license.decodedLicenseEmail,
        license.serial,
        license.decodedNotes,
        license.decodedManufacturerName,
        license.decodedCategoryName,
        license.decodedSupplierName,
        license.decodedCompanyName,
        license.orderNumber,
        license.purchaseOrder,
        query = query,
    )

fun consumableMatchesSearch(consumable: Consumable, query: String): Boolean =
    matchesSearch(
        consumable.decodedName,
        consumable.decodedItemNo,
        consumable.decodedModelNumber,
        consumable.decodedLocationName,
        consumable.decodedManufacturerName,
        consumable.decodedCategoryName,
        consumable.decodedCompanyName,
        consumable.supplier?.name?.let(HtmlDecoder::decode),
        consumable.orderNumber,
        consumable.notes?.let(HtmlDecoder::decode),
        query = query,
    )

fun componentMatchesSearch(component: Component, query: String): Boolean =
    matchesSearch(
        component.decodedName,
        component.decodedSerial,
        component.decodedModelNumber,
        component.decodedLocationName,
        component.decodedManufacturerName,
        component.decodedCategoryName,
        component.decodedCompanyName,
        component.supplier?.name?.let(HtmlDecoder::decode),
        component.orderNumber,
        component.notes?.let(HtmlDecoder::decode),
        query = query,
    )

fun locationMatchesSearch(location: Location, query: String): Boolean =
    matchesSearch(
        location.decodedName,
        location.address,
        location.address2,
        location.city,
        location.state,
        location.country,
        location.zip,
        location.parent?.name?.let(HtmlDecoder::decode),
        query = query,
    )

fun maintenanceMatchesSearch(record: AssetMaintenance, query: String): Boolean =
    matchesSearch(
        record.decodedTitle,
        record.displayType,
        record.assetDisplayLabel,
        record.decodedNotes,
        record.supplier?.name?.let(HtmlDecoder::decode),
        record.cost,
        record.responsibleParty?.name?.let(HtmlDecoder::decode),
        record.createdBy?.name?.let(HtmlDecoder::decode),
        record.completedBy?.name?.let(HtmlDecoder::decode),
        query = query,
    )

/** Extra searchable blob for picker UIs (not shown as subtitle). */
fun userPickerSearchText(user: User): String =
    listOf(
        user.decodedUsername,
        user.decodedEmail,
        user.decodedPhone,
        user.decodedEmployeeNumber,
        user.decodedJobtitle,
        user.decodedLastName,
        user.decodedCompanyName,
        user.decodedNotes,
    ).filter { it.isNotBlank() }.joinToString(" ")

/** Logged-in API user first, then A–Z. */
fun usersForNamePicker(users: List<User>, currentUser: User?): List<User> {
    val pinned = currentUser?.let { me ->
        users.firstOrNull { it.id == me.id } ?: me
    }
    val pinnedId = pinned?.id
    val rest = users
        .asSequence()
        .filter { pinnedId == null || it.id != pinnedId }
        .sortedBy { it.decodedName.lowercase(Locale.getDefault()) }
        .toList()
    return if (pinned != null) listOf(pinned) + rest else rest
}

fun locationPickerSearchText(location: Location): String =
    listOf(
        location.address,
        location.address2,
        location.city,
        location.state,
        location.country,
        location.zip,
        location.parent?.name?.let(HtmlDecoder::decode),
    ).mapNotNull { it?.takeIf(String::isNotBlank) }.joinToString(" ")

fun assetPickerSearchText(asset: Asset): String =
    buildList {
        add(asset.decodedSerial)
        add(asset.decodedModelName)
        add(asset.modelNumber.orEmpty())
        add(asset.decodedLocationName)
        add(asset.decodedAssignedToName)
        add(asset.decodedNotes)
        add(asset.orderNumber.orEmpty())
        add(asset.altBarcode.orEmpty())
        asset.customFields?.values?.forEach { add(it.decodedValue) }
    }.filter { it.isNotBlank() }.joinToString(" ")


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
