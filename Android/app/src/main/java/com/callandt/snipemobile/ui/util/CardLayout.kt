package com.callandt.snipemobile.ui.util

import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.Component
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.data.model.DateInfo
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.util.HtmlDecoder
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

private val layoutJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

enum class CardKind(val id: String, val titleKey: String) {
    Asset("asset", "tab_assets"),
    User("user", "tab_users"),
    Accessory("accessory", "tab_accessories"),
    License("license", "tab_licenses"),
    Consumable("consumable", "tab_consumables"),
    Component("component", "tab_components"),
    ;

    companion object {
        fun fromId(id: String): CardKind? = entries.firstOrNull { it.id == id }
    }
}

object CardFieldID {
    const val Name = "name"
    const val Model = "model"
    const val Tag = "tag"
    const val Serial = "serial"
    const val Status = "status"
    const val Location = "location"
    const val AssignedTo = "assignedTo"
    const val Email = "email"
    const val JobTitle = "jobTitle"
    const val Username = "username"
    const val Manufacturer = "manufacturer"
    const val Category = "category"
    const val Expiration = "expiration"
    const val LicensedTo = "licensedTo"
    const val LicensedEmail = "licensedEmail"
    const val Company = "company"
    const val Supplier = "supplier"
    const val DefaultLocation = "defaultLocation"
    const val Notes = "notes"
    const val PurchaseDate = "purchaseDate"
    const val PurchaseCost = "purchaseCost"
    const val OrderNumber = "orderNumber"
    const val BookValue = "bookValue"
    const val EolDate = "eolDate"
    const val WarrantyExpires = "warrantyExpires"
    const val WarrantyMonths = "warrantyMonths"
    const val LastAudit = "lastAudit"
    const val NextAudit = "nextAudit"
    const val ExpectedCheckin = "expectedCheckin"
    const val LastCheckout = "lastCheckout"
    const val LastCheckin = "lastCheckin"
    const val ModelNumber = "modelNumber"
    const val FirstName = "firstName"
    const val LastName = "lastName"
    const val Phone = "phone"
    const val EmployeeNumber = "employeeNumber"
    const val Groups = "groups"
    const val ItemNo = "itemNo"
    const val Reassignable = "reassignable"
    const val Maintained = "maintained"
    const val ProductKey = "productKey"
    const val None = ""
}

