package com.callandt.snipemobile.ui.util

import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.data.model.Component
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.data.model.DateInfo
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.data.model.Location
import com.callandt.snipemobile.data.model.User
import java.util.Date
import java.util.Locale
import kotlin.math.sign

enum class ListSortOrder {
    Ascending,
    Descending,
}

enum class ListSortField {
    Name,
    UpdatedAt,
    CreatedAt,
    AssetTag,
    PurchaseDate,
    Remaining,
    Location,
    EolDate,
    WarrantyExpires,
    NextAuditDate,
    LastAuditDate,
    LastCheckout,
    LastCheckin,
    ExpectedCheckin,
    ExpirationDate,
    TerminationDate,
    StartDate,
    CompletionDate,
    ;

    val localizedTitle: String
        get() = when (this) {
            Name -> L10n.string("name")
            UpdatedAt -> L10n.string("sort_last_modified")
            CreatedAt -> L10n.string("created_date")
            AssetTag -> L10n.string("asset_tag")
            PurchaseDate -> L10n.string("purchase_date")
            Remaining -> L10n.string("remaining")
            Location -> L10n.string("location")
            EolDate -> L10n.string("eol_date")
            WarrantyExpires -> L10n.string("warranty_expires")
            NextAuditDate -> L10n.string("next_audit_date")
            LastAuditDate -> L10n.string("last_audit_date")
            LastCheckout -> L10n.string("last_checkout")
            LastCheckin -> L10n.string("last_checkin")
            ExpectedCheckin -> L10n.string("expected_checkin")
            ExpirationDate -> L10n.string("expiration_date")
            TerminationDate -> L10n.string("termination_date")
            StartDate -> L10n.string("start_date")
            CompletionDate -> L10n.string("completion_date")
        }

    val kind: Kind
        get() = when (this) {
            Name, Location -> Kind.Text
            AssetTag, Remaining -> Kind.Number
            else -> Kind.Date
        }

    val defaultOrder: ListSortOrder
        get() = when (this) {
            Name, Location -> ListSortOrder.Ascending
            AssetTag -> ListSortOrder.Descending
            EolDate, WarrantyExpires, NextAuditDate, ExpirationDate, TerminationDate, ExpectedCheckin ->
                ListSortOrder.Ascending
            else -> ListSortOrder.Descending
        }

    val isDeadline: Boolean
        get() = when (this) {
            EolDate, WarrantyExpires, NextAuditDate, ExpirationDate, TerminationDate, ExpectedCheckin -> true
            else -> false
        }

    val ascendingTitle: String
        get() = when (kind) {
            Kind.Text -> "A–Z"
            Kind.Date -> L10n.string("sort_oldest")
            Kind.Number -> L10n.string("sort_low_high")
        }

    val descendingTitle: String
        get() = when (kind) {
            Kind.Text -> "Z–A"
            Kind.Date -> L10n.string("sort_newest")
            Kind.Number -> L10n.string("sort_high_low")
        }

    enum class Kind { Text, Date, Number }
}

data class ListSort(
    val field: ListSortField,
    val order: ListSortOrder,
) {
    companion object {
        val nameAscending = ListSort(ListSortField.Name, ListSortOrder.Ascending)
        val assetTagDescending = ListSort(ListSortField.AssetTag, ListSortOrder.Descending)
        val updatedDescending = ListSort(ListSortField.UpdatedAt, ListSortOrder.Descending)
        val startDateDescending = ListSort(ListSortField.StartDate, ListSortOrder.Descending)
    }
}

sealed class ListSortComparable {
    data class Text(val value: String) : ListSortComparable()
    data class NumericText(val value: String) : ListSortComparable()
    data class DateValue(val value: Date?) : ListSortComparable()
    data class NumberValue(val value: Double?) : ListSortComparable()

    fun compareTo(other: ListSortComparable, order: ListSortOrder): Int = when {
        this is Text && other is Text ->
            signed(value.lowercase(Locale.ROOT).compareTo(other.value.lowercase(Locale.ROOT)), order)
        this is NumericText && other is NumericText ->
            signed(numericSortKey(value).compareTo(numericSortKey(other.value)), order)
        this is DateValue && other is DateValue ->
            compareOptional(value, other.value, order)
        this is NumberValue && other is NumberValue ->
            compareOptional(value, other.value, order)
        else -> 0
    }

    private fun <T : Comparable<T>> compareOptional(
        lhs: T?,
        rhs: T?,
        order: ListSortOrder,
    ): Int = when {
        lhs == null && rhs == null -> 0
        lhs == null -> 1
        rhs == null -> -1
        else -> signed(lhs.compareTo(rhs), order)
    }
}

data class ListSortKey<T>(
    val field: ListSortField,
    val value: (T) -> ListSortComparable,
)

fun <T> List<T>.sortedByListSort(
    sort: ListSort,
    keys: List<ListSortKey<T>>,
    idOf: (T) -> Int,
): List<T> {
    val key = keys.firstOrNull { it.field == sort.field } ?: return this
    val decorated = map { Triple(it, key.value(it), idOf(it)) }
    val comparator = Comparator<Triple<T, ListSortComparable, Int>> { lhs, rhs ->
        val comparison = lhs.second.compareTo(rhs.second, sort.order)
        if (comparison != 0) comparison else lhs.third.compareTo(rhs.third)
    }
    return try {
        decorated.sortedWith(comparator).map { it.first }
    } catch (_: IllegalArgumentException) {
        decorated.sortedBy { it.third }.map { it.first }
    }
}

