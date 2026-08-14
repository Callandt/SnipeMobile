@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
@file:Suppress("SpellCheckingInspection")

package com.callandt.snipemobile.data.model

import com.callandt.snipemobile.util.HtmlDecoder
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNames
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Shared JSON config for Snipe-IT API and local cache. */
val SnipeJson: Json = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    isLenient = true
    encodeDefaults = true
}

// ---------------------------------------------------------------------------
// Decode helpers
// ---------------------------------------------------------------------------

internal object SnipeDecoders {
    fun flexibleInt(element: JsonElement?): Int? {
        if (element == null || element is JsonNull) return null
        if (element !is JsonPrimitive) return null
        element.intOrNull?.let { return it }
        element.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }?.toIntOrNull()?.let { return it }
        element.doubleOrNull?.let { return it.toInt() }
        return null
    }

    /** Nested object, or null/`false`. */
    fun <T> decodeOptionalObject(element: JsonElement?, serializer: kotlinx.serialization.DeserializationStrategy<T>): T? {
        if (element == null || element is JsonNull) return null
        if (element is JsonPrimitive) {
            val asBool = element.booleanOrNull
            if (asBool != null) return null
            val text = element.contentOrNull?.trim().orEmpty()
            if (text.isEmpty() || text.equals("false", ignoreCase = true)) return null
            return null
        }
        return runCatching { SnipeJson.decodeFromJsonElement(serializer, element) }.getOrNull()
    }

    fun flexibleStringOrNumber(element: JsonElement?): String? {
        if (element == null || element is JsonNull) return null
        if (element !is JsonPrimitive) return null
        element.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        element.doubleOrNull?.let { return it.toString() }
        element.intOrNull?.let { return it.toString() }
        return null
    }

    fun flexibleBool(element: JsonElement?, default: Boolean = false): Boolean {
        if (element == null || element is JsonNull) return default
        val prim = element.jsonPrimitive
        prim.booleanOrNull?.let { return it }
        prim.intOrNull?.let { return it != 0 }
        return when (prim.contentOrNull?.trim()?.lowercase(Locale.US)) {
            "1", "true", "yes" -> true
            "0", "false", "no" -> false
            else -> default
        }
    }

    /** Lenient DateInfo: object, plain string, or false/empty → null. */
    fun flexibleDateInfo(element: JsonElement?): DateInfo? {
        if (element == null || element is JsonNull) return null
        val info = runCatching { SnipeJson.decodeFromJsonElement(DateInfo.serializer(), element) }.getOrNull()
            ?: return null
        val hasValue = !info.date.isNullOrBlank() ||
            !info.datetime.isNullOrBlank() ||
            !info.formatted.isNullOrBlank()
        return info.takeIf { hasValue }
    }

    fun purchaseDateString(element: JsonElement?): String? {
        if (element == null || element is JsonNull) return null
        if (element is JsonObject) {
            val info = runCatching { SnipeJson.decodeFromJsonElement(DateInfo.serializer(), element) }.getOrNull()
            val raw = (info?.date ?: info?.formatted)?.trim().orEmpty()
            return raw.takeIf { it.isNotEmpty() }
        }
        val text = element.jsonPrimitive.contentOrNull?.trim().orEmpty()
        return text.takeIf { it.isNotEmpty() }
    }

    fun decodeUserGroups(element: JsonElement?): List<UserGroup> {
        if (element == null || element is JsonNull) return emptyList()
        if (element is JsonArray) {
            return SnipeJson.decodeFromJsonElement(element)
        }
        if (element is JsonObject) {
            element["rows"]?.let { rows ->
                if (rows is JsonArray) {
                    return SnipeJson.decodeFromJsonElement(rows)
                }
            }
        }
        return emptyList()
    }

    fun normalizeUserImage(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        val lower = trimmed.lowercase(Locale.US)
        if (lower.endsWith("/uploads/default.png") || lower.endsWith("/uploads/default.jpg")) {
            return null
        }
        return trimmed
    }
}

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

@Serializable(with = DateInfoSerializer::class)
data class DateInfo(
    val date: String? = null,
    val formatted: String? = null,
    val datetime: String? = null,
) {
    companion object {
        private val API_FORMATS = listOf(
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        )

        fun parseAPIDate(raw: String?): Date? {
            val trimmed = raw?.trim().orEmpty()
            if (trimmed.isEmpty()) return null
            val parsers = apiDateParsers.get() ?: return null
            for (parser in parsers) {
                runCatching { parser.parse(trimmed) }.getOrNull()?.let { return it }
                val format = parser.toPattern()
                if (format == "yyyy-MM-dd HH:mm:ss" && trimmed.length >= 19) {
                    runCatching { parser.parse(trimmed.take(19)) }.getOrNull()?.let { return it }
                }
                if (format == "yyyy-MM-dd" && trimmed.length >= 10) {
                    runCatching { parser.parse(trimmed.take(10)) }.getOrNull()?.let { return it }
                }
            }
            return null
        }

        private val apiDateParsers = ThreadLocal.withInitial {
            val utc = TimeZone.getTimeZone("UTC")
            API_FORMATS.map { format ->
                SimpleDateFormat(format, Locale.US).apply {
                    timeZone = utc
                    isLenient = false
                }
            }
        }
    }

    fun localizedDisplay(includeTime: Boolean = true): String? {
        val source = date?.takeIf { it.isNotEmpty() }
            ?: datetime?.takeIf { it.isNotEmpty() }
            ?: formatted?.takeIf { it.isNotEmpty() }
            ?: return null

        val parsed = parseAPIDate(source) ?: return formatted ?: source
        val hasTime = source.length > 10 && (source.contains('T') || source.contains(' '))

        val locale = Locale.getDefault()
        val formatter = if (includeTime && hasTime) {
            SimpleDateFormat.getDateTimeInstance(SimpleDateFormat.MEDIUM, SimpleDateFormat.SHORT, locale)
        } else {
            SimpleDateFormat.getDateInstance(SimpleDateFormat.MEDIUM, locale)
        }
        (formatter as SimpleDateFormat).timeZone = TimeZone.getDefault()
        return formatter.format(parsed)
    }

    val parsedDate: Date?
        get() = parseAPIDate(datetime) ?: parseAPIDate(date) ?: parseAPIDate(formatted)
}

/** Accepts Snipe-IT date objects, plain strings, or false/empty. */
object DateInfoSerializer : KSerializer<DateInfo> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("DateInfo") {
        element<String?>("date", isOptional = true)
        element<String?>("formatted", isOptional = true)
        element<String?>("datetime", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): DateInfo {
        return when (val element = (decoder as JsonDecoder).decodeJsonElement()) {
            is JsonNull -> DateInfo()
            is JsonPrimitive -> {
                if (element.booleanOrNull == false) return DateInfo()
                val text = element.contentOrNull?.trim().orEmpty()
                if (text.isEmpty() || text.equals("false", ignoreCase = true)) DateInfo()
                else DateInfo(date = text)
            }
            is JsonObject -> DateInfo(
                date = element["date"]?.let { SnipeDecoders.flexibleStringOrNumber(it) },
                formatted = element["formatted"]?.let { SnipeDecoders.flexibleStringOrNumber(it) },
                datetime = element["datetime"]?.let { SnipeDecoders.flexibleStringOrNumber(it) },
            )
            else -> DateInfo()
        }
    }

    override fun serialize(encoder: Encoder, value: DateInfo) {
        val obj = buildJsonObject {
            value.date?.let { put("date", it) }
            value.formatted?.let { put("formatted", it) }
            value.datetime?.let { put("datetime", it) }
        }
        (encoder as JsonEncoder).encodeJsonElement(obj)
    }
}