@Serializable
data class CardSlotLayout(
    val title: String,
    val subtitle: String? = null,
    val details: List<String>? = null,
    val meta: List<String>? = null,
    val icons: Map<String, String>? = null,
) {
    val isLegacy: Boolean get() = details == null && meta == null

    fun resolved(spec: CardKindSpec): CardSlotLayout {
        val filled = if (!isLegacy) {
            copy(details = details ?: emptyList(), meta = meta ?: emptyList(), icons = icons)
        } else {
            val used = linkedSetOf(title)
            val detailIDs = mutableListOf<String>()
            if (!subtitle.isNullOrEmpty()) {
                detailIDs += subtitle
                used += subtitle
            }
            spec.defaultSubtitle?.takeIf { it !in used }?.let {
                detailIDs += it
                used += it
            }
            for (id in spec.headerFields) {
                if (id in used) continue
                detailIDs += id
                used += id
            }
            val metaIDs = mutableListOf<String>()
            if (spec.defaultTitle !in used) {
                metaIDs += spec.defaultTitle
                used += spec.defaultTitle
            }
            for (id in spec.metaFields) {
                if (id in used) continue
                metaIDs += id
            }
            copy(details = detailIDs, meta = metaIDs, icons = icons)
        }
        return filled.foldingSubtitleIntoDetails()
    }

    private fun foldingSubtitleIntoDetails(): CardSlotLayout {
        val subtitleId = subtitle?.takeIf { it.isNotEmpty() } ?: return copy(subtitle = null, details = details ?: emptyList())
        val remaining = (details ?: emptyList()).filter { it != subtitleId }
        val detailIDs = if (subtitleId != title) listOf(subtitleId) + remaining else remaining
        return copy(subtitle = null, details = detailIDs)
    }

    fun matchesDefault(spec: CardKindSpec): Boolean {
        val current = resolved(spec)
        val expected = spec.defaultLayout
        val iconsMatch = current.icons.isNullOrEmpty() ||
            current.icons.all { it.value == CardKindSpec.icon(it.key) }
        return current.title == expected.title &&
            current.details == expected.details &&
            current.meta == expected.meta &&
            iconsMatch
    }

    fun unusedFields(spec: CardKindSpec): List<String> {
        val used = buildSet {
            add(title)
            subtitle?.takeIf { it.isNotEmpty() }?.let { add(it) }
            details.orEmpty().forEach { add(it) }
            meta.orEmpty().forEach { add(it) }
        }
        return spec.fields.filter { it !in used }
    }

    fun removing(id: String): CardSlotLayout = copy(
        subtitle = subtitle.takeUnless { it == id },
        details = details.orEmpty().filter { it != id },
        meta = meta.orEmpty().filter { it != id },
    )

    fun placingTitle(id: String): CardSlotLayout = moving(id, FieldOccupancy.Title)

    fun placingSubtitle(id: String?): CardSlotLayout {
        return if (id.isNullOrEmpty()) copy(subtitle = null)
        else removing(id).copy(subtitle = id)
    }

    fun replacingDetail(index: Int, id: String): CardSlotLayout = moving(id, FieldOccupancy.Detail(index))

    fun replacingMeta(index: Int, id: String): CardSlotLayout = moving(id, FieldOccupancy.Meta(index))

    private fun occupancyOf(id: String): FieldOccupancy? = when {
        title == id -> FieldOccupancy.Title
        else -> details?.indexOf(id)?.takeIf { it >= 0 }?.let { FieldOccupancy.Detail(it) }
            ?: meta?.indexOf(id)?.takeIf { it >= 0 }?.let { FieldOccupancy.Meta(it) }
    }

    private fun setting(id: String, slot: FieldOccupancy): CardSlotLayout = when (slot) {
        FieldOccupancy.Title -> copy(title = id)
        is FieldOccupancy.Detail -> {
            val items = details.orEmpty().toMutableList()
            if (slot.index in items.indices) items[slot.index] = id
            copy(details = items)
        }
        is FieldOccupancy.Meta -> {
            val items = meta.orEmpty().toMutableList()
            if (slot.index in items.indices) items[slot.index] = id
            copy(meta = items)
        }
    }

    private fun moving(id: String, dest: FieldOccupancy): CardSlotLayout {
        val displaced = when (dest) {
            FieldOccupancy.Title -> title
            is FieldOccupancy.Detail -> details.orEmpty().getOrNull(dest.index).orEmpty()
            is FieldOccupancy.Meta -> meta.orEmpty().getOrNull(dest.index).orEmpty()
        }
        if (displaced == id) return this
        val origin = occupancyOf(id)
        var next = setting(id, dest)
        if (origin != null && displaced.isNotEmpty()) {
            next = next.setting(displaced, origin)
        }
        return next
    }

    fun appendingDetail(id: String): CardSlotLayout {
        val next = removing(id)
        val items = next.details.orEmpty()
        if (items.size >= CardKindSpec.MaxDetailLines) return this
        return next.copy(details = items + id)
    }

    fun appendingMeta(id: String): CardSlotLayout {
        val next = removing(id)
        return next.copy(meta = next.meta.orEmpty() + id)
    }

    fun removingDetail(index: Int): CardSlotLayout {
        val items = details.orEmpty().toMutableList()
        if (index in items.indices) items.removeAt(index)
        return copy(details = items)
    }

    fun removingMeta(index: Int): CardSlotLayout {
        val items = meta.orEmpty().toMutableList()
        if (index in items.indices) items.removeAt(index)
        return copy(meta = items)
    }

    fun icon(fieldId: String): String = icons?.get(fieldId) ?: CardKindSpec.icon(fieldId)

    fun settingIcon(icon: String, fieldId: String): CardSlotLayout {
        val map = (icons ?: emptyMap()).toMutableMap()
        if (icon == CardKindSpec.icon(fieldId)) {
            map.remove(fieldId)
        } else {
            map[fieldId] = icon
        }
        return copy(icons = map.takeIf { it.isNotEmpty() })
    }
}

private sealed class FieldOccupancy {
    data object Title : FieldOccupancy()
    data class Detail(val index: Int) : FieldOccupancy()
    data class Meta(val index: Int) : FieldOccupancy()
}

object CardIcons {
    val all = listOf(
        "tag", "barcode", "model", "serial", "status", "location",
        "person", "email", "job", "username", "manufacturer",
        "category", "calendar", "info", "number", "pin", "phone",
    )

    fun labelKey(id: String): String = when (id) {
        "tag" -> "name"
        "barcode" -> "asset_tag"
        "model" -> "model"
        "serial" -> "serial"
        "status" -> "status"
        "location" -> "location"
        "person" -> "assigned_to"
        "email" -> "email"
        "job" -> "job_title"
        "username" -> "username"
        "manufacturer" -> "manufacturer"
        "category" -> "category"
        "calendar" -> "expiration_date"
        "info" -> "card_icon_info"
        "number" -> "card_icon_number"
        "pin" -> "card_icon_pin"
        "phone" -> "phone"
        else -> id
    }
}

data class CardFieldContent(
    val id: String,
    val raw: String,
    val formatted: String? = null,
    val icon: String = "info",
)

data class ResolvedCardMeta(
    val icon: String,
    val text: String,
)

data class ResolvedCardLayout(
    val title: String,
    val subtitle: String?,
    val headerLines: List<String>,
    val meta: List<ResolvedCardMeta>,
)

