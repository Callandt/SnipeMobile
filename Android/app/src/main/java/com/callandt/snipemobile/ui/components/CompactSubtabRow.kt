package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Equal-width subtabs. */
@Composable
fun CompactSubtabRow(
    selectedIndex: Int,
    titles: List<String>,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (titles.size <= 1) return
    TabRow(
        selectedTabIndex = selectedIndex.coerceIn(0, titles.lastIndex),
        modifier = modifier
            .fillMaxWidth()
            .padding(bottom = 4.dp),
    ) {
        titles.forEachIndexed { index, title ->
            Tab(
                selected = selectedIndex == index,
                onClick = { onSelect(index) },
                text = { Text(title) },
            )
        }
    }
}
