package com.callandt.snipemobile.ui.util

import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.mapSaver
import androidx.compose.runtime.saveable.rememberSaveable

/** Keep sort/filter when leaving a list. */
val ListSortSaver: Saver<ListSort, Any> = listSaver(
    save = { listOf(it.field.name, it.order.name) },
    restore = { raw ->
        val field = runCatching { ListSortField.valueOf(raw[0] as String) }.getOrNull()
            ?: return@listSaver null
        val order = runCatching { ListSortOrder.valueOf(raw[1] as String) }.getOrNull()
            ?: return@listSaver null
        ListSort(field, order)
    },
)

val ListFilterSaver: Saver<ListFilter, Any> = mapSaver(
    save = { it.selections },
    restore = { saved ->
        ListFilter(
            selections = saved.mapNotNull { (key, value) ->
                (value as? String)?.let { key to it }
            }.toMap(),
        )
    },
)

val AssetFilterSaver: Saver<AssetFilter, Any> = listSaver(
    save = { filter ->
        val (kind, id) = when (val selection = filter.statusSelection) {
            AssetStatusSelection.All -> "all" to ""
            AssetStatusSelection.ReadyToDeploy -> "rtd" to ""
            AssetStatusSelection.Deployed -> "deployed" to ""
            is AssetStatusSelection.Status -> "status" to selection.id.toString()
        }
        listOf(
            kind,
            id,
            filter.category.orEmpty(),
            filter.model.orEmpty(),
            filter.manufacturer.orEmpty(),
            filter.location.orEmpty(),
        )
    },
    restore = { raw ->
        val status = when (raw[0] as? String) {
            "rtd" -> AssetStatusSelection.ReadyToDeploy
            "deployed" -> AssetStatusSelection.Deployed
            "status" -> {
                val id = (raw[1] as? String)?.toIntOrNull() ?: return@listSaver null
                AssetStatusSelection.Status(id)
            }
            else -> AssetStatusSelection.All
        }
        AssetFilter(
            statusSelection = status,
            category = (raw.getOrNull(2) as? String).savedToOptional(),
            model = (raw.getOrNull(3) as? String).savedToOptional(),
            manufacturer = (raw.getOrNull(4) as? String).savedToOptional(),
            location = (raw.getOrNull(5) as? String).savedToOptional(),
        )
    },
)

private fun String?.savedToOptional(): String? = this?.takeIf { it.isNotEmpty() }

@Composable
fun rememberSaveableListSort(
    initial: ListSort,
    key: String? = null,
): MutableState<ListSort> =
    rememberSaveable(key = key, stateSaver = ListSortSaver) { mutableStateOf(initial) }

@Composable
fun rememberSaveableListFilter(
    initial: ListFilter = ListFilter(),
    key: String? = null,
): MutableState<ListFilter> =
    rememberSaveable(key = key, stateSaver = ListFilterSaver) { mutableStateOf(initial) }

@Composable
fun rememberSaveableAssetFilter(
    initial: AssetFilter = AssetFilter(),
    key: String? = null,
): MutableState<AssetFilter> =
    rememberSaveable(key = key, stateSaver = AssetFilterSaver) { mutableStateOf(initial) }

@Composable
inline fun <reified T : Enum<T>> rememberSaveableEnum(
    initial: T,
    key: String? = null,
): MutableState<T> =
    rememberSaveable(
        key = key,
        stateSaver = Saver(
            save = { it.name },
            restore = { runCatching { enumValueOf<T>(it) }.getOrDefault(initial) },
        ),
    ) { mutableStateOf(initial) }