data class CardKindSpec(
    val kind: CardKind,
    val fields: List<String>,
    val defaultTitle: String,
    val defaultSubtitle: String?,
    val headerFields: List<String>,
    val metaFields: List<String>,
    val titleFallbacks: List<String>,
) {
    val defaultLayout: CardSlotLayout
        get() {
            val detailIDs = buildList {
                defaultSubtitle?.takeIf { it.isNotEmpty() && it !in headerFields }?.let { add(it) }
                addAll(headerFields)
            }.take(MaxDetailLines)
            return CardSlotLayout(
                title = defaultTitle,
                subtitle = null,
                details = detailIDs,
                meta = metaFields,
            )
        }

    companion object {
        const val MaxDetailLines = 3

        fun spec(kind: CardKind): CardKindSpec = when (kind) {
            CardKind.Asset -> CardKindSpec(
                kind = CardKind.Asset,
                fields = listOf(
                    CardFieldID.Model, CardFieldID.Name, CardFieldID.Tag, CardFieldID.Serial, CardFieldID.Status,
                    CardFieldID.Location, CardFieldID.DefaultLocation, CardFieldID.AssignedTo, CardFieldID.Manufacturer,
                    CardFieldID.Category, CardFieldID.Supplier, CardFieldID.Company, CardFieldID.ModelNumber,
                    CardFieldID.PurchaseDate, CardFieldID.PurchaseCost, CardFieldID.OrderNumber, CardFieldID.BookValue,
                    CardFieldID.EolDate, CardFieldID.WarrantyExpires, CardFieldID.WarrantyMonths,
                    CardFieldID.LastAudit, CardFieldID.NextAudit, CardFieldID.ExpectedCheckin,
                    CardFieldID.LastCheckout, CardFieldID.LastCheckin, CardFieldID.Notes,
                ),
                defaultTitle = CardFieldID.Model,
                defaultSubtitle = CardFieldID.Tag,
                headerFields = listOf(CardFieldID.Serial, CardFieldID.Status),
                metaFields = listOf(CardFieldID.Name, CardFieldID.Location),
                titleFallbacks = listOf(CardFieldID.Model, CardFieldID.Name, CardFieldID.Tag),
            )
            CardKind.User -> CardKindSpec(
                kind = CardKind.User,
                fields = listOf(
                    CardFieldID.Name, CardFieldID.FirstName, CardFieldID.LastName, CardFieldID.Username,
                    CardFieldID.Email, CardFieldID.Phone, CardFieldID.JobTitle, CardFieldID.EmployeeNumber,
                    CardFieldID.Company, CardFieldID.Location, CardFieldID.Status, CardFieldID.Groups, CardFieldID.Notes,
                ),
                defaultTitle = CardFieldID.Name,
                defaultSubtitle = CardFieldID.Email,
                headerFields = emptyList(),
                metaFields = listOf(CardFieldID.JobTitle, CardFieldID.Location),
                titleFallbacks = listOf(CardFieldID.Name, CardFieldID.Username, CardFieldID.Email),
            )
            CardKind.Accessory -> CardKindSpec(
                kind = CardKind.Accessory,
                fields = listOf(
                    CardFieldID.Name, CardFieldID.Tag, CardFieldID.ModelNumber, CardFieldID.Status,
                    CardFieldID.Manufacturer, CardFieldID.Category, CardFieldID.Supplier, CardFieldID.Company,
                    CardFieldID.AssignedTo, CardFieldID.Location, CardFieldID.PurchaseDate, CardFieldID.PurchaseCost,
                    CardFieldID.OrderNumber, CardFieldID.Notes,
                ),
                defaultTitle = CardFieldID.Name,
                defaultSubtitle = CardFieldID.Tag,
                headerFields = listOf(CardFieldID.Manufacturer),
                metaFields = listOf(CardFieldID.AssignedTo, CardFieldID.Location),
                titleFallbacks = listOf(CardFieldID.Name, CardFieldID.Tag),
            )
            CardKind.License -> CardKindSpec(
                kind = CardKind.License,
                fields = listOf(
                    CardFieldID.Name, CardFieldID.Manufacturer, CardFieldID.Category, CardFieldID.ProductKey,
                    CardFieldID.Expiration, CardFieldID.LicensedTo, CardFieldID.LicensedEmail, CardFieldID.PurchaseDate,
                    CardFieldID.PurchaseCost, CardFieldID.OrderNumber, CardFieldID.Supplier, CardFieldID.Company,
                    CardFieldID.Reassignable, CardFieldID.Maintained, CardFieldID.Notes,
                ),
                defaultTitle = CardFieldID.Name,
                defaultSubtitle = CardFieldID.Manufacturer,
                headerFields = listOf(CardFieldID.Expiration),
                metaFields = listOf(CardFieldID.LicensedTo, CardFieldID.LicensedEmail),
                titleFallbacks = listOf(CardFieldID.Name, CardFieldID.LicensedTo),
            )
            CardKind.Consumable -> CardKindSpec(
                kind = CardKind.Consumable,
                fields = listOf(
                    CardFieldID.Name, CardFieldID.ItemNo, CardFieldID.ModelNumber, CardFieldID.Category,
                    CardFieldID.Manufacturer, CardFieldID.Supplier, CardFieldID.Company, CardFieldID.Location,
                    CardFieldID.PurchaseDate, CardFieldID.PurchaseCost, CardFieldID.OrderNumber, CardFieldID.Notes,
                ),
                defaultTitle = CardFieldID.Name,
                defaultSubtitle = CardFieldID.Category,
                headerFields = listOf(CardFieldID.Manufacturer),
                metaFields = listOf(CardFieldID.Location),
                titleFallbacks = listOf(CardFieldID.Name),
            )
            CardKind.Component -> CardKindSpec(
                kind = CardKind.Component,
                fields = listOf(
                    CardFieldID.Name, CardFieldID.Serial, CardFieldID.ModelNumber, CardFieldID.Category,
                    CardFieldID.Manufacturer, CardFieldID.Supplier, CardFieldID.Company, CardFieldID.Location,
                    CardFieldID.PurchaseDate, CardFieldID.PurchaseCost, CardFieldID.OrderNumber, CardFieldID.Notes,
                ),
                defaultTitle = CardFieldID.Name,
                defaultSubtitle = CardFieldID.Category,
                headerFields = listOf(CardFieldID.Manufacturer),
                metaFields = listOf(CardFieldID.Location),
                titleFallbacks = listOf(CardFieldID.Name),
            )
        }

        fun labelKey(fieldId: String): String = when (fieldId) {
            CardFieldID.Name -> "name"
            CardFieldID.Model -> "model"
            CardFieldID.Tag -> "asset_tag"
            CardFieldID.Serial -> "serial"
            CardFieldID.Status -> "status"
            CardFieldID.Location -> "location"
            CardFieldID.AssignedTo -> "assigned_to"
            CardFieldID.Email, CardFieldID.LicensedEmail -> "email"
            CardFieldID.JobTitle -> "job_title"
            CardFieldID.Username -> "username"
            CardFieldID.Manufacturer -> "manufacturer"
            CardFieldID.Category -> "category"
            CardFieldID.Expiration -> "expiration_date"
            CardFieldID.LicensedTo -> "licensed_to"
            CardFieldID.Company -> "company"
            CardFieldID.Supplier -> "supplier"
            CardFieldID.DefaultLocation -> "default_location"
            CardFieldID.Notes -> "notes"
            CardFieldID.PurchaseDate -> "purchase_date"
            CardFieldID.PurchaseCost -> "purchase_cost"
            CardFieldID.OrderNumber -> "order_number"
            CardFieldID.BookValue -> "book_value"
            CardFieldID.EolDate -> "eol_date"
            CardFieldID.WarrantyExpires -> "warranty_expires"
            CardFieldID.WarrantyMonths -> "warranty_months"
            CardFieldID.LastAudit -> "last_audit_date"
            CardFieldID.NextAudit -> "next_audit_date"
            CardFieldID.ExpectedCheckin -> "expected_checkin"
            CardFieldID.LastCheckout -> "last_checkout"
            CardFieldID.LastCheckin -> "last_checkin"
            CardFieldID.ModelNumber -> "model_number"
            CardFieldID.FirstName -> "first_name"
            CardFieldID.LastName -> "last_name"
            CardFieldID.Phone -> "phone"
            CardFieldID.EmployeeNumber -> "employee_number"
            CardFieldID.Groups -> "groups"
            CardFieldID.ItemNo -> "item_no"
            CardFieldID.Reassignable -> "reassignable"
            CardFieldID.Maintained -> "maintained"
            CardFieldID.ProductKey -> "product_key"
            else -> fieldId
        }

        fun icon(fieldId: String): String = when (fieldId) {
            CardFieldID.Name -> "tag"
            CardFieldID.Model -> "model"
            CardFieldID.Tag -> "barcode"
            CardFieldID.Serial -> "serial"
            CardFieldID.Status -> "status"
            CardFieldID.Location -> "location"
            CardFieldID.AssignedTo, CardFieldID.LicensedTo -> "person"
            CardFieldID.Email, CardFieldID.LicensedEmail -> "email"
            CardFieldID.JobTitle -> "job"
            CardFieldID.Username -> "username"
            CardFieldID.Manufacturer -> "manufacturer"
            CardFieldID.Category -> "category"
            CardFieldID.Expiration -> "calendar"
            CardFieldID.Company, CardFieldID.Supplier -> "manufacturer"
            CardFieldID.DefaultLocation -> "location"
            CardFieldID.Notes -> "info"
            CardFieldID.PurchaseDate, CardFieldID.EolDate, CardFieldID.WarrantyExpires,
            CardFieldID.LastAudit, CardFieldID.NextAudit, CardFieldID.ExpectedCheckin,
            CardFieldID.LastCheckout, CardFieldID.LastCheckin -> "calendar"
            CardFieldID.PurchaseCost, CardFieldID.BookValue, CardFieldID.OrderNumber,
            CardFieldID.WarrantyMonths, CardFieldID.EmployeeNumber -> "number"
            CardFieldID.ModelNumber, CardFieldID.ItemNo, CardFieldID.ProductKey -> "serial"
            CardFieldID.FirstName, CardFieldID.LastName, CardFieldID.Groups -> "person"
            CardFieldID.Phone -> "phone"
            CardFieldID.Reassignable, CardFieldID.Maintained -> "status"
            else -> "info"
        }
    }
}

