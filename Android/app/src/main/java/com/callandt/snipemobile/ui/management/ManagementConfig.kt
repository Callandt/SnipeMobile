package com.callandt.snipemobile.ui.management

import com.callandt.snipemobile.util.HtmlDecoder
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

enum class ManagementFieldKind {
    Text,
    Multiline,
    Url,
    Email,
    Phone,
    Number,
    Toggle,
    ColorHex,
    Picker,
}

data class ManagementFormField(
    val bodyKey: String,
    val labelKey: String,
    val kind: ManagementFieldKind,
    val required: Boolean = false,
    val createOnly: Boolean = false,
    val defaultValue: String? = null,
    val pickerOptions: List<Pair<String, String>> = emptyList(),
    val pickerSource: ManagementPickerSource? = null,
    val rowValueReader: ((JsonObject) -> String)? = null,
) {
    fun displayLabel(): String = L10n.fieldLabel(labelKey, required)
}

enum class ManagementPickerSource {
    CategoriesAsset,
    Manufacturers,
    Companies,
    Locations,
    Users,
    Fieldsets,
    StatusType,
    CategoryType,
}

/** Entity that can be created from this picker, if any. */
fun ManagementPickerSource.creatableEntity(): ManagementEntity? = when (this) {
    ManagementPickerSource.CategoriesAsset -> ManagementEntity.Categories
    ManagementPickerSource.Manufacturers -> ManagementEntity.Manufacturers
    ManagementPickerSource.Companies -> ManagementEntity.Companies
    ManagementPickerSource.Fieldsets -> ManagementEntity.Fieldsets
    ManagementPickerSource.Locations,
    ManagementPickerSource.Users,
    ManagementPickerSource.StatusType,
    ManagementPickerSource.CategoryType,
    -> null
}

fun ManagementPickerSource.creatableLocation(): Boolean =
    this == ManagementPickerSource.Locations

fun ManagementPickerSource.createDefaults(): Map<String, String> = when (this) {
    ManagementPickerSource.CategoriesAsset -> mapOf("category_type" to "asset")
    else -> emptyMap()
}

data class ManagementEntityConfig(
    val path: String,
    val singularKey: String,
    val fields: List<ManagementFormField>,
    val titleReader: (JsonObject) -> String = { ManagementValue.displayString(it["name"]) },
    val subtitleReader: ((JsonObject) -> String?)? = null,
)

object ManagementValue {
    fun scalarString(element: JsonElement?): String = when (element) {
        null, is JsonNull -> ""
        is JsonPrimitive -> when {
            element.isString -> element.content
            element.intOrNull != null -> element.intOrNull.toString()
            element.contentOrNull == "true" -> "1"
            element.contentOrNull == "false" -> "0"
            else -> element.contentOrNull.orEmpty()
        }
        else -> ""
    }

    fun displayString(element: JsonElement?): String = HtmlDecoder.decode(scalarString(element))

    fun nestedId(row: JsonObject, key: String): String {
        row[key]?.jsonObject?.get("id")?.jsonPrimitive?.intOrNull?.let { return it.toString() }
        row[key]?.jsonPrimitive?.intOrNull?.let { return it.toString() }
        row[key]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { return it }
        return ""
    }

    fun nestedName(row: JsonObject, key: String): String? {
        val name = row[key]?.jsonObject?.get("name")?.jsonPrimitive?.contentOrNull
        return name?.takeIf { it.isNotEmpty() }?.let { HtmlDecoder.decode(it) }
    }

    fun boolString(element: JsonElement?): String = when (scalarString(element).lowercase()) {
        "1", "true" -> "1"
        else -> "0"
    }
}