@Serializable
data class NamedId(
    val id: Int,
    val name: String,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

typealias Model = NamedId

@Serializable(with = AssetModelRowSerializer::class)
data class AssetModelRow(
    val id: Int,
    val name: String,
    @SerialName("require_serial") val requireSerial: Boolean? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
    val requiresSerial: Boolean get() = requireSerial == true
}

object AssetModelRowSerializer : KSerializer<AssetModelRow> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("AssetModelRow")

    override fun deserialize(decoder: Decoder): AssetModelRow {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val requireSerial = obj["require_serial"]?.jsonPrimitive?.let { prim ->
            prim.booleanOrNull ?: prim.intOrNull?.let { it != 0 }
        }
        return AssetModelRow(
            id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
            name = obj["name"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            requireSerial = requireSerial,
        )
    }

    override fun serialize(encoder: Encoder, value: AssetModelRow) {
        val obj = buildJsonObject {
            put("id", value.id)
            put("name", value.name)
            value.requireSerial?.let { put("require_serial", it) }
        }
        (encoder as JsonEncoder).encodeJsonElement(obj)
    }
}

@Serializable(with = CategoryRowSerializer::class)
data class CategoryRow(
    val id: Int,
    val name: String,
    @SerialName("category_type") val categoryType: String? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

object CategoryRowSerializer : KSerializer<CategoryRow> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("CategoryRow") {
        element<Int>("id")
        element<String>("name")
        element<String?>("category_type", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): CategoryRow {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        return CategoryRow(
            id = SnipeDecoders.flexibleInt(obj["id"]) ?: 0,
            name = SnipeDecoders.flexibleStringOrNumber(obj["name"]).orEmpty(),
            categoryType = categoryTypeFrom(obj["category_type"] ?: obj["type"]),
        )
    }

    override fun serialize(encoder: Encoder, value: CategoryRow) {
        val obj = buildJsonObject {
            put("id", value.id)
            put("name", value.name)
            value.categoryType?.let { put("category_type", it) }
        }
        (encoder as JsonEncoder).encodeJsonElement(obj)
    }

    private fun categoryTypeFrom(element: JsonElement?): String? {
        if (element == null || element is JsonNull) return null
        if (element is JsonPrimitive) {
            return element.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
        }
        if (element is JsonObject) {
            return SnipeDecoders.flexibleStringOrNumber(element["type"])
                ?: SnipeDecoders.flexibleStringOrNumber(element["id"])?.takeIf { it.toIntOrNull() == null }
                ?: SnipeDecoders.flexibleStringOrNumber(element["name"])
        }
        return null
    }
}

typealias Category = NamedId
typealias Manufacturer = NamedId
typealias Supplier = NamedId
typealias Company = NamedId
typealias MaintenanceType = NamedId

@Serializable
data class StatusLabel(
    val id: Int,
    val name: String,
    @JsonNames("type", "status_type")
    val type: String? = null,
    @SerialName("status_meta") val statusMeta: String? = null,
) {
    val resolvedType: String get() = (type ?: "").trim().lowercase(Locale.US)
    val isDeployableType: Boolean get() = resolvedType.isEmpty() || resolvedType == "deployable"
    val decodedName: String get() = HtmlDecoder.decode(name)
}

@Serializable
data class AssignedTo(
    val id: Int,
    val username: String? = null,
    val name: String,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
    val email: String? = null,
    @SerialName("employee_number") val employeeNumber: String? = null,
    val type: String? = null,
) {
    private val normalizedType: String
        get() {
            val raw = (type ?: "").lowercase(Locale.US)
            return when {
                raw == "user" || raw.endsWith("\\user") -> "user"
                raw == "location" || raw.endsWith("\\location") -> "location"
                raw == "asset" || raw.endsWith("\\asset") -> "asset"
                else -> raw
            }
        }

    val isUser: Boolean get() = normalizedType == "user"
    val isLocation: Boolean get() = normalizedType == "location"
    val isAsset: Boolean get() = normalizedType == "asset"
    val decodedName: String get() = HtmlDecoder.decode(name)
}

@Serializable
data class LocationParent(
    val id: Int? = null,
    val name: String? = null,
)

@Serializable
data class Location(
    val id: Int,
    val name: String,
    val address: String? = null,
    val address2: String? = null,
    val city: String? = null,
    val state: String? = null,
    val country: String? = null,
    val zip: String? = null,
    val currency: String? = null,
    val parent: LocationParent? = null,
    @SerialName("created_at") val createdAt: DateInfo? = null,
    @SerialName("updated_at") val updatedAt: DateInfo? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

@Serializable
data class CreatedBy(
    val id: Int,
    val name: String,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

@Serializable
data class CustomField(
    val field: String,
    val value: String? = null,
    @SerialName("field_format") val fieldFormat: String? = null,
    val element: String? = null,
) {
    val decodedValue: String get() = HtmlDecoder.decode(value ?: "")
}

// ---------------------------------------------------------------------------
// Custom field definitions / fieldsets
// ---------------------------------------------------------------------------

/** A custom field definition, as returned by `/api/v1/fields` and fieldset endpoints. */
@Serializable
data class FieldDefinition(
    val id: Int,
    val name: String,
    val type: String? = null,
    @SerialName("field_values_array") val fieldValuesArray: List<String>? = null,
    @SerialName("db_column_name") val dbColumnName: String? = null,
    @SerialName("db_column") val dbColumn: String? = null,
    @SerialName("db_field") val dbField: String? = null,
    val field: String? = null,
    @SerialName("default_value") val defaultValue: String? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

/** A field entry within a fieldset's `fields.rows`. */
@Serializable
data class FieldsetField(
    val id: Int,
    val name: String,
    val type: String? = null,
    @SerialName("field_values_array") val fieldValuesArray: List<String>? = null,
)

/**
 * A Snipe-IT fieldset, mapping a set of custom fields to one or more asset models.
 * The `models` key can arrive as either `{ "rows": [...] }` or a plain array depending on
 * server version, so this uses a manual [Decoder].
 */
@Serializable(with = FieldsetSerializer::class)
data class Fieldset(
    val id: Int,
    val name: String,
    val fields: List<FieldsetField>,
    val modelIds: List<Int>,
)

object FieldsetSerializer : KSerializer<Fieldset> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Fieldset")

    override fun deserialize(decoder: Decoder): Fieldset {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0
        val name = obj["name"]?.jsonPrimitive?.contentOrNull.orEmpty()
        val fieldRows = obj["fields"]?.jsonObject?.get("rows")?.jsonArray.orEmpty()
        val fields = fieldRows.mapNotNull { element ->
            runCatching { SnipeJson.decodeFromJsonElement(FieldsetField.serializer(), element) }.getOrNull()
        }
        val modelIds = when (val modelsElement = obj["models"]) {
            is JsonObject -> modelsElement["rows"]?.jsonArray
                ?.mapNotNull { it.jsonObject["id"]?.jsonPrimitive?.intOrNull }.orEmpty()
            is JsonArray -> modelsElement.mapNotNull { it.jsonObject["id"]?.jsonPrimitive?.intOrNull }
            else -> emptyList()
        }
        return Fieldset(id = id, name = name, fields = fields, modelIds = modelIds)
    }

    override fun serialize(encoder: Encoder, value: Fieldset) {
        throw UnsupportedOperationException("Fieldset is decode-only")
    }
}

@Serializable
data class AvailableActions(
    val checkout: Boolean = false,
    val checkin: Boolean = false,
    val clone: Boolean = false,
    val restore: Boolean = false,
    val update: Boolean = false,
    val audit: Boolean = false,
    val delete: Boolean = false,
    /** From requestable hardware list. */
    val request: Boolean = false,
    val cancel: Boolean = false,
)

@Serializable
data class UserGroup(
    val id: Int,
    val name: String,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

// ---------------------------------------------------------------------------
// Asset
// ---------------------------------------------------------------------------

@Serializable(with = AssetSerializer::class)
data class Asset(
    val id: Int,
    val name: String = "",
    @SerialName("asset_tag") val assetTag: String,
    val serial: String? = null,
    val model: Model? = null,
    val byod: Boolean = false,
    val requestable: Boolean = false,
    @SerialName("model_number") val modelNumber: String? = null,
    val eol: String? = null,
    @SerialName("asset_eol_date") val assetEolDate: DateInfo? = null,
    @SerialName("status_label") val statusLabel: StatusLabel,
    val category: Category? = null,
    val manufacturer: Manufacturer? = null,
    val supplier: Supplier? = null,
    val notes: String? = null,
    @SerialName("order_number") val orderNumber: String? = null,
    val company: Company? = null,
    val location: Location? = null,
    @SerialName("rtd_location") val rtdLocation: Location? = null,
    val image: String? = null,
    val qr: String? = null,
    @SerialName("alt_barcode") val altBarcode: String? = null,
    @SerialName("assigned_to") val assignedTo: AssignedTo? = null,
    val jobtitle: String? = null,
    @SerialName("warranty_months") val warrantyMonths: String? = null,
    @SerialName("warranty_expires") val warrantyExpires: DateInfo? = null,
    @SerialName("created_by") val createdBy: CreatedBy? = null,
    @SerialName("created_at") val createdAt: DateInfo? = null,
    @SerialName("updated_at") val updatedAt: DateInfo? = null,
    @SerialName("last_audit_date") val lastAuditDate: DateInfo? = null,
    @SerialName("next_audit_date") val nextAuditDate: DateInfo? = null,
    @SerialName("deleted_at") val deletedAt: DateInfo? = null,
    @SerialName("purchase_date") val purchaseDate: DateInfo? = null,
    val age: String? = null,
    @SerialName("last_checkout") val lastCheckout: DateInfo? = null,
    @SerialName("last_checkin") val lastCheckin: DateInfo? = null,
    @SerialName("expected_checkin") val expectedCheckin: DateInfo? = null,
    @SerialName("purchase_cost") val purchaseCost: String? = null,
    @SerialName("checkin_counter") val checkinCounter: Int? = null,
    @SerialName("checkout_counter") val checkoutCounter: Int? = null,
    @SerialName("requests_counter") val requestsCounter: Int? = null,
    @SerialName("user_can_checkout") val userCanCheckout: Boolean = false,
    @SerialName("book_value") val bookValue: String? = null,
    @SerialName("custom_fields") val customFields: Map<String, CustomField>? = null,
    @SerialName("available_actions") val availableActions: AvailableActions? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
    val decodedAssetTag: String get() = HtmlDecoder.decode(assetTag)
    val decodedSerial: String get() = HtmlDecoder.decode(serial ?: "")
    val decodedModelName: String get() = HtmlDecoder.decode(model?.name ?: "")
    val decodedStatusLabelName: String get() = HtmlDecoder.decode(statusLabel.name)
    val decodedAssignedToName: String get() = HtmlDecoder.decode(assignedTo?.name ?: "")
    val decodedLocationName: String get() = HtmlDecoder.decode(location?.name ?: "")
    val decodedCategoryName: String get() = HtmlDecoder.decode(category?.name ?: "")
    val decodedManufacturerName: String get() = HtmlDecoder.decode(manufacturer?.name ?: "")
    val decodedSupplierName: String get() = HtmlDecoder.decode(supplier?.name ?: "")
    val decodedCompanyName: String get() = HtmlDecoder.decode(company?.name ?: "")
    val decodedNotes: String get() = HtmlDecoder.decode(notes ?: "")
    val decodedWarrantyMonths: String get() = HtmlDecoder.decode(warrantyMonths ?: "")
}

/**
 * Soft Asset decode: ignore bad fields instead of dropping the row.
 */
object AssetSerializer : KSerializer<Asset> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Asset")

    override fun deserialize(decoder: Decoder): Asset {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        // status_label object, or status string on requestable list.
        val statusLabel: StatusLabel = softDecode(obj["status_label"])
            ?: obj["status"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }?.let {
                StatusLabel(id = 0, name = it, statusMeta = it)
            }
            ?: StatusLabel(id = 0, name = "Unknown")

        // model object, or plain name string on requestable list.
        val model: Model? = softDecode(obj["model"])
            ?: obj["model"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }?.let {
                Model(id = 0, name = it)
            }

        // location object, or plain name string on requestable list.
        val location: Location? = softDecode(obj["location"])
            ?: obj["location"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }?.let {
                Location(id = 0, name = it)
            }

        // Missing flag → treat as requestable (requestable list).
        val requestable = if (obj.containsKey("requestable")) {
            SnipeDecoders.flexibleBool(obj["requestable"])
        } else {
            true
        }

        return Asset(
            id = SnipeDecoders.flexibleInt(obj["id"]) ?: 0,
            name = obj["name"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            assetTag = obj["asset_tag"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            serial = obj["serial"]?.jsonPrimitive?.contentOrNull,
            model = model,
            byod = SnipeDecoders.flexibleBool(obj["byod"]),
            requestable = requestable,
            modelNumber = SnipeDecoders.flexibleStringOrNumber(obj["model_number"]),
            eol = SnipeDecoders.flexibleStringOrNumber(obj["eol"]),
            assetEolDate = SnipeDecoders.flexibleDateInfo(obj["asset_eol_date"]),
            statusLabel = statusLabel,
            category = softDecode(obj["category"]),
            manufacturer = softDecode(obj["manufacturer"]),
            supplier = softDecode(obj["supplier"]),
            notes = obj["notes"]?.jsonPrimitive?.contentOrNull,
            orderNumber = SnipeDecoders.flexibleStringOrNumber(obj["order_number"]),
            company = softDecode(obj["company"]),
            location = location,
            rtdLocation = softDecode(obj["rtd_location"]),
            image = obj["image"]?.jsonPrimitive?.contentOrNull,
            qr = obj["qr"]?.jsonPrimitive?.contentOrNull,
            altBarcode = obj["alt_barcode"]?.jsonPrimitive?.contentOrNull,
            assignedTo = softDecode(obj["assigned_to"]),
            jobtitle = obj["jobtitle"]?.jsonPrimitive?.contentOrNull,
            warrantyMonths = SnipeDecoders.flexibleStringOrNumber(obj["warranty_months"]),
            warrantyExpires = SnipeDecoders.flexibleDateInfo(obj["warranty_expires"]),
            createdBy = softDecode(obj["created_by"]),
            createdAt = SnipeDecoders.flexibleDateInfo(obj["created_at"]),
            updatedAt = SnipeDecoders.flexibleDateInfo(obj["updated_at"]),
            lastAuditDate = SnipeDecoders.flexibleDateInfo(obj["last_audit_date"]),
            nextAuditDate = SnipeDecoders.flexibleDateInfo(obj["next_audit_date"]),
            deletedAt = SnipeDecoders.flexibleDateInfo(obj["deleted_at"]),
            purchaseDate = SnipeDecoders.flexibleDateInfo(obj["purchase_date"]),
            age = SnipeDecoders.flexibleStringOrNumber(obj["age"]),
            lastCheckout = SnipeDecoders.flexibleDateInfo(obj["last_checkout"]),
            lastCheckin = SnipeDecoders.flexibleDateInfo(obj["last_checkin"]),
            expectedCheckin = SnipeDecoders.flexibleDateInfo(obj["expected_checkin"]),
            purchaseCost = SnipeDecoders.flexibleStringOrNumber(obj["purchase_cost"]),
            checkinCounter = SnipeDecoders.flexibleInt(obj["checkin_counter"]),
            checkoutCounter = SnipeDecoders.flexibleInt(obj["checkout_counter"]),
            requestsCounter = SnipeDecoders.flexibleInt(obj["requests_counter"]),
            userCanCheckout = SnipeDecoders.flexibleBool(obj["user_can_checkout"]),
            bookValue = SnipeDecoders.flexibleStringOrNumber(obj["book_value"]),
            customFields = softDecode(obj["custom_fields"]),
            availableActions = softDecode(obj["available_actions"]),
        )
    }

    override fun serialize(encoder: Encoder, value: Asset) {
        (encoder as JsonEncoder).encodeJsonElement(SnipeJson.encodeToJsonElement(value.toWire()))
    }

    private inline fun <reified T> softDecode(element: JsonElement?): T? =
        element?.takeUnless { it is JsonNull }?.let {
            runCatching { SnipeJson.decodeFromJsonElement<T>(it) }.getOrNull()
        }

    private fun Asset.toWire() = AssetWire(
        id = id,
        name = name,
        assetTag = assetTag,
        serial = serial,
        model = model,
        byod = byod,
        requestable = requestable,
        modelNumber = modelNumber,
        eol = eol,
        assetEolDate = assetEolDate,
        statusLabel = statusLabel,
        category = category,
        manufacturer = manufacturer,
        supplier = supplier,
        notes = notes,
        orderNumber = orderNumber,
        company = company,
        location = location,
        rtdLocation = rtdLocation,
        image = image,
        qr = qr,
        altBarcode = altBarcode,
        assignedTo = assignedTo,
        jobtitle = jobtitle,
        warrantyMonths = warrantyMonths,
        warrantyExpires = warrantyExpires,
        createdBy = createdBy,
        createdAt = createdAt,
        updatedAt = updatedAt,
        lastAuditDate = lastAuditDate,
        nextAuditDate = nextAuditDate,
        deletedAt = deletedAt,
        purchaseDate = purchaseDate,
        age = age,
        lastCheckout = lastCheckout,
        lastCheckin = lastCheckin,
        expectedCheckin = expectedCheckin,
        purchaseCost = purchaseCost,
        checkinCounter = checkinCounter,
        checkoutCounter = checkoutCounter,
        requestsCounter = requestsCounter,
        userCanCheckout = userCanCheckout,
        bookValue = bookValue,
        customFields = customFields,
        availableActions = availableActions,
    )

    @Serializable
    private data class AssetWire(
        val id: Int,
        val name: String = "",
        @SerialName("asset_tag") val assetTag: String,
        val serial: String? = null,
        val model: Model? = null,
        val byod: Boolean = false,
        val requestable: Boolean = false,
        @SerialName("model_number") val modelNumber: String? = null,
        val eol: String? = null,
        @SerialName("asset_eol_date") val assetEolDate: DateInfo? = null,
        @SerialName("status_label") val statusLabel: StatusLabel,
        val category: Category? = null,
        val manufacturer: Manufacturer? = null,
        val supplier: Supplier? = null,
        val notes: String? = null,
        @SerialName("order_number") val orderNumber: String? = null,
        val company: Company? = null,
        val location: Location? = null,
        @SerialName("rtd_location") val rtdLocation: Location? = null,
        val image: String? = null,
        val qr: String? = null,
        @SerialName("alt_barcode") val altBarcode: String? = null,
        @SerialName("assigned_to") val assignedTo: AssignedTo? = null,
        val jobtitle: String? = null,
        @SerialName("warranty_months") val warrantyMonths: String? = null,
        @SerialName("warranty_expires") val warrantyExpires: DateInfo? = null,
        @SerialName("created_by") val createdBy: CreatedBy? = null,
        @SerialName("created_at") val createdAt: DateInfo? = null,
        @SerialName("updated_at") val updatedAt: DateInfo? = null,
        @SerialName("last_audit_date") val lastAuditDate: DateInfo? = null,
        @SerialName("next_audit_date") val nextAuditDate: DateInfo? = null,
        @SerialName("deleted_at") val deletedAt: DateInfo? = null,
        @SerialName("purchase_date") val purchaseDate: DateInfo? = null,
        val age: String? = null,
        @SerialName("last_checkout") val lastCheckout: DateInfo? = null,
        @SerialName("last_checkin") val lastCheckin: DateInfo? = null,
        @SerialName("expected_checkin") val expectedCheckin: DateInfo? = null,
        @SerialName("purchase_cost") val purchaseCost: String? = null,
        @SerialName("checkin_counter") val checkinCounter: Int? = null,
        @SerialName("checkout_counter") val checkoutCounter: Int? = null,
        @SerialName("requests_counter") val requestsCounter: Int? = null,
        @SerialName("user_can_checkout") val userCanCheckout: Boolean = false,
        @SerialName("book_value") val bookValue: String? = null,
        @SerialName("custom_fields") val customFields: Map<String, CustomField>? = null,
        @SerialName("available_actions") val availableActions: AvailableActions? = null,
    )
}

// ---------------------------------------------------------------------------
// User
// ---------------------------------------------------------------------------

@Serializable(with = UserSerializer::class)
data class User(
    val id: Int,
    val name: String,
    val firstName: String,
    val lastName: String? = null,
    val username: String? = null,
    val email: String? = null,
    val phone: String? = null,
    val image: String? = null,
    val location: Location? = null,
    val company: Company? = null,
    @SerialName("employee_num") val employeeNumber: String? = null,
    val jobtitle: String? = null,
    val notes: String? = null,
    val activated: Boolean? = null,
    val groups: List<UserGroup> = emptyList(),
    val createdAt: DateInfo? = null,
    val updatedAt: DateInfo? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
    val decodedFirstName: String get() = HtmlDecoder.decode(firstName)
    val decodedLastName: String get() = HtmlDecoder.decode(lastName ?: "")
    val decodedUsername: String get() = HtmlDecoder.decode(username ?: "")
    val decodedEmail: String get() = HtmlDecoder.decode(email ?: "")
    val decodedPhone: String get() = HtmlDecoder.decode(phone ?: "")
    val decodedLocationName: String get() = HtmlDecoder.decode(location?.name ?: "")
    val decodedCompanyName: String get() = HtmlDecoder.decode(company?.name ?: "")
    val decodedEmployeeNumber: String get() = HtmlDecoder.decode(employeeNumber ?: "")
    val decodedJobtitle: String get() = HtmlDecoder.decode(jobtitle ?: "")
    val decodedNotes: String get() = HtmlDecoder.decode(notes ?: "")
}

object UserSerializer : KSerializer<User> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("User") {
        element("id", Int.serializer().descriptor)
    }

    override fun deserialize(decoder: Decoder): User {
        val input = decoder as JsonDecoder
        val obj = input.decodeJsonElement().jsonObject
        val imageRaw = obj["image"]?.jsonPrimitive?.contentOrNull
            ?: obj["avatar"]?.jsonPrimitive?.contentOrNull
        return User(
            id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
            name = obj["name"]?.jsonPrimitive?.contentOrNull ?: "",
            firstName = obj["first_name"]?.jsonPrimitive?.contentOrNull ?: "",
            lastName = obj["last_name"]?.jsonPrimitive?.contentOrNull,
            username = obj["username"]?.jsonPrimitive?.contentOrNull,
            email = obj["email"]?.jsonPrimitive?.contentOrNull,
            phone = obj["phone"]?.jsonPrimitive?.contentOrNull,
            image = SnipeDecoders.normalizeUserImage(imageRaw),
            location = obj["location"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            company = obj["company"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            employeeNumber = obj["employee_num"]?.jsonPrimitive?.contentOrNull,
            jobtitle = obj["jobtitle"]?.jsonPrimitive?.contentOrNull,
            notes = obj["notes"]?.jsonPrimitive?.contentOrNull,
            activated = obj["activated"]?.jsonPrimitive?.booleanOrNull,
            groups = SnipeDecoders.decodeUserGroups(obj["groups"]),
            createdAt = SnipeDecoders.flexibleDateInfo(obj["created_at"]),
            updatedAt = SnipeDecoders.flexibleDateInfo(obj["updated_at"]),
        )
    }

    override fun serialize(encoder: Encoder, value: User) {
        val output = encoder as JsonEncoder
        val obj = buildMap {
            put("id", JsonPrimitive(value.id))
            put("name", JsonPrimitive(value.name))
            put("first_name", JsonPrimitive(value.firstName))
            value.lastName?.let { put("last_name", JsonPrimitive(it)) }
            value.username?.let { put("username", JsonPrimitive(it)) }
            value.email?.let { put("email", JsonPrimitive(it)) }
            value.phone?.let { put("phone", JsonPrimitive(it)) }
            value.image?.let { put("image", JsonPrimitive(it)) }
            value.location?.let { put("location", SnipeJson.encodeToJsonElement(it)) }
            value.company?.let { put("company", SnipeJson.encodeToJsonElement(it)) }
            value.employeeNumber?.let { put("employee_num", JsonPrimitive(it)) }
            value.jobtitle?.let { put("jobtitle", JsonPrimitive(it)) }
            value.notes?.let { put("notes", JsonPrimitive(it)) }
            value.activated?.let { put("activated", JsonPrimitive(it)) }
            if (value.groups.isNotEmpty()) {
                put("groups", SnipeJson.encodeToJsonElement(value.groups))
            }
            value.createdAt?.let { put("created_at", SnipeJson.encodeToJsonElement(it)) }
            value.updatedAt?.let { put("updated_at", SnipeJson.encodeToJsonElement(it)) }
        }
        output.encodeJsonElement(JsonObject(obj))
    }
}

// ---------------------------------------------------------------------------
// Accessory / Consumable / Component (flexible numeric + date fields)
// ---------------------------------------------------------------------------

@Serializable(with = AccessorySerializer::class)
data class Accessory(
    val id: Int,
    val name: String,
    val statusLabel: StatusLabel? = null,
    val assignedTo: AssignedTo? = null,
    val location: Location? = null,
    val manufacturer: Manufacturer? = null,
    val category: Category? = null,
    val company: Company? = null,
    val supplier: Supplier? = null,
    val qty: Int? = null,
    val minAmt: Int? = null,
    val remaining: Int? = null,
    val checkoutsCount: Int? = null,
    val orderNumber: String? = null,
    val purchaseCost: String? = null,
    val purchaseDate: String? = null,
    val modelNumber: String? = null,
    val image: String? = null,
    val notes: String? = null,
    val createdAt: DateInfo? = null,
    val updatedAt: DateInfo? = null,
) {
    val assetTag: String get() = id.toString()

    val decodedName: String get() = HtmlDecoder.decode(name)
    val decodedAssetTag: String get() = HtmlDecoder.decode(assetTag)
    val decodedAssignedToName: String get() = HtmlDecoder.decode(assignedTo?.name ?: "")
    val decodedLocationName: String get() = HtmlDecoder.decode(location?.name ?: "")
    val decodedManufacturerName: String get() = HtmlDecoder.decode(manufacturer?.name ?: "")
    val decodedCategoryName: String get() = HtmlDecoder.decode(category?.name ?: "")
    val decodedNotes: String get() = HtmlDecoder.decode(notes ?: "")
}

object AccessorySerializer : KSerializer<Accessory> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Accessory")

    override fun deserialize(decoder: Decoder): Accessory {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        return Accessory(
            id = SnipeDecoders.flexibleInt(obj["id"]) ?: 0,
            name = SnipeDecoders.flexibleStringOrNumber(obj["name"]) ?: "",
            statusLabel = SnipeDecoders.decodeOptionalObject(obj["status_label"], StatusLabel.serializer()),
            assignedTo = SnipeDecoders.decodeOptionalObject(obj["assigned_to"], AssignedTo.serializer()),
            location = SnipeDecoders.decodeOptionalObject(obj["location"], Location.serializer()),
            manufacturer = SnipeDecoders.decodeOptionalObject(obj["manufacturer"], NamedId.serializer()),
            category = SnipeDecoders.decodeOptionalObject(obj["category"], NamedId.serializer()),
            company = SnipeDecoders.decodeOptionalObject(obj["company"], NamedId.serializer()),
            supplier = SnipeDecoders.decodeOptionalObject(obj["supplier"], NamedId.serializer()),
            qty = SnipeDecoders.flexibleInt(obj["qty"]),
            minAmt = SnipeDecoders.flexibleInt(obj["min_amt"]),
            remaining = SnipeDecoders.flexibleInt(obj["remaining"]),
            checkoutsCount = SnipeDecoders.flexibleInt(obj["checkouts_count"]),
            orderNumber = SnipeDecoders.flexibleStringOrNumber(obj["order_number"]),
            purchaseCost = SnipeDecoders.flexibleStringOrNumber(obj["purchase_cost"]),
            purchaseDate = SnipeDecoders.purchaseDateString(obj["purchase_date"]),
            modelNumber = SnipeDecoders.flexibleStringOrNumber(obj["model_number"]),
            image = SnipeDecoders.flexibleStringOrNumber(obj["image"]),
            notes = SnipeDecoders.flexibleStringOrNumber(obj["notes"]),
            createdAt = SnipeDecoders.flexibleDateInfo(obj["created_at"]),
            updatedAt = SnipeDecoders.flexibleDateInfo(obj["updated_at"]),
        )
    }

    override fun serialize(encoder: Encoder, value: Accessory) {
        (encoder as JsonEncoder).encodeJsonElement(
            SnipeJson.encodeToJsonElement(
                AccessoryWire(
                    id = value.id,
                    name = value.name,
                    statusLabel = value.statusLabel,
                    assignedTo = value.assignedTo,
                    location = value.location,
                    manufacturer = value.manufacturer,
                    category = value.category,
                    company = value.company,
                    supplier = value.supplier,
                    qty = value.qty,
                    minAmt = value.minAmt,
                    remaining = value.remaining,
                    checkoutsCount = value.checkoutsCount,
                    orderNumber = value.orderNumber,
                    purchaseCost = value.purchaseCost,
                    purchaseDate = value.purchaseDate,
                    modelNumber = value.modelNumber,
                    image = value.image,
                    notes = value.notes,
                    createdAt = value.createdAt,
                    updatedAt = value.updatedAt,
                ),
            ),
        )
    }

    @Serializable
    private data class AccessoryWire(
        val id: Int,
        val name: String,
        @SerialName("status_label") val statusLabel: StatusLabel? = null,
        @SerialName("assigned_to") val assignedTo: AssignedTo? = null,
        val location: Location? = null,
        val manufacturer: Manufacturer? = null,
        val category: Category? = null,
        val company: Company? = null,
        val supplier: Supplier? = null,
        val qty: Int? = null,
        @SerialName("min_amt") val minAmt: Int? = null,
        val remaining: Int? = null,
        @SerialName("checkouts_count") val checkoutsCount: Int? = null,
        @SerialName("order_number") val orderNumber: String? = null,
        @SerialName("purchase_cost") val purchaseCost: String? = null,
        @SerialName("purchase_date") val purchaseDate: String? = null,
        @SerialName("model_number") val modelNumber: String? = null,
        val image: String? = null,
        val notes: String? = null,
        @SerialName("created_at") val createdAt: DateInfo? = null,
        @SerialName("updated_at") val updatedAt: DateInfo? = null,
    )
}

@Serializable(with = ConsumableSerializer::class)
data class Consumable(
    val id: Int,
    val name: String,
    val image: String? = null,
    val itemNo: String? = null,
    val modelNumber: String? = null,
    val category: Category? = null,
    val company: Company? = null,
    val location: Location? = null,
    val manufacturer: Manufacturer? = null,
    val supplier: Supplier? = null,
    val qty: Int? = null,
    val minAmt: Int? = null,
    val remaining: Int? = null,
    val orderNumber: String? = null,
    val purchaseCost: String? = null,
    val purchaseDate: String? = null,
    val notes: String? = null,
    val createdAt: DateInfo? = null,
    val updatedAt: DateInfo? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
    val decodedItemNo: String get() = HtmlDecoder.decode(itemNo ?: "")
    val decodedModelNumber: String get() = HtmlDecoder.decode(modelNumber ?: "")
    val decodedLocationName: String get() = HtmlDecoder.decode(location?.name ?: "")
    val decodedManufacturerName: String get() = HtmlDecoder.decode(manufacturer?.name ?: "")
    val decodedCategoryName: String get() = HtmlDecoder.decode(category?.name ?: "")
    val decodedCompanyName: String get() = HtmlDecoder.decode(company?.name ?: "")
}

object ConsumableSerializer : KSerializer<Consumable> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Consumable")

    override fun deserialize(decoder: Decoder): Consumable {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        return Consumable(
            id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
            name = obj["name"]?.jsonPrimitive?.contentOrNull ?: "",
            image = obj["image"]?.jsonPrimitive?.contentOrNull,
            itemNo = obj["item_no"]?.jsonPrimitive?.contentOrNull,
            modelNumber = obj["model_number"]?.jsonPrimitive?.contentOrNull,
            category = obj["category"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            company = obj["company"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            location = obj["location"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            manufacturer = obj["manufacturer"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            supplier = obj["supplier"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            qty = SnipeDecoders.flexibleInt(obj["qty"]),
            minAmt = SnipeDecoders.flexibleInt(obj["min_amt"]),
            remaining = SnipeDecoders.flexibleInt(obj["remaining"]),
            orderNumber = obj["order_number"]?.jsonPrimitive?.contentOrNull,
            purchaseCost = SnipeDecoders.flexibleStringOrNumber(obj["purchase_cost"]),
            purchaseDate = SnipeDecoders.purchaseDateString(obj["purchase_date"]),
            notes = obj["notes"]?.jsonPrimitive?.contentOrNull,
            createdAt = SnipeDecoders.flexibleDateInfo(obj["created_at"]),
            updatedAt = SnipeDecoders.flexibleDateInfo(obj["updated_at"]),
        )
    }

    override fun serialize(encoder: Encoder, value: Consumable) {
        (encoder as JsonEncoder).encodeJsonElement(SnipeJson.encodeToJsonElement(value.toWire()))
    }

    @Serializable
    private data class ConsumableWire(
        val id: Int,
        val name: String,
        val image: String? = null,
        @SerialName("item_no") val itemNo: String? = null,
        @SerialName("model_number") val modelNumber: String? = null,
        val category: Category? = null,
        val company: Company? = null,
        val location: Location? = null,
        val manufacturer: Manufacturer? = null,
        val supplier: Supplier? = null,
        val qty: Int? = null,
        @SerialName("min_amt") val minAmt: Int? = null,
        val remaining: Int? = null,
        @SerialName("order_number") val orderNumber: String? = null,
        @SerialName("purchase_cost") val purchaseCost: String? = null,
        @SerialName("purchase_date") val purchaseDate: String? = null,
        val notes: String? = null,
        @SerialName("created_at") val createdAt: DateInfo? = null,
        @SerialName("updated_at") val updatedAt: DateInfo? = null,
    )

    private fun Consumable.toWire() = ConsumableWire(
        id = id,
        name = name,
        image = image,
        itemNo = itemNo,
        modelNumber = modelNumber,
        category = category,
        company = company,
        location = location,
        manufacturer = manufacturer,
        supplier = supplier,
        qty = qty,
        minAmt = minAmt,
        remaining = remaining,
        orderNumber = orderNumber,
        purchaseCost = purchaseCost,
        purchaseDate = purchaseDate,
        notes = notes,
        createdAt = createdAt,
        updatedAt = updatedAt,
    )
}

@Serializable(with = ComponentSerializer::class)
data class Component(
    val id: Int,
    val name: String,
    val image: String? = null,
    val serial: String? = null,
    val modelNumber: String? = null,
    val category: Category? = null,
    val company: Company? = null,
    val location: Location? = null,
    val manufacturer: Manufacturer? = null,
    val supplier: Supplier? = null,
    val qty: Int? = null,
    val minAmt: Int? = null,
    val remaining: Int? = null,
    val orderNumber: String? = null,
    val purchaseCost: String? = null,
    val purchaseDate: String? = null,
    val notes: String? = null,
    val createdAt: DateInfo? = null,
    val updatedAt: DateInfo? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
    val decodedSerial: String get() = HtmlDecoder.decode(serial ?: "")
    val decodedModelNumber: String get() = HtmlDecoder.decode(modelNumber ?: "")
    val decodedLocationName: String get() = HtmlDecoder.decode(location?.name ?: "")
    val decodedManufacturerName: String get() = HtmlDecoder.decode(manufacturer?.name ?: "")
    val decodedCategoryName: String get() = HtmlDecoder.decode(category?.name ?: "")
    val decodedCompanyName: String get() = HtmlDecoder.decode(company?.name ?: "")
}

object ComponentSerializer : KSerializer<Component> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Component")

    override fun deserialize(decoder: Decoder): Component {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        return Component(
            id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
            name = obj["name"]?.jsonPrimitive?.contentOrNull ?: "",
            image = obj["image"]?.jsonPrimitive?.contentOrNull,
            serial = obj["serial"]?.jsonPrimitive?.contentOrNull,
            modelNumber = obj["model_number"]?.jsonPrimitive?.contentOrNull,
            category = obj["category"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            company = obj["company"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            location = obj["location"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            manufacturer = obj["manufacturer"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            supplier = obj["supplier"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            qty = SnipeDecoders.flexibleInt(obj["qty"]),
            minAmt = SnipeDecoders.flexibleInt(obj["min_amt"]),
            remaining = SnipeDecoders.flexibleInt(obj["remaining"]),
            orderNumber = obj["order_number"]?.jsonPrimitive?.contentOrNull,
            purchaseCost = SnipeDecoders.flexibleStringOrNumber(obj["purchase_cost"]),
            purchaseDate = SnipeDecoders.purchaseDateString(obj["purchase_date"]),
            notes = obj["notes"]?.jsonPrimitive?.contentOrNull,
            createdAt = SnipeDecoders.flexibleDateInfo(obj["created_at"]),
            updatedAt = SnipeDecoders.flexibleDateInfo(obj["updated_at"]),
        )
    }

    override fun serialize(encoder: Encoder, value: Component) {
        (encoder as JsonEncoder).encodeJsonElement(SnipeJson.encodeToJsonElement(value.toWire()))
    }

    @Serializable
    private data class ComponentWire(
        val id: Int,
        val name: String,
        val image: String? = null,
        val serial: String? = null,
        @SerialName("model_number") val modelNumber: String? = null,
        val category: Category? = null,
        val company: Company? = null,
        val location: Location? = null,
        val manufacturer: Manufacturer? = null,
        val supplier: Supplier? = null,
        val qty: Int? = null,
        @SerialName("min_amt") val minAmt: Int? = null,
        val remaining: Int? = null,
        @SerialName("order_number") val orderNumber: String? = null,
        @SerialName("purchase_cost") val purchaseCost: String? = null,
        @SerialName("purchase_date") val purchaseDate: String? = null,
        val notes: String? = null,
        @SerialName("created_at") val createdAt: DateInfo? = null,
        @SerialName("updated_at") val updatedAt: DateInfo? = null,
    )

    private fun Component.toWire() = ComponentWire(
        id = id,
        name = name,
        image = image,
        serial = serial,
        modelNumber = modelNumber,
        category = category,
        company = company,
        location = location,
        manufacturer = manufacturer,
        supplier = supplier,
        qty = qty,
        minAmt = minAmt,
        remaining = remaining,
        orderNumber = orderNumber,
        purchaseCost = purchaseCost,
        purchaseDate = purchaseDate,
        notes = notes,
        createdAt = createdAt,
        updatedAt = updatedAt,
    )
}

// ---------------------------------------------------------------------------
// License
// ---------------------------------------------------------------------------

@Serializable
data class License(
    val id: Int,
    val name: String = "",
    @SerialName("product_key") val productKey: String? = null,
    @SerialName("license_name") val licenseName: String? = null,
    @SerialName("license_email") val licenseEmail: String? = null,
    val serial: String? = null,
    val seats: Int? = null,
    @SerialName("free_seats_count") val freeSeatsCount: Int? = null,
    val remaining: Int? = null,
    @SerialName("min_amt") val minAmt: Int? = null,
    val reassignable: Boolean? = null,
    val maintained: Boolean? = null,
    val category: Category? = null,
    val manufacturer: Manufacturer? = null,
    val supplier: Supplier? = null,
    val company: Company? = null,
    val notes: String? = null,
    @SerialName("order_number") val orderNumber: String? = null,
    @SerialName("purchase_order") val purchaseOrder: String? = null,
    @SerialName("purchase_cost") val purchaseCost: String? = null,
    @SerialName("purchase_date") val purchaseDate: DateInfo? = null,
    @SerialName("expiration_date") val expirationDate: DateInfo? = null,
    @SerialName("termination_date") val terminationDate: DateInfo? = null,
    @SerialName("created_at") val createdAt: DateInfo? = null,
    @SerialName("updated_at") val updatedAt: DateInfo? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
    val decodedLicenseName: String get() = HtmlDecoder.decode(licenseName ?: "")
    val decodedLicenseEmail: String get() = HtmlDecoder.decode(licenseEmail ?: "")
    val decodedManufacturerName: String get() = HtmlDecoder.decode(manufacturer?.name ?: "")
    val decodedCategoryName: String get() = HtmlDecoder.decode(category?.name ?: "")
    val decodedSupplierName: String get() = HtmlDecoder.decode(supplier?.name ?: "")
    val decodedCompanyName: String get() = HtmlDecoder.decode(company?.name ?: "")
    val decodedNotes: String get() = HtmlDecoder.decode(notes ?: "")
    val decodedProductKey: String get() = HtmlDecoder.decode(productKey ?: "")
}

@Serializable
data class LicenseSeatAsset(
    val id: Int,
    val name: String? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name ?: "")
}

data class LicenseSeatAssignee(
    val user: User?,
    val name: String,
    val email: String,
    val company: String,
)

@Serializable
data class LicenseSeatRow(
    val id: Int,
    @SerialName("license_id") val licenseId: Int? = null,
    @SerialName("assigned_user") val assignedUser: AssignedTo? = null,
    @SerialName("assigned_asset") val assignedAsset: LicenseSeatAsset? = null,
    val location: Location? = null,
    @SerialName("user_can_checkin") val userCanCheckin: Boolean? = null,
    @SerialName("user_can_checkout") val userCanCheckout: Boolean? = null,
    val reassignable: Boolean? = null,
    val disabled: Boolean? = null,
) {
    fun resolvedAssignee(assets: List<Asset>, users: List<User>): LicenseSeatAssignee? {
        if (assignedAsset == null) return null

        assignedUser?.let { seatUser ->
            val cached = users.firstOrNull { it.id == seatUser.id }
            return LicenseSeatAssignee(
                user = cached,
                name = cached?.decodedName ?: HtmlDecoder.decode(seatUser.name),
                email = cached?.decodedEmail ?: HtmlDecoder.decode(seatUser.email ?: ""),
                company = cached?.decodedCompanyName ?: "",
            )
        }

        val asset = assets.firstOrNull { it.id == assignedAsset.id } ?: return null
        val assigned = asset.assignedTo ?: return null
        if (!assigned.isUser) return null

        users.firstOrNull { it.id == assigned.id }?.let { user ->
            return LicenseSeatAssignee(
                user = user,
                name = user.decodedName,
                email = user.decodedEmail,
                company = user.decodedCompanyName,
            )
        }

        val name = asset.decodedAssignedToName
        if (name.isEmpty()) return null
        return LicenseSeatAssignee(user = null, name = name, email = "", company = "")
    }
}

// ---------------------------------------------------------------------------
// Activity & files
// ---------------------------------------------------------------------------

@Serializable
data class Activity(
    val id: Int,
    @SerialName("created_at") val createdAt: DateInfo? = null,
    val item: ActivityItem? = null,
    val target: ActivityItem? = null,
    @SerialName("action_type") val actionType: String,
    val note: String? = null,
    @SerialName("log_meta") val logMeta: Map<String, LogMetaChange>? = null,
    val admin: ActivityUser? = null,
    @SerialName("created_by") val createdBy: ActivityUser? = null,
    val file: ActivityFile? = null,
) {
    val decodedNote: String get() = HtmlDecoder.decode(note ?: "")
}

@Serializable
data class ActivityItem(
    val id: Int,
    val name: String,
    val type: String,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

@Serializable
data class ActivityUser(
    val id: Int,
    val name: String,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name)
}

@Serializable
data class LogMetaChange(
    val old: String? = null,
    val new: String? = null,
)

@Serializable
data class ActivityFile(
    val url: String? = null,
    val filename: String? = null,
    val mediatype: String? = null,
    val inlineable: Boolean? = null,
    @SerialName("exists_on_disk") val existsOnDisk: Boolean? = null,
) {
    val decodedFilename: String get() = HtmlDecoder.decode(filename ?: "")

    val isImage: Boolean
        get() {
            if (mediatype?.lowercase(Locale.US)?.startsWith("image/") == true) return true
            val lower = decodedFilename.lowercase(Locale.US)
            return lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png") ||
                lower.endsWith(".gif") || lower.endsWith(".webp") || lower.endsWith(".heic")
        }

    val isPDF: Boolean
        get() {
            if (mediatype?.lowercase(Locale.US)?.contains("pdf") == true) return true
            return decodedFilename.lowercase(Locale.US).endsWith(".pdf")
        }
}

@Serializable
data class AssetFileAvailableActions(
    val delete: Boolean? = null,
)

@Serializable
data class AssetFile(
    val id: Int,
    val filename: String? = null,
    val name: String? = null,
    val filetype: String? = null,
    val mediatype: String? = null,
    val url: String? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: CreatedBy? = null,
    @SerialName("created_at") val createdAt: DateInfo? = null,
    @SerialName("available_actions") val availableActions: AssetFileAvailableActions? = null,
    @kotlinx.serialization.Transient val isAcceptance: Boolean = false,
) {
    val decodedFilename: String
        get() = HtmlDecoder.decode(filename ?: name ?: "")

    val shortFilename: String
        get() {
            val decoded = decodedFilename
            val regex = Regex("^asset-\\d+-[A-Za-z0-9]+-")
            val trimmed = decoded.replace(regex, "")
            return trimmed.ifEmpty { decoded }
        }

    val decodedNote: String get() = HtmlDecoder.decode(note ?: "")

    val canDelete: Boolean
        get() = if (isAcceptance) false else availableActions?.delete ?: true

    val isImage: Boolean
        get() {
            if (isAcceptance) return false
            if (mediatype?.lowercase(Locale.US)?.startsWith("image/") == true) return true
            val lower = decodedFilename.lowercase(Locale.US)
            return lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png") ||
                lower.endsWith(".gif") || lower.endsWith(".webp") || lower.endsWith(".heic")
        }

    val isPDF: Boolean
        get() {
            if (mediatype?.lowercase(Locale.US)?.contains("pdf") == true) return true
            return decodedFilename.lowercase(Locale.US).endsWith(".pdf")
        }
}

// ---------------------------------------------------------------------------
// Maintenance
// ---------------------------------------------------------------------------

@Serializable
data class MaintenanceAssetRef(
    val id: Int? = null,
    val name: String? = null,
    @SerialName("asset_tag") val assetTag: String? = null,
)

@Serializable(with = AssetMaintenanceSerializer::class)
data class AssetMaintenance(
    val id: Int,
    val title: String,
    @SerialName("asset_id") val assetId: Int? = null,
    @SerialName("asset_name") val assetName: String? = null,
    @SerialName("asset_tag") val assetTag: String? = null,
    @SerialName("asset_maintenance_type") val assetMaintenanceType: String? = null,
    @SerialName("maintenance_type") val maintenanceType: String? = null,
    val supplier: Supplier? = null,
    val cost: String? = null,
    val notes: String? = null,
    @SerialName("start_date") val startDate: DateInfo? = null,
    @SerialName("completion_date") val completionDate: DateInfo? = null,
    @SerialName("is_warranty") val isWarranty: Boolean = false,
    val url: String? = null,
    val image: String? = null,
    @SerialName("asset_maintenance_time") val maintenanceTime: Int? = null,
    @SerialName("created_by") val createdBy: CreatedBy? = null,
    @SerialName("responsible_party") val responsibleParty: CreatedBy? = null,
    @SerialName("completed_at") val completedAt: DateInfo? = null,
    @SerialName("created_at") val createdAt: DateInfo? = null,
    @SerialName("updated_at") val updatedAt: DateInfo? = null,
    @SerialName("completed_by") val completedBy: CreatedBy? = null,
) {
    val decodedTitle: String get() = HtmlDecoder.decode(title)
    val decodedNotes: String get() = HtmlDecoder.decode(notes ?: "")

    val isCompleted: Boolean
        get() {
            if (!completedAt?.datetime.isNullOrEmpty()) return true
            if (!completedAt?.formatted.isNullOrEmpty()) return true
            return false
        }

    val displayType: String?
        get() = assetMaintenanceType?.takeIf { it.isNotEmpty() }
            ?: maintenanceType?.takeIf { it.isNotEmpty() }

    val assetDisplayLabel: String?
        get() {
            val decodedName = assetName?.let { HtmlDecoder.decode(it) }?.takeIf { it.isNotEmpty() }
            val tag = assetTag?.takeIf { it.isNotEmpty() }
            return when {
                decodedName != null && tag != null -> "$decodedName ($tag)"
                decodedName != null -> decodedName
                tag != null -> tag
                else -> null
            }
        }
}

object AssetMaintenanceSerializer : KSerializer<AssetMaintenance> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("AssetMaintenance")

    override fun deserialize(decoder: Decoder): AssetMaintenance {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val nestedAsset = obj["asset"]?.takeUnless { it is JsonNull }?.let {
            SnipeJson.decodeFromJsonElement<MaintenanceAssetRef>(it)
        }
        return AssetMaintenance(
            id = obj["id"]?.jsonPrimitive?.intOrNull ?: 0,
            title = obj["title"]?.jsonPrimitive?.contentOrNull
                ?: obj["name"]?.jsonPrimitive?.contentOrNull
                ?: "",
            assetId = obj["asset_id"]?.jsonPrimitive?.intOrNull ?: nestedAsset?.id,
            assetName = obj["asset_name"]?.jsonPrimitive?.contentOrNull ?: nestedAsset?.name,
            assetTag = obj["asset_tag"]?.jsonPrimitive?.contentOrNull ?: nestedAsset?.assetTag,
            assetMaintenanceType = obj["asset_maintenance_type"]?.jsonPrimitive?.contentOrNull,
            maintenanceType = obj["maintenance_type"]?.jsonPrimitive?.contentOrNull,
            supplier = obj["supplier"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            cost = obj["cost"]?.jsonPrimitive?.contentOrNull,
            notes = obj["notes"]?.jsonPrimitive?.contentOrNull,
            startDate = obj["start_date"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            // 8.7+ uses expected_completion_date; older servers still send completion_date.
            completionDate = (obj["expected_completion_date"] ?: obj["completion_date"])
                ?.takeUnless { it is JsonNull }
                ?.let { SnipeJson.decodeFromJsonElement(it) },
            isWarranty = obj["is_warranty"]?.jsonPrimitive?.booleanOrNull ?: false,
            url = obj["url"]?.jsonPrimitive?.contentOrNull,
            image = obj["image"]?.jsonPrimitive?.contentOrNull,
            maintenanceTime = SnipeDecoders.flexibleInt(obj["asset_maintenance_time"]),
            createdBy = obj["created_by"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            responsibleParty = obj["responsible_party"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            completedAt = obj["completed_at"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            createdAt = obj["created_at"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            updatedAt = obj["updated_at"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
            completedBy = obj["completed_by"]?.takeUnless { it is JsonNull }?.let {
                SnipeJson.decodeFromJsonElement(it)
            },
        )
    }

    override fun serialize(encoder: Encoder, value: AssetMaintenance) {
        (encoder as JsonEncoder).encodeJsonElement(SnipeJson.encodeToJsonElement(value.toWire()))
    }

    @Serializable
    private data class AssetMaintenanceWire(
        val id: Int,
        val title: String,
        @SerialName("asset_id") val assetId: Int? = null,
        @SerialName("asset_name") val assetName: String? = null,
        @SerialName("asset_tag") val assetTag: String? = null,
        @SerialName("asset_maintenance_type") val assetMaintenanceType: String? = null,
        @SerialName("maintenance_type") val maintenanceType: String? = null,
        val supplier: Supplier? = null,
        val cost: String? = null,
        val notes: String? = null,
        @SerialName("start_date") val startDate: DateInfo? = null,
        @SerialName("completion_date") val completionDate: DateInfo? = null,
        @SerialName("is_warranty") val isWarranty: Boolean = false,
        val url: String? = null,
        val image: String? = null,
        @SerialName("asset_maintenance_time") val maintenanceTime: Int? = null,
        @SerialName("created_by") val createdBy: CreatedBy? = null,
        @SerialName("responsible_party") val responsibleParty: CreatedBy? = null,
        @SerialName("completed_at") val completedAt: DateInfo? = null,
        @SerialName("created_at") val createdAt: DateInfo? = null,
        @SerialName("updated_at") val updatedAt: DateInfo? = null,
        @SerialName("completed_by") val completedBy: CreatedBy? = null,
    )

    private fun AssetMaintenance.toWire() = AssetMaintenanceWire(
        id = id,
        title = title,
        assetId = assetId,
        assetName = assetName,
        assetTag = assetTag,
        assetMaintenanceType = assetMaintenanceType,
        maintenanceType = maintenanceType,
        supplier = supplier,
        cost = cost,
        notes = notes,
        startDate = startDate,
        completionDate = completionDate,
        isWarranty = isWarranty,
        url = url,
        image = image,
        maintenanceTime = maintenanceTime,
        createdBy = createdBy,
        responsibleParty = responsibleParty,
        completedAt = completedAt,
        createdAt = createdAt,
        updatedAt = updatedAt,
        completedBy = completedBy,
    )
}

@Serializable(with = MaintenanceUpdateRequestSerializer::class)
data class MaintenanceUpdateRequest(
    val name: String? = null,
    @SerialName("asset_maintenance_type") val assetMaintenanceType: String? = null,
    @SerialName("maintenance_type_id") val maintenanceTypeId: Int? = null,
    @SerialName("supplier_id") val supplierId: Int? = null,
    val cost: String? = null,
    val notes: String? = null,
    val url: String? = null,
    @SerialName("responsible_party_id") val responsiblePartyId: Int? = null,
    val clearResponsibleParty: Boolean = false,
    @SerialName("start_date") val startDate: String? = null,
    @SerialName("completion_date") val completionDate: String? = null,
    @SerialName("is_warranty") val isWarranty: Boolean? = null,
    @SerialName("image_delete") val imageDelete: Int? = null,
)

object MaintenanceUpdateRequestSerializer : KSerializer<MaintenanceUpdateRequest> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("MaintenanceUpdateRequest")

    override fun deserialize(decoder: Decoder): MaintenanceUpdateRequest {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val responsible = obj["responsible_party_id"]
        return MaintenanceUpdateRequest(
            name = obj["name"]?.jsonPrimitive?.contentOrNull,
            assetMaintenanceType = obj["asset_maintenance_type"]?.jsonPrimitive?.contentOrNull,
            maintenanceTypeId = SnipeDecoders.flexibleInt(obj["maintenance_type_id"]),
            supplierId = SnipeDecoders.flexibleInt(obj["supplier_id"]),
            cost = obj["cost"]?.jsonPrimitive?.contentOrNull,
            notes = obj["notes"]?.jsonPrimitive?.contentOrNull,
            url = obj["url"]?.jsonPrimitive?.contentOrNull,
            responsiblePartyId = SnipeDecoders.flexibleInt(responsible),
            clearResponsibleParty = responsible is JsonNull,
            startDate = obj["start_date"]?.jsonPrimitive?.contentOrNull,
            completionDate = obj["completion_date"]?.jsonPrimitive?.contentOrNull,
            isWarranty = obj["is_warranty"]?.jsonPrimitive?.booleanOrNull,
            imageDelete = SnipeDecoders.flexibleInt(obj["image_delete"]),
        )
    }

    override fun serialize(encoder: Encoder, value: MaintenanceUpdateRequest) {
        val output = encoder as JsonEncoder
        val obj = buildMap {
            value.name?.let { put("name", JsonPrimitive(it)) }
            value.assetMaintenanceType?.let { put("asset_maintenance_type", JsonPrimitive(it)) }
            value.maintenanceTypeId?.let { put("maintenance_type_id", JsonPrimitive(it)) }
            value.supplierId?.let { put("supplier_id", JsonPrimitive(it)) }
            value.cost?.let { put("cost", JsonPrimitive(it)) }
            value.notes?.let { put("notes", JsonPrimitive(it)) }
            value.url?.let { put("url", JsonPrimitive(it)) }
            when {
                value.clearResponsibleParty -> put("responsible_party_id", JsonNull)
                value.responsiblePartyId != null -> put("responsible_party_id", JsonPrimitive(value.responsiblePartyId))
            }
            value.startDate?.let { put("start_date", JsonPrimitive(it)) }
            value.completionDate?.let {
                // Send both keys: legacy servers + Snipe-IT 8.7+ expected_completion_date.
                put("completion_date", JsonPrimitive(it))
                put("expected_completion_date", JsonPrimitive(it))
            }
            value.isWarranty?.let { put("is_warranty", JsonPrimitive(it)) }
            value.imageDelete?.let { put("image_delete", JsonPrimitive(it)) }
        }
        output.encodeJsonElement(JsonObject(obj))
    }
}

// ---------------------------------------------------------------------------
// Checkout / detail helper rows
// ---------------------------------------------------------------------------

@Serializable
data class AssignedToCheckedOut(
    val id: Int? = null,
    val image: String? = null,
    val type: String? = null,
    val name: String? = null,
    @SerialName("first_name") val firstName: String? = null,
    @SerialName("last_name") val lastName: String? = null,
    val username: String? = null,
    val model: String? = null,
    @SerialName("asset_tag") val assetTag: String? = null,
    val serial: String? = null,
    @SerialName("created_by") val createdBy: CreatedByCheckedOut? = null,
    @SerialName("created_at") val createdAt: DateInfoCheckedOut? = null,
    @SerialName("deleted_at") val deletedAt: String? = null,
) {
    val decodedName: String get() = HtmlDecoder.decode(name ?: "")
    val decodedModel: String get() = HtmlDecoder.decode(model ?: "")
    val decodedAssetTag: String get() = HtmlDecoder.decode(assetTag ?: "")

    private val normalizedType: String
        get() {
            val raw = (type ?: "").lowercase(Locale.US)
            return when {
                raw == "user" || raw.endsWith("\\user") -> "user"
                raw == "location" || raw.endsWith("\\location") -> "location"
                raw == "asset" || raw.endsWith("\\asset") -> "asset"
                else -> raw
            }
        }

    val isUser: Boolean get() = normalizedType == "user"
    val isLocation: Boolean get() = normalizedType == "location"
    val isAsset: Boolean get() = normalizedType == "asset"

    fun matchesUser(userId: Int): Boolean {
        if (id != userId) return false
        val raw = (type ?: "").trim()
        return raw.isEmpty() || isUser
    }
}

@Serializable
data class CreatedByCheckedOut(
    val id: Int? = null,
    val name: String? = null,
)

@Serializable
data class DateInfoCheckedOut(
    val datetime: String? = null,
    val formatted: String? = null,
)

@Serializable
data class AvailableActionsCheckedOut(
    val checkin: Boolean? = null,
)

@Serializable
data class AccessoryCheckedOutRow(
    val id: Int? = null,
    @SerialName("assigned_to") val assignedTo: AssignedToCheckedOut? = null,
    val note: String? = null,
    @SerialName("created_by") val createdBy: CreatedByCheckedOut? = null,
    @SerialName("created_at") val createdAt: DateInfoCheckedOut? = null,
    @SerialName("available_actions") val availableActions: AvailableActionsCheckedOut? = null,
)

@Serializable(with = ConsumableUserRowSerializer::class)
data class ConsumableUserRow(
    val userId: Int? = null,
    val name: String? = null,
    val email: String? = null,
    val note: String? = null,
    val rowId: String = UUID.randomUUID().toString(),
)

object ConsumableUserRowSerializer : KSerializer<ConsumableUserRow> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("ConsumableUserRow")

    override fun deserialize(decoder: Decoder): ConsumableUserRow {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val userObj = obj["user"]?.takeUnless { it is JsonNull }?.jsonObject
        return ConsumableUserRow(
            userId = userObj?.get("id")?.jsonPrimitive?.intOrNull,
            name = userObj?.get("name")?.jsonPrimitive?.contentOrNull,
            email = null,
            note = obj["note"]?.jsonPrimitive?.contentOrNull,
        )
    }

    override fun serialize(encoder: Encoder, value: ConsumableUserRow) {
        val output = encoder as JsonEncoder
        val userObj = buildMap {
            value.userId?.let { put("id", JsonPrimitive(it)) }
            value.name?.let { put("name", JsonPrimitive(it)) }
        }
        val obj = buildMap {
            if (userObj.isNotEmpty()) put("user", JsonObject(userObj))
            value.note?.let { put("note", JsonPrimitive(it)) }
        }
        output.encodeJsonElement(JsonObject(obj))
    }
}

@Serializable(with = ComponentAssetRowSerializer::class)
data class ComponentAssetRow(
    val assignedPivotId: Int? = null,
    val assetId: Int? = null,
    val assetName: String? = null,
    val assetTag: String? = null,
    val assignedQty: Int? = null,
    val note: String? = null,
    val rowId: String = UUID.randomUUID().toString(),
) {
    val decodedAssetName: String get() = HtmlDecoder.decode(assetName ?: "")
    val decodedAssetTag: String get() = HtmlDecoder.decode(assetTag ?: "")
}

object ComponentAssetRowSerializer : KSerializer<ComponentAssetRow> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("ComponentAssetRow")

    override fun deserialize(decoder: Decoder): ComponentAssetRow {
        val obj = (decoder as JsonDecoder).decodeJsonElement().jsonObject
        val assetObj = obj["name"]?.takeUnless { it is JsonNull }?.jsonObject
        val assignedQty = SnipeDecoders.flexibleInt(obj["assigned_qty"])
            ?: SnipeDecoders.flexibleInt(obj["qty"])
        return ComponentAssetRow(
            assignedPivotId = SnipeDecoders.flexibleInt(obj["assigned_pivot_id"]),
            assetId = assetObj?.get("id")?.jsonPrimitive?.intOrNull,
            assetName = assetObj?.get("name")?.jsonPrimitive?.contentOrNull,
            assetTag = assetObj?.get("asset_tag")?.jsonPrimitive?.contentOrNull,
            assignedQty = assignedQty,
            note = obj["note"]?.jsonPrimitive?.contentOrNull,
        )
    }

    override fun serialize(encoder: Encoder, value: ComponentAssetRow) {
        val output = encoder as JsonEncoder
        val assetObj = buildMap {
            value.assetId?.let { put("id", JsonPrimitive(it)) }
            value.assetName?.let { put("name", JsonPrimitive(it)) }
            value.assetTag?.let { put("asset_tag", JsonPrimitive(it)) }
        }
        val obj = buildMap {
            value.assignedPivotId?.let { put("assigned_pivot_id", JsonPrimitive(it)) }
            if (assetObj.isNotEmpty()) put("name", JsonObject(assetObj))
            value.assignedQty?.let { put("assigned_qty", JsonPrimitive(it)) }
            value.note?.let { put("note", JsonPrimitive(it)) }
        }
        output.encodeJsonElement(JsonObject(obj))
    }
}

data class AssetAssignedComponent(
    val component: Component,
    val assignedQty: Int,
) {
    val id: Int get() = component.id
}

// ---------------------------------------------------------------------------
// API helpers & response wrappers
// ---------------------------------------------------------------------------

data class CreateResult(
    val success: Boolean,
    val message: String = "",
    val id: Int? = null,
)

data class WriteResult(
    val success: Boolean,
    val message: String,
)

data class ManagementWriteResult(
    val success: Boolean,
    val message: String? = null,
    val id: Int? = null,
)

enum class MaintenanceTypesMode {
    Unknown,
    Legacy,
    TypeIds,
}

@Serializable
data class PagedResponse<T>(
    val total: Int? = null,
    val rows: List<T>? = null,
)

@Serializable
data class ActivityResponse(
    val rows: List<Activity>? = null,
)

@Serializable
data class AssetFileResponse(
    val total: Int? = null,
    val rows: List<AssetFile>? = null,
)

// ---------------------------------------------------------------------------
// Local cache snapshot
// ---------------------------------------------------------------------------

@Serializable
data class SnipeDataCacheSnapshot(
    val assets: List<Asset> = emptyList(),
    val users: List<User> = emptyList(),
    val currentUser: User? = null,
    val accessories: List<Accessory> = emptyList(),
    val licenses: List<License> = emptyList(),
    val consumables: List<Consumable> = emptyList(),
    val components: List<Component> = emptyList(),
    val locations: List<Location> = emptyList(),
    val companies: List<Company> = emptyList(),
    val manufacturers: List<Manufacturer> = emptyList(),
    val suppliers: List<Supplier> = emptyList(),
    val statusLabels: List<StatusLabel> = emptyList(),
    val maintenances: List<AssetMaintenance> = emptyList(),
    val savedAt: Double = System.currentTimeMillis() / 1000.0,
)