object CardLayoutResolver {
    fun resolve(
        kind: CardKind,
        layout: CardSlotLayout,
        fields: List<CardFieldContent>,
    ): ResolvedCardLayout {
        val spec = CardKindSpec.spec(kind)
        val byId = fields.associateBy { it.id }

        fun raw(id: String) = byId[id]?.raw?.trim().orEmpty()
        fun display(id: String): String {
            val formatted = byId[id]?.formatted?.trim().orEmpty()
            return formatted.ifEmpty { raw(id) }
        }
        fun icon(id: String) = layout.icons?.get(id) ?: byId[id]?.icon ?: CardKindSpec.icon(id)

        var titleId = layout.title
        var titleText = raw(titleId)
        if (titleText.isEmpty()) {
            for (id in spec.titleFallbacks + spec.fields) {
                val candidate = raw(id)
                if (candidate.isNotEmpty()) {
                    titleId = id
                    titleText = candidate
                    break
                }
            }
        }

        val used = linkedSetOf<String>()
        if (titleText.isNotEmpty()) used += titleId

        val explicit = !layout.isLegacy
        val detailIds = buildList {
            if (explicit) {
                addAll(layout.details.orEmpty())
            } else {
                spec.defaultSubtitle?.takeIf { it !in used }?.let { add(it) }
                spec.headerFields.filter { it !in used && it !in this@buildList }.forEach { add(it) }
            }
            val subtitleId = layout.subtitle
            if (!subtitleId.isNullOrEmpty() && subtitleId != titleId && subtitleId !in this) {
                add(0, subtitleId)
            }
        }
        val metaIds = if (explicit) {
            layout.meta.orEmpty()
        } else {
            buildList {
                if (spec.defaultTitle !in used) add(spec.defaultTitle)
                spec.metaFields.filter { it !in used && it !in this@buildList }.forEach { add(it) }
            }
        }

        val headerLines = mutableListOf<String>()
        for (id in detailIds) {
            if (id in used) continue
            val text = display(id)
            if (text.isNotEmpty() && text != titleText) {
                headerLines += text
                used += id
            }
        }

        val meta = mutableListOf<ResolvedCardMeta>()
        for (id in metaIds) {
            if (id in used) continue
            val text = display(id)
            if (text.isNotEmpty() && text != titleText) {
                meta += ResolvedCardMeta(icon(id), text)
                used += id
            }
        }

        return ResolvedCardLayout(
            title = titleText,
            subtitle = null,
            headerLines = headerLines,
            meta = meta,
        )
    }
}

