package com.callandt.snipemobile.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.ui.util.CardKind
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.ui.util.resolveCard
import com.callandt.snipemobile.ui.util.userCardFields

fun userCardTitle(user: User): String {
    val name = user.decodedName.trim()
    if (name.isNotEmpty()) return name
    val first = user.decodedFirstName.trim()
    if (first.isNotEmpty()) return first
    val email = user.decodedEmail.trim()
    if (email.isNotEmpty()) return email
    return L10n.string("user")
}

@Composable
fun UserCard(
    user: User,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    onLongClick: (() -> Unit)? = null,
) {
    val resolved = resolveCard(CardKind.User, LocalCardLayouts.current, userCardFields(user))

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .then(
                if (onLongClick != null) {
                    Modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick)
                } else {
                    Modifier.clickable(onClick = onClick)
                },
            ),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurface,
        tonalElevation = 0.dp,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CardListIcon(
                    imageVector = Icons.Default.Person,
                    imagePath = user.image,
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    CardLayoutHeader(resolved = resolved)
                }
            }
            CardLayoutMeta(items = resolved.meta)
        }
    }
}