fun ManagementEntity.config(): ManagementEntityConfig = when (this) {
    ManagementEntity.Companies -> ManagementEntityConfig(
        path = "/api/v1/companies",
        singularKey = "mgmt_company_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField("phone", "phone", ManagementFieldKind.Phone),
            ManagementFormField("fax", "mgmt_fax", ManagementFieldKind.Phone),
            ManagementFormField("email", "email", ManagementFieldKind.Email),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
    )

    ManagementEntity.Manufacturers -> ManagementEntityConfig(
        path = "/api/v1/manufacturers",
        singularKey = "mgmt_manufacturer_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField("url", "url", ManagementFieldKind.Url),
            ManagementFormField("support_url", "mgmt_support_url", ManagementFieldKind.Url),
            ManagementFormField("support_phone", "mgmt_support_phone", ManagementFieldKind.Phone),
            ManagementFormField("support_email", "mgmt_support_email", ManagementFieldKind.Email),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
    )

    ManagementEntity.Suppliers -> ManagementEntityConfig(
        path = "/api/v1/suppliers",
        singularKey = "mgmt_supplier_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField("contact", "mgmt_contact", ManagementFieldKind.Text),
            ManagementFormField("address", "address", ManagementFieldKind.Text),
            ManagementFormField("city", "city", ManagementFieldKind.Text),
            ManagementFormField("phone", "phone", ManagementFieldKind.Phone),
            ManagementFormField("email", "email", ManagementFieldKind.Email),
            ManagementFormField("url", "url", ManagementFieldKind.Url),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
        subtitleReader = { row ->
            ManagementValue.displayString(row["city"]).takeIf { it.isNotEmpty() }
        },
    )

    ManagementEntity.Categories -> ManagementEntityConfig(
        path = "/api/v1/categories",
        singularKey = "mgmt_category_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField(
                bodyKey = "category_type",
                labelKey = "mgmt_category_type",
                kind = ManagementFieldKind.Picker,
                required = true,
                defaultValue = "asset",
                pickerSource = ManagementPickerSource.CategoryType,
                rowValueReader = { ManagementValue.scalarString(it["category_type"]).lowercase() },
            ),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
        subtitleReader = { row ->
            categoryTypeLabel(ManagementValue.scalarString(row["category_type"]).lowercase())
        },
    )

    ManagementEntity.StatusLabels -> ManagementEntityConfig(
        path = "/api/v1/statuslabels",
        singularKey = "mgmt_status_label_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField(
                bodyKey = "type",
                labelKey = "mgmt_status_type",
                kind = ManagementFieldKind.Picker,
                required = true,
                defaultValue = "deployable",
                pickerSource = ManagementPickerSource.StatusType,
                rowValueReader = { ManagementValue.scalarString(it["type"]).lowercase() },
            ),
            ManagementFormField("color", "mgmt_color", ManagementFieldKind.ColorHex, defaultValue = "AA3399"),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
        subtitleReader = { row ->
            statusTypeLabel(ManagementValue.scalarString(row["type"]).lowercase())
        },
    )

    ManagementEntity.Models -> ManagementEntityConfig(
        path = "/api/v1/models",
        singularKey = "mgmt_model_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField(
                bodyKey = "category_id",
                labelKey = "category",
                kind = ManagementFieldKind.Picker,
                required = true,
                pickerSource = ManagementPickerSource.CategoriesAsset,
                rowValueReader = { ManagementValue.nestedId(it, "category") },
            ),
            ManagementFormField(
                bodyKey = "manufacturer_id",
                labelKey = "manufacturer",
                kind = ManagementFieldKind.Picker,
                pickerSource = ManagementPickerSource.Manufacturers,
                rowValueReader = { ManagementValue.nestedId(it, "manufacturer") },
            ),
            ManagementFormField(
                bodyKey = "fieldset_id",
                labelKey = "mgmt_fieldset",
                kind = ManagementFieldKind.Picker,
                pickerSource = ManagementPickerSource.Fieldsets,
                rowValueReader = { ManagementValue.nestedId(it, "fieldset") },
            ),
            ManagementFormField("model_number", "model_number", ManagementFieldKind.Text),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
        subtitleReader = { row ->
            ManagementValue.displayString(row["model_number"]).takeIf { it.isNotEmpty() }
                ?: ManagementValue.nestedName(row, "category")
        },
    )

    ManagementEntity.Departments -> ManagementEntityConfig(
        path = "/api/v1/departments",
        singularKey = "mgmt_department_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField(
                bodyKey = "company_id",
                labelKey = "company",
                kind = ManagementFieldKind.Picker,
                pickerSource = ManagementPickerSource.Companies,
                rowValueReader = { ManagementValue.nestedId(it, "company") },
            ),
            ManagementFormField(
                bodyKey = "location_id",
                labelKey = "location",
                kind = ManagementFieldKind.Picker,
                pickerSource = ManagementPickerSource.Locations,
                rowValueReader = { ManagementValue.nestedId(it, "location") },
            ),
            ManagementFormField("phone", "phone", ManagementFieldKind.Phone),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
        subtitleReader = { row -> ManagementValue.nestedName(row, "company") },
    )

    ManagementEntity.Groups -> ManagementEntityConfig(
        path = "/api/v1/groups",
        singularKey = "mgmt_group_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
    )

    ManagementEntity.Fieldsets -> ManagementEntityConfig(
        path = "/api/v1/fieldsets",
        singularKey = "mgmt_fieldset_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
        ),
    )

    ManagementEntity.Fields -> ManagementEntityConfig(
        path = "/api/v1/fields",
        singularKey = "mgmt_field_one",
        fields = listOf(
            ManagementFormField("name", "name", ManagementFieldKind.Text, required = true),
            ManagementFormField(
                bodyKey = "element",
                labelKey = "mgmt_element",
                kind = ManagementFieldKind.Picker,
                required = true,
                defaultValue = "text",
                pickerOptions = listOf(
                    "text" to "Text",
                    "textarea" to "Textarea",
                    "listbox" to "Listbox",
                    "checkbox" to "Checkbox",
                    "radio" to "Radio",
                ),
                rowValueReader = {
                    ManagementValue.scalarString(it["type"] ?: it["element"]).lowercase()
                },
            ),
            ManagementFormField("help_text", "mgmt_help_text", ManagementFieldKind.Text),
            ManagementFormField("notes", "notes", ManagementFieldKind.Multiline),
        ),
        subtitleReader = { row ->
            ManagementValue.scalarString(row["type"] ?: row["element"]).replaceFirstChar { it.uppercase() }
                .takeIf { it.isNotEmpty() }
        },
    )
}