data class CardLayoutStore(
    val layouts: Map<String, CardSlotLayout> = emptyMap(),
) {
    fun layout(kind: CardKind): CardSlotLayout =
        layouts[kind.id] ?: CardKindSpec.spec(kind).defaultLayout

    fun replacing(kind: CardKind, layout: CardSlotLayout): CardLayoutStore {
        val next = layouts.toMutableMap()
        if (layout.matchesDefault(CardKindSpec.spec(kind))) {
            next.remove(kind.id)
        } else {
            next[kind.id] = layout
        }
        return CardLayoutStore(next)
    }

    fun encodeJson(): String {
        if (layouts.isEmpty()) return ""
        return runCatching { layoutJson.encodeToString(layouts) }.getOrDefault("")
    }

    companion object {
        val Empty = CardLayoutStore()

        fun decode(json: String, preferAssetNameInLists: Boolean = false): CardLayoutStore {
            val parsed = if (json.isBlank()) {
                emptyMap()
            } else {
                runCatching { layoutJson.decodeFromString<Map<String, CardSlotLayout>>(json) }.getOrDefault(emptyMap())
            }.toMutableMap()
            if (!parsed.containsKey(CardKind.Asset.id) && preferAssetNameInLists) {
                parsed[CardKind.Asset.id] = CardSlotLayout(title = CardFieldID.Name, subtitle = CardFieldID.Tag)
            }
            return CardLayoutStore(parsed)
        }
    }
}

fun resolveCard(
    kind: CardKind,
    layouts: CardLayoutStore,
    fields: List<CardFieldContent>,
): ResolvedCardLayout = CardLayoutResolver.resolve(kind, layouts.layout(kind), fields)

private fun cardValue(id: String, raw: String, formatted: String? = null) =
    CardFieldContent(id, raw, formatted, CardKindSpec.icon(id))

private fun labeledField(id: String, raw: String): CardFieldContent {
    val trimmed = raw.trim()
    return cardValue(
        id,
        raw,
        formatted = trimmed.takeIf { it.isNotEmpty() }?.let { "${L10n.string(CardKindSpec.labelKey(id))}: $it" },
    )
}

private fun dateField(id: String, info: DateInfo?): CardFieldContent {
    val raw = info?.localizedDisplay(includeTime = false).orEmpty().ifEmpty { info?.formatted.orEmpty() }
    return labeledField(id, raw)
}

private fun yesNoField(id: String, value: Boolean?): CardFieldContent {
    if (value == null) return cardValue(id, "")
    return labeledField(id, L10n.string(if (value) "yes" else "no"))
}

