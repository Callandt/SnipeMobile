package com.callandt.snipemobile.ui.management

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Label
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.Category
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.ViewModule
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector

/** Admin entities managed under Settings. */
enum class ManagementEntity(
    val titleKey: String,
    val icon: ImageVector,
    val iconColor: Color,
) {
    Fields("mgmt_fields", Icons.AutoMirrored.Filled.ListAlt, Color(0xFF5856D6)),
    Fieldsets("mgmt_fieldsets", Icons.Default.ViewModule, Color(0xFF32ADE6)),
    Companies("mgmt_companies", Icons.Default.Business, Color(0xFF007AFF)),
    StatusLabels("mgmt_status_labels", Icons.AutoMirrored.Filled.Label, Color(0xFF34C759)),
    Models("mgmt_models", Icons.Default.Inventory2, Color(0xFFFF9500)),
    Categories("mgmt_categories", Icons.Default.Category, Color(0xFFFFCC00)),
    Manufacturers("mgmt_manufacturers", Icons.Default.Apartment, Color(0xFF5AC8FA)),
    Suppliers("mgmt_suppliers", Icons.Default.ShoppingCart, Color(0xFFAF52DE)),
    Departments("mgmt_departments", Icons.Default.People, Color(0xFFFF2D55)),
    Groups("mgmt_groups", Icons.Default.Group, Color(0xFFFF3B30)),
}
