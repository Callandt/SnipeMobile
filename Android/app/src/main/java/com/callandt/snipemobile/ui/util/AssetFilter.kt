package com.callandt.snipemobile.ui.util

import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.StatusLabel

sealed class AssetStatusSelection {
    data object All : AssetStatusSelection()
    data object Deployed : AssetStatusSelection()
    data class Status(val id: Int) : AssetStatusSelection()
}

data class AssetFilter(
    val statusSelection: AssetStatusSelection = AssetStatusSelection.All,
    val category: String? = null,
    val model: String? = null,
    val manufacturer: String? = null,
    val location: String? = null,
) {
    val isStatusActive: Boolean get() = statusSelection !is AssetStatusSelection.All

    val isActive: Boolean
        get() = isStatusActive || category != null || model != null ||
            manufacturer != null || location != null

    val activeCount: Int
        get() {
            var count = listOfNotNull(category, model, manufacturer, location).size
            if (isStatusActive) count += 1
            return count
        }

    fun clear(): AssetFilter = AssetFilter()

    fun matches(asset: Asset, statusLabels: List<StatusLabel> = emptyList()): Boolean {
        when (val selection = statusSelection) {
            AssetStatusSelection.All -> Unit
            AssetStatusSelection.Deployed -> if (asset.assignedTo == null) return false
            is AssetStatusSelection.Status -> {
                if (asset.statusLabel.id != selection.id) return false
                val selected = statusLabels.firstOrNull { it.id == selection.id }
                if (selected != null && AssetStatusFilterSupport.isReadyToDeployLabel(selected)) {
                    if (asset.assignedTo != null) return false
                    if (!AssetStatusFilterSupport.isDeployable(asset)) return false
                }
            }
        }
        if (category != null && asset.decodedCategoryName != category) return false
        if (model != null && asset.decodedModelName != model) return false
        if (manufacturer != null && asset.decodedManufacturerName != manufacturer) return false
        if (location != null && asset.decodedLocationName != location) return false
        return true
    }
}

data class AssetFilterOptions(
    val statusLabels: List<StatusLabel>,
    val showDeployed: Boolean,
    val categories: List<String>,
    val models: List<String>,
    val manufacturers: List<String>,
    val locations: List<String>,
) {
    val hasFilterOptions: Boolean
        get() = showDeployed || statusLabels.isNotEmpty() || categories.isNotEmpty() ||
            models.isNotEmpty() || manufacturers.isNotEmpty() || locations.isNotEmpty()

    val hasStatusOptions: Boolean
        get() = showDeployed || statusLabels.isNotEmpty()

    companion object {
        fun from(
            assets: List<Asset>,
            statusLabels: List<StatusLabel>,
        ): AssetFilterOptions {
            val showDeployed = assets.any { it.assignedTo != null }
            val labels = if (statusLabels.isNotEmpty()) {
                AssetStatusFilterSupport.sortedStatusLabels(statusLabels)
            } else {
                val seen = mutableSetOf<Int>()
                assets.mapNotNull { asset ->
                    val id = asset.statusLabel.id
                    if (seen.add(id)) asset.statusLabel else null
                }.let { AssetStatusFilterSupport.sortedStatusLabels(it) }
            }
            return AssetFilterOptions(
                statusLabels = labels,
                showDeployed = showDeployed,
                categories = distinctFilterValues(assets.map { it.decodedCategoryName }),
                models = distinctFilterValues(assets.map { it.decodedModelName }),
                manufacturers = distinctFilterValues(assets.map { it.decodedManufacturerName }),
                locations = distinctFilterValues(assets.map { it.decodedLocationName }),
            )
        }

        private fun distinctFilterValues(values: List<String>): List<String> =
            values.map { it.trim() }
                .filter { it.isNotEmpty() }
                .distinct()
                .sortedBy { it.lowercase() }
    }
}

object AssetStatusFilterSupport {
    fun isReadyToDeployLabel(label: StatusLabel): Boolean =
        label.statusMeta?.trim()?.lowercase() == "ready_to_deploy"

    fun isDeployable(asset: Asset): Boolean =
        (asset.statusLabel.type?.lowercase() ?: "deployable") == "deployable"

    fun displayName(label: StatusLabel): String {
        val meta = label.statusMeta?.trim().orEmpty()
        if (meta.isNotEmpty()) return L10n.statusLabel(meta)
        return label.decodedName
    }

    fun sortedStatusLabels(labels: List<StatusLabel>): List<StatusLabel> =
        labels.sortedBy { displayName(it).lowercase() }
}