fun assetCardFields(
    asset: Asset,
    locationName: String? = null,
    status: String? = null,
): List<CardFieldContent> = listOf(
    cardValue(CardFieldID.Model, asset.decodedModelName),
    cardValue(CardFieldID.Name, asset.decodedName),
    cardValue(
        CardFieldID.Tag,
        asset.decodedAssetTag,
        formatted = asset.decodedAssetTag.takeIf { it.isNotEmpty() }?.let { L10n.string("tag_label", it) },
    ),
    cardValue(
        CardFieldID.Serial,
        asset.decodedSerial,
        formatted = asset.decodedSerial.takeIf { it.isNotEmpty() }?.let { "${L10n.string("sn_label")} $it" },
    ),
    cardValue(CardFieldID.Status, status.orEmpty()),
    cardValue(CardFieldID.Location, locationName.orEmpty()),
    labeledField(CardFieldID.DefaultLocation, HtmlDecoder.decode(asset.rtdLocation?.name ?: "")),
    cardValue(CardFieldID.AssignedTo, asset.decodedAssignedToName),
    cardValue(CardFieldID.Manufacturer, asset.decodedManufacturerName),
    cardValue(CardFieldID.Category, asset.decodedCategoryName),
    cardValue(CardFieldID.Supplier, asset.decodedSupplierName),
    cardValue(CardFieldID.Company, asset.decodedCompanyName),
    labeledField(CardFieldID.ModelNumber, asset.modelNumber.orEmpty()),
    dateField(CardFieldID.PurchaseDate, asset.purchaseDate),
    labeledField(CardFieldID.PurchaseCost, asset.purchaseCost.orEmpty()),
    labeledField(CardFieldID.OrderNumber, asset.orderNumber.orEmpty()),
    labeledField(CardFieldID.BookValue, asset.bookValue.orEmpty()),
    dateField(CardFieldID.EolDate, asset.assetEolDate),
    dateField(CardFieldID.WarrantyExpires, asset.warrantyExpires),
    labeledField(CardFieldID.WarrantyMonths, asset.decodedWarrantyMonths),
    dateField(CardFieldID.LastAudit, asset.lastAuditDate),
    dateField(CardFieldID.NextAudit, asset.nextAuditDate),
    dateField(CardFieldID.ExpectedCheckin, asset.expectedCheckin),
    dateField(CardFieldID.LastCheckout, asset.lastCheckout),
    dateField(CardFieldID.LastCheckin, asset.lastCheckin),
    labeledField(CardFieldID.Notes, asset.decodedNotes),
)

fun userCardFields(user: User): List<CardFieldContent> = listOf(
    cardValue(CardFieldID.Name, user.decodedName),
    cardValue(CardFieldID.FirstName, user.decodedFirstName),
    cardValue(CardFieldID.LastName, user.decodedLastName),
    cardValue(CardFieldID.Username, user.decodedUsername),
    cardValue(CardFieldID.Email, user.decodedEmail),
    labeledField(CardFieldID.Phone, user.decodedPhone),
    cardValue(CardFieldID.JobTitle, user.decodedJobtitle),
    labeledField(CardFieldID.EmployeeNumber, user.decodedEmployeeNumber),
    cardValue(CardFieldID.Company, user.decodedCompanyName),
    cardValue(CardFieldID.Location, user.decodedLocationName),
    cardValue(
        CardFieldID.Status,
        user.activated?.let { L10n.string(if (it) "activated" else "deactivated") }.orEmpty(),
    ),
    labeledField(CardFieldID.Groups, user.groups.map { it.decodedName }.filter { it.isNotEmpty() }.joinToString(", ")),
    labeledField(CardFieldID.Notes, user.decodedNotes),
)

fun accessoryCardFields(accessory: Accessory): List<CardFieldContent> = listOf(
    cardValue(CardFieldID.Name, accessory.decodedName),
    cardValue(
        CardFieldID.Tag,
        accessory.decodedAssetTag,
        formatted = accessory.decodedAssetTag.takeIf { it.isNotEmpty() }?.let { L10n.string("tag_label", it) },
    ),
    labeledField(CardFieldID.ModelNumber, accessory.modelNumber.orEmpty()),
    cardValue(CardFieldID.Status, HtmlDecoder.decode(accessory.statusLabel?.name ?: "")),
    cardValue(CardFieldID.Manufacturer, accessory.decodedManufacturerName),
    cardValue(CardFieldID.Category, accessory.decodedCategoryName),
    cardValue(CardFieldID.Supplier, HtmlDecoder.decode(accessory.supplier?.name ?: "")),
    cardValue(CardFieldID.Company, HtmlDecoder.decode(accessory.company?.name ?: "")),
    cardValue(CardFieldID.AssignedTo, accessory.decodedAssignedToName),
    cardValue(CardFieldID.Location, accessory.decodedLocationName),
    labeledField(CardFieldID.PurchaseDate, formatPurchaseDate(accessory.purchaseDate).orEmpty()),
    labeledField(CardFieldID.PurchaseCost, accessory.purchaseCost.orEmpty()),
    labeledField(CardFieldID.OrderNumber, accessory.orderNumber.orEmpty()),
    labeledField(CardFieldID.Notes, accessory.decodedNotes),
)

