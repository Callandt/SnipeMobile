package com.callandt.snipemobile.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.callandt.snipemobile.data.api.SnipeActionKind
import com.callandt.snipemobile.data.api.SnipeApiClient
import com.callandt.snipemobile.data.api.SnipeListModule

/** Recomputes when account permissions or sampled list actions change. */
@Composable
fun rememberCanPerform(
    client: SnipeApiClient,
    module: SnipeListModule,
    kind: SnipeActionKind,
    serverAllows: Boolean? = null,
): Boolean {
    val permissions by client.accountPermissions.collectAsState()
    val rights by client.moduleActionRights.collectAsState()
    return permissions.allowsAction(rights, module, kind, serverAllows)
}