object ListSortCatalog {
    val assets: List<ListSortKey<Asset>> = listOf(
        ListSortKey(ListSortField.Name) {
            ListSortComparable.Text(it.decodedName.ifEmpty { it.decodedAssetTag })
        },
        ListSortKey(ListSortField.AssetTag) { ListSortComparable.NumericText(it.decodedAssetTag) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
        ListSortKey(ListSortField.PurchaseDate) { ListSortComparable.DateValue(it.purchaseDate?.parsedDate) },
        ListSortKey(ListSortField.EolDate) { ListSortComparable.DateValue(it.assetEolDate?.parsedDate) },
        ListSortKey(ListSortField.WarrantyExpires) { ListSortComparable.DateValue(it.warrantyExpires?.parsedDate) },
        ListSortKey(ListSortField.NextAuditDate) { ListSortComparable.DateValue(it.nextAuditDate?.parsedDate) },
        ListSortKey(ListSortField.LastAuditDate) { ListSortComparable.DateValue(it.lastAuditDate?.parsedDate) },
        ListSortKey(ListSortField.LastCheckout) { ListSortComparable.DateValue(it.lastCheckout?.parsedDate) },
        ListSortKey(ListSortField.LastCheckin) { ListSortComparable.DateValue(it.lastCheckin?.parsedDate) },
        ListSortKey(ListSortField.ExpectedCheckin) { ListSortComparable.DateValue(it.expectedCheckin?.parsedDate) },
    )

    val licenses: List<ListSortKey<License>> = listOf(
        ListSortKey(ListSortField.Name) { ListSortComparable.Text(it.decodedName) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
        ListSortKey(ListSortField.PurchaseDate) { ListSortComparable.DateValue(it.purchaseDate?.parsedDate) },
        ListSortKey(ListSortField.ExpirationDate) { ListSortComparable.DateValue(it.expirationDate?.parsedDate) },
        ListSortKey(ListSortField.TerminationDate) { ListSortComparable.DateValue(it.terminationDate?.parsedDate) },
        ListSortKey(ListSortField.Remaining) {
            ListSortComparable.NumberValue((it.remaining ?: it.freeSeatsCount)?.toDouble())
        },
    )

    val accessories: List<ListSortKey<Accessory>> = listOf(
        ListSortKey(ListSortField.Name) { ListSortComparable.Text(it.decodedName) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
        ListSortKey(ListSortField.PurchaseDate) { ListSortComparable.DateValue(DateInfo.parseAPIDate(it.purchaseDate)) },
        ListSortKey(ListSortField.Remaining) {
            ListSortComparable.NumberValue((it.remaining ?: it.qty)?.toDouble())
        },
        ListSortKey(ListSortField.Location) { ListSortComparable.Text(it.decodedLocationName) },
    )

    val consumables: List<ListSortKey<Consumable>> = listOf(
        ListSortKey(ListSortField.Name) { ListSortComparable.Text(it.decodedName) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
        ListSortKey(ListSortField.PurchaseDate) { ListSortComparable.DateValue(DateInfo.parseAPIDate(it.purchaseDate)) },
        ListSortKey(ListSortField.Remaining) {
            ListSortComparable.NumberValue((it.remaining ?: it.qty)?.toDouble())
        },
        ListSortKey(ListSortField.Location) { ListSortComparable.Text(it.decodedLocationName) },
    )

    val components: List<ListSortKey<Component>> = listOf(
        ListSortKey(ListSortField.Name) { ListSortComparable.Text(it.decodedName) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
        ListSortKey(ListSortField.PurchaseDate) { ListSortComparable.DateValue(DateInfo.parseAPIDate(it.purchaseDate)) },
        ListSortKey(ListSortField.Remaining) {
            ListSortComparable.NumberValue((it.remaining ?: it.qty)?.toDouble())
        },
        ListSortKey(ListSortField.Location) { ListSortComparable.Text(it.decodedLocationName) },
    )

    val users: List<ListSortKey<User>> = listOf(
        ListSortKey(ListSortField.Name) { ListSortComparable.Text(it.decodedName) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
        ListSortKey(ListSortField.Location) { ListSortComparable.Text(it.decodedLocationName) },
    )

    val locations: List<ListSortKey<Location>> = listOf(
        ListSortKey(ListSortField.Name) { ListSortComparable.Text(it.decodedName) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
    )

    val maintenances: List<ListSortKey<AssetMaintenance>> = listOf(
        ListSortKey(ListSortField.Name) { ListSortComparable.Text(it.decodedTitle) },
        ListSortKey(ListSortField.StartDate) { ListSortComparable.DateValue(it.startDate?.parsedDate) },
        ListSortKey(ListSortField.UpdatedAt) { ListSortComparable.DateValue(it.updatedAt?.parsedDate) },
        ListSortKey(ListSortField.CreatedAt) { ListSortComparable.DateValue(it.createdAt?.parsedDate) },
        ListSortKey(ListSortField.CompletionDate) {
            ListSortComparable.DateValue(it.completedAt?.parsedDate ?: it.completionDate?.parsedDate)
        },
    )
}

private fun signed(raw: Int, order: ListSortOrder): Int =
    if (order == ListSortOrder.Ascending) raw.sign else -raw.sign

private val DIGIT_RUNS = Regex("\\d+")

/** Numeric chunks so 2 sorts before 10. */
internal fun numericSortKey(value: String): String =
    DIGIT_RUNS.replace(value.lowercase(Locale.ROOT)) { match ->
        val digits = match.value.trimStart('0').ifEmpty { "0" }
        digits.length.toString().padStart(4, '0') + digits
    }