fun ManagementFormField.currentValue(row: JsonObject): String {
    val raw = rowValueReader?.invoke(row)
        ?: ManagementValue.scalarString(row[bodyKey])
    return when (kind) {
        ManagementFieldKind.Text, ManagementFieldKind.Multiline, ManagementFieldKind.Url,
        ManagementFieldKind.Email, ManagementFieldKind.Phone,
        -> ManagementValue.displayString(JsonPrimitive(raw))
        else -> raw
    }
}

fun statusTypeLabel(type: String): String? = when (type) {
    "deployable", "pending", "undeployable", "archived" -> L10n.string("status_type_$type")
    else -> type.takeIf { it.isNotEmpty() }
}

fun categoryTypeLabel(type: String): String? = when (type) {
    "asset", "accessory", "consumable", "component", "license" -> L10n.string("category_type_$type")
    else -> type.takeIf { it.isNotEmpty() }
}

fun statusTypeOptions(): List<Pair<String, String>> = listOf(
    "deployable" to L10n.string("status_type_deployable"),
    "pending" to L10n.string("status_type_pending"),
    "undeployable" to L10n.string("status_type_undeployable"),
    "archived" to L10n.string("status_type_archived"),
)

fun categoryTypeOptions(): List<Pair<String, String>> = listOf(
    "asset" to L10n.string("category_type_asset"),
    "accessory" to L10n.string("category_type_accessory"),
    "consumable" to L10n.string("category_type_consumable"),
    "component" to L10n.string("category_type_component"),
    "license" to L10n.string("category_type_license"),
)