fun licenseCardFields(license: License): List<CardFieldContent> {
    val expiration = license.expirationDate?.localizedDisplay().orEmpty()
        .ifEmpty { license.expirationDate?.formatted.orEmpty() }
    return listOf(
        cardValue(CardFieldID.Name, license.decodedName),
        cardValue(CardFieldID.Manufacturer, license.decodedManufacturerName),
        cardValue(CardFieldID.Category, license.decodedCategoryName),
        labeledField(CardFieldID.ProductKey, license.decodedProductKey),
        cardValue(
            CardFieldID.Expiration,
            expiration,
            formatted = expiration.takeIf { it.isNotEmpty() }?.let { L10n.string("expires_value", it) },
        ),
        cardValue(CardFieldID.LicensedTo, license.decodedLicenseName),
        cardValue(CardFieldID.LicensedEmail, license.decodedLicenseEmail),
        dateField(CardFieldID.PurchaseDate, license.purchaseDate),
        labeledField(CardFieldID.PurchaseCost, license.purchaseCost.orEmpty()),
        labeledField(CardFieldID.OrderNumber, license.orderNumber.orEmpty()),
        cardValue(CardFieldID.Supplier, license.decodedSupplierName),
        cardValue(CardFieldID.Company, license.decodedCompanyName),
        yesNoField(CardFieldID.Reassignable, license.reassignable),
        yesNoField(CardFieldID.Maintained, license.maintained),
        labeledField(CardFieldID.Notes, license.decodedNotes),
    )
}

fun consumableCardFields(item: Consumable): List<CardFieldContent> = listOf(
    cardValue(CardFieldID.Name, item.decodedName),
    labeledField(CardFieldID.ItemNo, item.decodedItemNo),
    labeledField(CardFieldID.ModelNumber, item.decodedModelNumber),
    cardValue(CardFieldID.Category, item.decodedCategoryName),
    cardValue(CardFieldID.Manufacturer, item.decodedManufacturerName),
    cardValue(CardFieldID.Supplier, HtmlDecoder.decode(item.supplier?.name ?: "")),
    cardValue(CardFieldID.Company, item.decodedCompanyName),
    cardValue(CardFieldID.Location, item.decodedLocationName),
    labeledField(CardFieldID.PurchaseDate, formatPurchaseDate(item.purchaseDate).orEmpty()),
    labeledField(CardFieldID.PurchaseCost, item.purchaseCost.orEmpty()),
    labeledField(CardFieldID.OrderNumber, item.orderNumber.orEmpty()),
    labeledField(CardFieldID.Notes, HtmlDecoder.decode(item.notes ?: "")),
)

fun componentCardFields(item: Component): List<CardFieldContent> = listOf(
    cardValue(CardFieldID.Name, item.decodedName),
    labeledField(CardFieldID.Serial, item.decodedSerial),
    labeledField(CardFieldID.ModelNumber, item.decodedModelNumber),
    cardValue(CardFieldID.Category, item.decodedCategoryName),
    cardValue(CardFieldID.Manufacturer, item.decodedManufacturerName),
    cardValue(CardFieldID.Supplier, HtmlDecoder.decode(item.supplier?.name ?: "")),
    cardValue(CardFieldID.Company, item.decodedCompanyName),
    cardValue(CardFieldID.Location, item.decodedLocationName),
    labeledField(CardFieldID.PurchaseDate, formatPurchaseDate(item.purchaseDate).orEmpty()),
    labeledField(CardFieldID.PurchaseCost, item.purchaseCost.orEmpty()),
    labeledField(CardFieldID.OrderNumber, item.orderNumber.orEmpty()),
    labeledField(CardFieldID.Notes, HtmlDecoder.decode(item.notes ?: "")),
)

