package com.callandt.snipemobile.ui.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Usb
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.ui.AppViewModel
import com.callandt.snipemobile.ui.components.CardLayoutPreviewCard
import com.callandt.snipemobile.ui.components.SettingsGroupedCard
import com.callandt.snipemobile.ui.components.SettingsRow
import com.callandt.snipemobile.ui.components.SettingsSectionFooter
import com.callandt.snipemobile.ui.components.SettingsSectionHeader
import com.callandt.snipemobile.ui.components.cardFieldIcon
import com.callandt.snipemobile.ui.util.CardIcons
import com.callandt.snipemobile.ui.util.CardKind
import com.callandt.snipemobile.ui.util.CardKindSpec
import com.callandt.snipemobile.ui.util.CardSlotLayout
import com.callandt.snipemobile.ui.util.L10n

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardLayoutSettingsScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onOpenKind: (CardKind) -> Unit,
) {
    val layouts by viewModel.cardLayouts.collectAsState()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string("card_layout_settings")) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            item { SettingsSectionHeader(L10n.string("card_layout_settings")) }
            item {
                SettingsGroupedCard {
                    CardKind.entries.forEachIndexed { index, kind ->
                        val spec = CardKindSpec.spec(kind)
                        val layout = layouts.layout(kind).resolved(spec)
                        SettingsRow(
                            icon = cardKindIcon(kind),
                            iconColor = cardKindColor(kind),
                            title = L10n.string(kind.titleKey),
                            value = layoutSummary(layout),
                            onClick = { onOpenKind(kind) },
                        )
                        if (index != CardKind.entries.lastIndex) {
                            HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardLayoutKindEditorScreen(
    kind: CardKind,
    viewModel: AppViewModel,
    onBack: () -> Unit,
) {
    val layouts by viewModel.cardLayouts.collectAsState()
    val spec = remember(kind) { CardKindSpec.spec(kind) }
    val layout = layouts.layout(kind).resolved(spec)
    val unused = layout.unusedFields(spec)
    var removedFields by remember(kind) { mutableStateOf(listOf<RemovedCardField>()) }

    fun save(next: CardSlotLayout) {
        viewModel.setCardLayouts(layouts.replacing(kind, next.resolved(spec)))
    }

    fun forgetRemoved(id: String) {
        removedFields = removedFields.filterNot { it.id == id }
    }

    fun rememberRemoved(id: String, asMeta: Boolean) {
        val icon = if (asMeta) layout.icons?.get(id) else null
        removedFields = removedFields.filterNot { it.id == id } + RemovedCardField(id, asMeta, icon)
    }

    fun layoutByResetting(): CardSlotLayout {
        var next = spec.defaultLayout
        val used = mutableSetOf(next.title).apply {
            next.details.orEmpty().forEach { add(it) }
            next.meta.orEmpty().forEach { add(it) }
        }
        for (item in removedFields) {
            if (item.id in used) continue
            next = if (item.asMeta || next.details.orEmpty().size >= CardKindSpec.MaxDetailLines) {
                next.appendingMeta(item.id)
            } else {
                next.appendingDetail(item.id)
            }
            if (item.icon != null) {
                next = next.settingIcon(item.icon, item.id)
            }
            used += item.id
        }
        return next
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(L10n.string(kind.titleKey)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = L10n.string("back"))
                    }
                },
                actions = {
                    TextButton(
                        enabled = !layout.matchesDefault(spec) || removedFields.isNotEmpty(),
                        onClick = {
                            save(layoutByResetting())
                            removedFields = emptyList()
                        },
                    ) {
                        Text(L10n.string("card_layout_reset"))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            item { SettingsSectionHeader(L10n.string("card_layout_preview")) }
            item {
                CardLayoutPreviewCard(
                    kind = kind,
                    layout = layout,
                    kindIcon = cardKindIcon(kind),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }
            item { SettingsSectionHeader(L10n.string("card_layout_title_slot")) }
            item {
                SettingsGroupedCard {
                    CardFieldDropdown(
                        selectedId = layout.title,
                        fields = spec.fields,
                        onSelect = { save(layout.placingTitle(it)) },
                    )
                }
            }
            item { SettingsSectionHeader(L10n.string("card_layout_detail_slot")) }
            item {
                SettingsGroupedCard {
                    val details = layout.details.orEmpty()
                    val canAddDetail = unused.isNotEmpty() && details.size < CardKindSpec.MaxDetailLines
                    details.forEachIndexed { index, fieldId ->
                        CardFieldSlotRow(
                            selectedId = fieldId,
                            fields = spec.fields,
                            onSelect = { save(layout.replacingDetail(index, it)) },
                            onRemove = {
                                rememberRemoved(fieldId, asMeta = false)
                                save(layout.removingDetail(index))
                            },
                        )
                        if (index != details.lastIndex || canAddDetail) {
                            HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                        }
                    }
                    if (canAddDetail) {
                        AddFieldRow(
                            fields = unused,
                            onSelect = {
                                forgetRemoved(it)
                                save(layout.appendingDetail(it))
                            },
                        )
                    }
                }
                SettingsSectionFooter(L10n.string("card_layout_tap_remove_footer"))
            }
            item { SettingsSectionHeader(L10n.string("card_layout_meta_slot")) }
            item {
                SettingsGroupedCard {
                    val meta = layout.meta.orEmpty()
                    meta.forEachIndexed { index, fieldId ->
                        CardFieldSlotRow(
                            selectedId = fieldId,
                            fields = spec.fields,
                            onSelect = { save(layout.replacingMeta(index, it)) },
                            onRemove = {
                                rememberRemoved(fieldId, asMeta = true)
                                save(layout.removingMeta(index))
                            },
                            iconId = layout.icon(fieldId),
                            onSelectIcon = { save(layout.settingIcon(it, fieldId)) },
                        )
                        if (index != meta.lastIndex || unused.isNotEmpty()) {
                            HorizontalDivider(modifier = Modifier.padding(start = 16.dp))
                        }
                    }
                    if (unused.isNotEmpty()) {
                        AddFieldRow(
                            fields = unused,
                            onSelect = {
                                forgetRemoved(it)
                                save(layout.appendingMeta(it))
                            },
                        )
                    }
                }
                SettingsSectionFooter(L10n.string("card_layout_tap_remove_footer"))
            }
        }
    }
}

private data class RemovedCardField(
    val id: String,
    val asMeta: Boolean,
    val icon: String? = null,
)

private fun layoutSummary(layout: CardSlotLayout): String {
    val parts = buildList {
        add(L10n.string(CardKindSpec.labelKey(layout.title)))
        layout.details.orEmpty().forEach { add(L10n.string(CardKindSpec.labelKey(it))) }
        layout.meta.orEmpty().forEach { add(L10n.string(CardKindSpec.labelKey(it))) }
    }
    return parts.joinToString(" · ")
}

@Composable
private fun CardFieldSlotRow(
    selectedId: String,
    fields: List<String>,
    onSelect: (String) -> Unit,
    onRemove: () -> Unit,
    iconId: String? = null,
    onSelectIcon: ((String) -> Unit)? = null,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CardFieldDropdown(
            selectedId = selectedId,
            fields = fields,
            onSelect = onSelect,
            modifier = Modifier.weight(1f),
        )
        if (iconId != null && onSelectIcon != null) {
            CardIconPicker(
                selectedId = iconId,
                onSelect = onSelectIcon,
            )
        }
        IconButton(onClick = onRemove) {
            Icon(Icons.Default.Close, contentDescription = L10n.string("card_layout_remove_field"))
        }
    }
}

@Composable
private fun CardIconPicker(
    selectedId: String,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Surface(
            onClick = { expanded = true },
            shape = RoundedCornerShape(10.dp),
            color = MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier
                .padding(end = 4.dp)
                .size(40.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = cardFieldIcon(selectedId),
                    contentDescription = L10n.string("card_layout_icon"),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            Column(
                modifier = Modifier
                    .padding(8.dp)
                    .width(220.dp),
            ) {
                CardIcons.all.chunked(5).forEach { row ->
                    Row {
                        row.forEach { icon ->
                            val selected = icon == selectedId
                            Surface(
                                onClick = {
                                    expanded = false
                                    onSelect(icon)
                                },
                                shape = RoundedCornerShape(8.dp),
                                color = if (selected) {
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                                } else {
                                    Color.Transparent
                                },
                                modifier = Modifier.size(40.dp),
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Icon(
                                        imageVector = cardFieldIcon(icon),
                                        contentDescription = L10n.string(CardIcons.labelKey(icon)),
                                        tint = if (selected) {
                                            MaterialTheme.colorScheme.primary
                                        } else {
                                            MaterialTheme.colorScheme.onSurfaceVariant
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AddFieldRow(
    fields: List<String>,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box(modifier = Modifier.fillMaxWidth()) {
        TextButton(onClick = { expanded = true }) {
            Icon(Icons.Default.Add, contentDescription = null)
            Text(L10n.string("card_layout_add_field"))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            fields.forEach { fieldId ->
                DropdownMenuItem(
                    text = { Text(L10n.string(CardKindSpec.labelKey(fieldId))) },
                    onClick = {
                        expanded = false
                        onSelect(fieldId)
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CardFieldDropdown(
    selectedId: String,
    fields: List<String>,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    val label = if (selectedId.isEmpty()) {
        L10n.string("card_layout_subtitle_none")
    } else {
        L10n.string(CardKindSpec.labelKey(selectedId))
    }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        OutlinedTextField(
            modifier = Modifier
                .menuAnchor()
                .fillMaxWidth(),
            readOnly = true,
            value = label,
            onValueChange = {},
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            fields.forEach { fieldId ->
                val text = if (fieldId.isEmpty()) {
                    L10n.string("card_layout_subtitle_none")
                } else {
                    L10n.string(CardKindSpec.labelKey(fieldId))
                }
                DropdownMenuItem(
                    text = { Text(text) },
                    onClick = {
                        expanded = false
                        onSelect(fieldId)
                    },
                    trailingIcon = if (fieldId == selectedId) {
                        { Icon(Icons.Default.Check, contentDescription = null) }
                    } else {
                        null
                    },
                )
            }
        }
    }
}

private fun cardKindIcon(kind: CardKind): ImageVector = when (kind) {
    CardKind.Asset -> Icons.Default.Laptop
    CardKind.User -> Icons.Default.Person
    CardKind.Accessory -> Icons.Default.Usb
    CardKind.License -> Icons.Default.Description
    CardKind.Consumable -> Icons.Outlined.Inventory2
    CardKind.Component -> Icons.Default.Memory
}

private fun cardKindColor(kind: CardKind): Color = when (kind) {
    CardKind.Asset -> Color(0xFF007AFF)
    CardKind.User -> Color(0xFF5AC8FA)
    CardKind.Accessory -> Color(0xFFAF52DE)
    CardKind.License -> Color(0xFFFF9500)
    CardKind.Consumable -> Color(0xFF34C759)
    CardKind.Component -> Color(0xFF5856D6)
}