object CardLayoutPreview {
    fun fields(kind: CardKind): List<CardFieldContent> = when (kind) {
        CardKind.Asset -> listOf(
            cardValue(CardFieldID.Model, "MacBook Pro"),
            cardValue(CardFieldID.Name, "MacBook Pro 16\""),
            cardValue(CardFieldID.Tag, "MBP-1042", L10n.string("tag_label", "MBP-1042")),
            cardValue(CardFieldID.Serial, "C02YV1ABJGH6", "${L10n.string("sn_label")} C02YV1ABJGH6"),
            cardValue(CardFieldID.Status, L10n.string("status_ready_to_deploy")),
            cardValue(CardFieldID.Location, "Brussels"),
            labeledField(CardFieldID.DefaultLocation, "Brussels"),
            cardValue(CardFieldID.AssignedTo, "John Doe"),
            cardValue(CardFieldID.Manufacturer, "Apple"),
            cardValue(CardFieldID.Category, "Laptops"),
            cardValue(CardFieldID.Supplier, "Amazon"),
            cardValue(CardFieldID.Company, "Acme"),
            labeledField(CardFieldID.ModelNumber, "A2991"),
            labeledField(CardFieldID.PurchaseDate, "12 Jan 2024"),
            labeledField(CardFieldID.PurchaseCost, "2.499"),
            labeledField(CardFieldID.OrderNumber, "PO-1042"),
            labeledField(CardFieldID.BookValue, "1.890"),
            labeledField(CardFieldID.EolDate, "12 Jan 2028"),
            labeledField(CardFieldID.WarrantyExpires, "12 Jan 2027"),
            labeledField(CardFieldID.WarrantyMonths, "36"),
            labeledField(CardFieldID.LastAudit, "1 Sep 2026"),
            labeledField(CardFieldID.NextAudit, "1 Sep 2027"),
            labeledField(CardFieldID.ExpectedCheckin, "30 Sep 2026"),
            labeledField(CardFieldID.LastCheckout, "1 Mar 2026"),
            labeledField(CardFieldID.LastCheckin, "12 Feb 2026"),
            labeledField(CardFieldID.Notes, "Company laptop"),
        )
        CardKind.User -> listOf(
            cardValue(CardFieldID.Name, "John Doe"),
            cardValue(CardFieldID.FirstName, "John"),
            cardValue(CardFieldID.LastName, "Doe"),
            cardValue(CardFieldID.Email, "john.doe@example.com"),
            cardValue(CardFieldID.Username, "jdoe"),
            labeledField(CardFieldID.Phone, "+31 6 1234 5678"),
            cardValue(CardFieldID.JobTitle, "Designer"),
            labeledField(CardFieldID.EmployeeNumber, "E-204"),
            cardValue(CardFieldID.Company, "Acme"),
            cardValue(CardFieldID.Location, "Brussels"),
            cardValue(CardFieldID.Status, L10n.string("activated")),
            labeledField(CardFieldID.Groups, "Design"),
            labeledField(CardFieldID.Notes, "MacBook assigned"),
        )
        CardKind.Accessory -> listOf(
            cardValue(CardFieldID.Name, "Magic Keyboard"),
            cardValue(CardFieldID.Tag, "ACC-204", L10n.string("tag_label", "ACC-204")),
            labeledField(CardFieldID.ModelNumber, "A1843"),
            cardValue(CardFieldID.Status, L10n.string("status_ready_to_deploy")),
            cardValue(CardFieldID.Manufacturer, "Apple"),
            cardValue(CardFieldID.Category, "Keyboards"),
            cardValue(CardFieldID.Supplier, "Amazon"),
            cardValue(CardFieldID.Company, "Acme"),
            cardValue(CardFieldID.AssignedTo, "John Doe"),
            cardValue(CardFieldID.Location, "Brussels"),
            labeledField(CardFieldID.PurchaseDate, "12 Jan 2024"),
            labeledField(CardFieldID.PurchaseCost, "149"),
            labeledField(CardFieldID.OrderNumber, "PO-204"),
            labeledField(CardFieldID.Notes, "With numeric keypad"),
        )
        CardKind.License -> listOf(
            cardValue(CardFieldID.Name, "Adobe Photoshop"),
            cardValue(CardFieldID.Manufacturer, "Adobe"),
            cardValue(CardFieldID.Category, "Software"),
            labeledField(CardFieldID.ProductKey, "1234-5678-90AB"),
            cardValue(CardFieldID.Expiration, "31 Dec 2026", L10n.string("expires_value", "31 Dec 2026")),
            cardValue(CardFieldID.LicensedTo, "John Doe"),
            cardValue(CardFieldID.LicensedEmail, "john.doe@example.com"),
            labeledField(CardFieldID.PurchaseDate, "1 Jan 2024"),
            labeledField(CardFieldID.PurchaseCost, "263"),
            labeledField(CardFieldID.OrderNumber, "PO-PS1"),
            cardValue(CardFieldID.Supplier, "Amazon"),
            cardValue(CardFieldID.Company, "Acme"),
            yesNoField(CardFieldID.Reassignable, true),
            yesNoField(CardFieldID.Maintained, true),
            labeledField(CardFieldID.Notes, "Creative Cloud"),
        )
        CardKind.Consumable -> listOf(
            cardValue(CardFieldID.Name, "HP 205A Black Toner"),
            labeledField(CardFieldID.ItemNo, "CF530A"),
            labeledField(CardFieldID.ModelNumber, "LaserJet Pro M180"),
            cardValue(CardFieldID.Category, "Printer supplies"),
            cardValue(CardFieldID.Manufacturer, "HP"),
            cardValue(CardFieldID.Supplier, "Amazon"),
            cardValue(CardFieldID.Company, "Acme"),
            cardValue(CardFieldID.Location, "Brussels"),
            labeledField(CardFieldID.PurchaseDate, "12 Jan 2024"),
            labeledField(CardFieldID.PurchaseCost, "89"),
            labeledField(CardFieldID.OrderNumber, "PO-TNR"),
            labeledField(CardFieldID.Notes, "Black"),
        )
        CardKind.Component -> listOf(
            cardValue(CardFieldID.Name, "Samsung 980 PRO 1TB"),
            labeledField(CardFieldID.Serial, "S6B0NS0R123456"),
            labeledField(CardFieldID.ModelNumber, "MZ-V8P1T0"),
            cardValue(CardFieldID.Category, "Storage"),
            cardValue(CardFieldID.Manufacturer, "Samsung"),
            cardValue(CardFieldID.Supplier, "Amazon"),
            cardValue(CardFieldID.Company, "Acme"),
            cardValue(CardFieldID.Location, "Brussels"),
            labeledField(CardFieldID.PurchaseDate, "12 Jan 2024"),
            labeledField(CardFieldID.PurchaseCost, "129"),
            labeledField(CardFieldID.OrderNumber, "PO-SSD"),
            labeledField(CardFieldID.Notes, "NVMe SSD"),
        )
    }
}

